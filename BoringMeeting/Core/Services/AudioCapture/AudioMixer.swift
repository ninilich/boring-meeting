import Foundation
import AVFoundation

/// Mixes microphone and system audio files offline after recording
class AudioMixer {
    
    // MARK: - Public Methods
    
    /// Mix microphone and system audio files
    /// - Parameters:
    ///   - micURL: URL to mic.caf file
    ///   - systemURL: URL to system.caf file
    ///   - outputURL: URL for mixed.caf output
    ///   - micGain: Microphone gain (0.0-1.0, default 0.5)
    ///   - systemGain: System audio gain (0.0-1.0, default 0.5)
    static func mix(
        micURL: URL,
        systemURL: URL,
        outputURL: URL,
        micGain: Float = 0.5,
        systemGain: Float = 0.5
    ) async throws {
        // Run on background thread to avoid blocking UI
        try await Task.detached {
            try Self.mixSync(
                micURL: micURL,
                systemURL: systemURL,
                outputURL: outputURL,
                micGain: micGain,
                systemGain: systemGain
            )
        }.value
    }
    
    /// Synchronous mixing implementation (run on background thread)
    private nonisolated static func mixSync(
        micURL: URL,
        systemURL: URL,
        outputURL: URL,
        micGain: Float = 0.5,
        systemGain: Float = 0.5
    ) throws {
        print("🎚️ Mixing audio files...")
        
        // Open input files
        let micFile = try AVAudioFile(forReading: micURL)
        let systemFile = try AVAudioFile(forReading: systemURL)

        let micDurationSeconds = Double(micFile.length) / micFile.fileFormat.sampleRate
        let systemDurationSeconds = Double(systemFile.length) / systemFile.fileFormat.sampleRate
        let shorterDuration = min(micDurationSeconds, systemDurationSeconds)
        let longerDuration = max(micDurationSeconds, systemDurationSeconds)
        let durationRatio = shorterDuration > 0 ? (longerDuration / shorterDuration) : 1

        let shouldClampToShorterDuration = durationRatio > 1.2

        if shouldClampToShorterDuration {
            print("⚠️ Source duration mismatch detected (mic: \(String(format: "%.1f", micDurationSeconds))s, system: \(String(format: "%.1f", systemDurationSeconds))s). Clamping mix to shorter source.")
        }

        diagnosticLog("Input files:")
        diagnosticLog("- mic fileFormat: \(describe(format: micFile.fileFormat))")
        diagnosticLog("- mic processingFormat: \(describe(format: micFile.processingFormat))")
        diagnosticLog("- mic length: \(micFile.length) frames, \(String(format: "%.3f", micDurationSeconds))s")
        diagnosticLog("- system fileFormat: \(describe(format: systemFile.fileFormat))")
        diagnosticLog("- system processingFormat: \(describe(format: systemFile.processingFormat))")
        diagnosticLog("- system length: \(systemFile.length) frames, \(String(format: "%.3f", systemDurationSeconds))s")
        
        // Target format: 48kHz stereo (system audio format)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidAudioFormat
        }
        
        // Create converter for microphone (likely 16kHz mono -> 48kHz stereo)
        guard let micConverter = AVAudioConverter(
            from: micFile.processingFormat,
            to: targetFormat
        ) else {
            throw AudioCaptureError.invalidAudioFormat
        }
        
        // Settings for output CAF + Apple Lossless
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitDepthHintKey: 16
        ]
        
        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        
        // Buffer size: 0.1 second at 48kHz
        let bufferSize: AVAudioFrameCount = 4800
        let micInputBufferSize = max(
            AVAudioFrameCount((micFile.processingFormat.sampleRate * 0.1).rounded()),
            1
        )
        let micToTargetRatio = targetFormat.sampleRate / micFile.processingFormat.sampleRate

        let maxOutputFrames: AVAudioFrameCount?
        if shouldClampToShorterDuration {
            maxOutputFrames = AVAudioFrameCount((shorterDuration * targetFormat.sampleRate).rounded())
        } else {
            maxOutputFrames = nil
        }

        diagnosticLog("Target format: \(describe(format: targetFormat))")
        diagnosticLog("micInputBufferSize=\(micInputBufferSize), systemBufferSize=\(bufferSize), micToTargetRatio=\(String(format: "%.6f", micToTargetRatio))")
        if let maxOutputFrames {
            diagnosticLog("Clamp enabled: maxOutputFrames=\(maxOutputFrames), maxDuration=\(String(format: "%.3f", Double(maxOutputFrames) / targetFormat.sampleRate))s")
        }
        
        var totalFrames: AVAudioFrameCount = 0
        var isProcessing = true
        var iteration = 0
        
        while isProcessing {
            iteration += 1
            // Read from mic file
            guard let micBuffer = AVAudioPCMBuffer(
                pcmFormat: micFile.processingFormat,
                frameCapacity: micInputBufferSize
            ) else { break }
            
            do {
                try micFile.read(into: micBuffer)
            } catch {
                // End of file
                isProcessing = false
                break
            }
            
            if micBuffer.frameLength == 0 {
                isProcessing = false
                break
            }
            
            // Convert mic to target format (resample + mono->stereo)
            let convertedCapacity = max(
                AVAudioFrameCount(Double(micBuffer.frameLength) * micToTargetRatio) + 1,
                bufferSize
            )

            guard let convertedMicBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: convertedCapacity
            ) else { break }
            
            var error: NSError?
            nonisolated(unsafe) var inputProvided = false

            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if inputProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }

                inputProvided = true
                outStatus.pointee = .haveData
                return micBuffer
            }
            
            let conversionStatus = micConverter.convert(
                to: convertedMicBuffer,
                error: &error,
                withInputFrom: inputBlock
            )

            if conversionStatus == .error || error != nil {
                throw AudioCaptureError.writeError(
                    "Mic conversion failed: \(error?.localizedDescription ?? "unknown error")"
                )
            }

            if convertedMicBuffer.frameLength == 0 {
                isProcessing = false
                break
            }
            
            // Read from system file
            guard let systemBuffer = AVAudioPCMBuffer(
                pcmFormat: systemFile.processingFormat,
                frameCapacity: bufferSize
            ) else { break }
            
            try? systemFile.read(into: systemBuffer)

            // System file might be shorter or at EOF; pad with silence to mic chunk length
            if systemBuffer.frameLength < convertedMicBuffer.frameLength {
                padBufferWithSilence(
                    systemBuffer,
                    targetFrameLength: convertedMicBuffer.frameLength
                )
            }
            
            // Mix buffers
            let mixedBuffer = mixBuffers(
                mic: convertedMicBuffer,
                system: systemBuffer,
                micGain: micGain,
                systemGain: systemGain
            )
            
            // Write to output
            try outputFile.write(from: mixedBuffer)
            totalFrames += mixedBuffer.frameLength

            if shouldEmitIterationDiagnostics(iteration: iteration) {
                diagnosticLog(
                    "iter=\(iteration) micIn=\(micBuffer.frameLength) micOut=\(convertedMicBuffer.frameLength) " +
                    "sys=\(systemBuffer.frameLength) mixed=\(mixedBuffer.frameLength) total=\(totalFrames)"
                )
            }

            if let maxOutputFrames, totalFrames >= maxOutputFrames {
                isProcessing = false
                diagnosticLog("Stopped by clamp at totalFrames=\(totalFrames)")
            }
        }
        
        let duration = Double(totalFrames) / 48000.0
        print("✅ Mixed audio: \(String(format: "%.1f", duration))s, \(totalFrames) frames")
        diagnosticLog("Mix completed in \(iteration) iterations")
    }
    
    // MARK: - Private Methods
    
    /// Mix two audio buffers with gain control
    private nonisolated static func mixBuffers(
        mic: AVAudioPCMBuffer,
        system: AVAudioPCMBuffer,
        micGain: Float,
        systemGain: Float
    ) -> AVAudioPCMBuffer {
        let frameLength = max(mic.frameLength, system.frameLength)
        
        guard let mixedBuffer = AVAudioPCMBuffer(
            pcmFormat: mic.format,
            frameCapacity: frameLength
        ) else {
            return mic
        }
        
        mixedBuffer.frameLength = frameLength
        
        let channelCount = Int(mic.format.channelCount)
        
        guard let micData = mic.floatChannelData,
              let systemData = system.floatChannelData,
              let mixedData = mixedBuffer.floatChannelData else {
            return mic
        }

        let micFrames = Int(mic.frameLength)
        let systemFrames = Int(system.frameLength)
        
        for channel in 0..<channelCount {
            let micSamples = micData[channel]
            let systemSamples = systemData[channel]
            let mixedSamples = mixedData[channel]
            
            for frame in 0..<Int(frameLength) {
                let micSample: Float = frame < micFrames ? micSamples[frame] : 0
                let systemSample: Float = frame < systemFrames ? systemSamples[frame] : 0
                mixedSamples[frame] = (micSample * micGain) + (systemSample * systemGain)
            }
        }
        
        return mixedBuffer
    }

    private nonisolated static func padBufferWithSilence(
        _ buffer: AVAudioPCMBuffer,
        targetFrameLength: AVAudioFrameCount
    ) {
        guard targetFrameLength <= buffer.frameCapacity else { return }
        guard let channels = buffer.floatChannelData else { return }

        let currentFrames = Int(buffer.frameLength)
        let targetFrames = Int(targetFrameLength)
        if targetFrames <= currentFrames { return }

        let framesToZero = targetFrames - currentFrames
        let channelCount = Int(buffer.format.channelCount)

        for channel in 0..<channelCount {
            channels[channel].advanced(by: currentFrames).initialize(repeating: 0, count: framesToZero)
        }

        buffer.frameLength = targetFrameLength
    }

    private nonisolated static func describe(format: AVAudioFormat) -> String {
        "sampleRate=\(String(format: "%.1f", format.sampleRate))Hz channels=\(format.channelCount) commonFormat=\(format.commonFormat.rawValue) interleaved=\(format.isInterleaved)"
    }

    private nonisolated static func shouldEmitIterationDiagnostics(iteration: Int) -> Bool {
        iteration <= 5 || iteration % 100 == 0
    }

    private nonisolated static func diagnosticLog(_ message: String) {
        guard AppSettings.isDebugLogsEnabled else { return }
        print("🧪 [AudioMixer] \(message)")
    }
}
