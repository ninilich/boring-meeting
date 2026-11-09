import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

/// Captures system audio using ScreenCaptureKit
@MainActor
class SystemAudioCapture: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isCapturing = false
    
    // MARK: - Private Properties
    
    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    
    /// Callback for captured audio buffers (same interface as MicrophoneCapture)
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    
    /// System audio format (usually 48kHz stereo)
    private(set) var audioFormat: AVAudioFormat?
    
    /// Recording format - 48kHz stereo Float32
    private(set) var recordingFormat: AVAudioFormat?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    deinit {
        // Synchronous cleanup only - can't use async in deinit
        stream?.stopCapture()
        stream = nil
        streamOutput = nil
    }
    
    // MARK: - Public Methods
    
    /// Start capturing system audio
    /// System will automatically show Screen Recording permission dialog if needed
    func start() async throws {
        guard !isCapturing else {
            throw AudioCaptureError.alreadyRecording
        }
        
        print("🔊 Starting system audio capture...")
        
        // Get shareable content
        let content: SCShareableContent
        if #available(macOS 14.0, *) {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } else {
            content = try await SCShareableContent.current
        }
        
        // Get main display
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }
        
        // Configure to capture system audio only (no display)
        let config = SCStreamConfiguration()
        
        // Audio settings
        config.capturesAudio = true
        config.sampleRate = 48000  // Standard system audio rate
        config.channelCount = 2    // Stereo
        
        // Keep valid display dimensions to avoid SCStream start failures
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        print("🔊 Stream config: \(config.sampleRate)Hz, \(config.channelCount)ch, \(config.width)x\(config.height)")
        print("🖥️ Capture display ID: \(display.displayID)")
        
        // Create filter - capture display for audio
        let filter = SCContentFilter(
            display: display,
            excludingWindows: []
        )
        
        // Create stream
        let newStream = SCStream(
            filter: filter,
            configuration: config,
            delegate: nil
        )
        
        // Create output handler
        let output = SystemAudioStreamOutput()
        output.onAudioBuffer = { [weak self] buffer, time in
            self?.onAudioBuffer?(buffer, time)
        }
        
        // Add audio output
        try newStream.addStreamOutput(
            output,
            type: SCStreamOutputType.audio,
            sampleHandlerQueue: DispatchQueue(
                label: "org.ninil.boringmeeting.systemaudio",
                qos: .userInitiated
            )
        )
        
        // Store references
        self.stream = newStream
        self.streamOutput = output
        
        // Start streaming
        print("🔊 Starting SCStream.startCapture()...")
        try await newStream.startCapture()
        
        isCapturing = true
        
        // System audio is typically 48kHz stereo
        if let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        ) {
            self.audioFormat = format
            self.recordingFormat = format
            print("🔊 Format: 48000Hz, 2ch (system audio)")
        }
        
        print("✅ System audio capture started")
    }
    
    /// Stop capturing system audio
    /// Stop capturing system audio
    func stop() {
        guard isCapturing else { return }
        
        // Stop stream synchronously (safe to call from deinit)
        stream?.stopCapture()
        
        // Clean up
        stream = nil
        streamOutput = nil
        audioFormat = nil
        isCapturing = false
        
        print("✅ System audio stopped")
    }
}

// MARK: - Stream Output Handler

private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var convertedBufferCount: Int = 0
    private var conversionWarningCount: Int = 0
    
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let pcmBuffer = convertToAudioBuffer(sampleBuffer) else {
            return
        }
        
        // Extract timing information
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let audioTime = AVAudioTime(
            hostTime: mach_absolute_time(),
            sampleTime: AVAudioFramePosition(presentationTime.value),
            atRate: 48000
        )
        
        onAudioBuffer?(pcmBuffer, audioTime)
    }
    
    /// Convert CMSampleBuffer to AVAudioPCMBuffer
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        
        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = audioStreamBasicDescription else {
            return nil
        }
        
        // Source format as delivered by ScreenCaptureKit
        guard let sourceFormat = AVAudioFormat(streamDescription: asbd) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return nil
        }

        // Copy PCM data directly into AVAudioPCMBuffer memory
        guard let sourcePCMBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        sourcePCMBuffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: sourcePCMBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            logConversionWarning("Failed to copy PCM data from CMSampleBuffer: \(status)")
            return nil
        }

        // Normalize to Float32 + non-interleaved so writer and mixer receive stable buffers
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ) else {
            return nil
        }

        let needsConversion =
            sourceFormat.commonFormat != .pcmFormatFloat32 ||
            sourceFormat.isInterleaved ||
            sourceFormat.channelCount != targetFormat.channelCount ||
            sourceFormat.sampleRate != targetFormat.sampleRate

        guard needsConversion else {
            return sourcePCMBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            logConversionWarning("Failed to create AVAudioConverter for \(sourceFormat) -> \(targetFormat)")
            return nil
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let targetCapacity = max(AVAudioFrameCount(Double(frameCount) * ratio) + 1, 1)

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            return nil
        }

        var conversionError: NSError?
        var providedInput = false

        let conversionStatus = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            if providedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            providedInput = true
            outStatus.pointee = .haveData
            return sourcePCMBuffer
        }

        if conversionStatus == .error || conversionError != nil {
            logConversionWarning("AVAudioConverter failed: \(conversionError?.localizedDescription ?? "unknown error")")
            return nil
        }

        if targetBuffer.frameLength == 0 {
            logConversionWarning("AVAudioConverter produced empty buffer")
            return nil
        }

        convertedBufferCount += 1
        if convertedBufferCount % 100 == 0 {
            print("🔊 Converted system audio buffers: \(convertedBufferCount)")
        }
        
        return targetBuffer
    }

    private func logConversionWarning(_ message: String) {
        conversionWarningCount += 1
        if conversionWarningCount <= 10 || conversionWarningCount % 100 == 0 {
            print("⚠️ \(message)")
        }
    }
}
