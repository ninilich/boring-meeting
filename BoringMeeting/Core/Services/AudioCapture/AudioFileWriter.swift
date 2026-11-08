import Foundation
import AVFoundation

/// Writes audio buffers to CAF file with Apple Lossless compression
class AudioFileWriter {
    
    // MARK: - Private Properties
    
    private var audioFile: AVAudioFile?
    private let fileURL: URL
    private var isWriting = false
    private var totalFramesWritten: AVAudioFrameCount = 0
    
    /// Queue for sequential writes
    private let writeQueue = DispatchQueue(
        label: "org.ninil.boringmeeting.audiowriter",
        qos: .userInitiated
    )
    
    /// Audio format for the file
    private let fileFormat: AVAudioFormat

    /// Called on the write queue when a buffer fails to write to disk
    var onWriteError: ((Error) -> Void)?
    
    // MARK: - Initialization
    
    init(url: URL, sampleRate: Double, channels: AVAudioChannelCount) throws {
        self.fileURL = url
        
        // Use PCM Int16 format (compatible with microphone and ALAC)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioCaptureError.invalidAudioFormat
        }
        
        self.fileFormat = format
    }
    
    deinit {
        finalize()
    }
    
    // MARK: - Public Methods
    
    /// Start writing to file
    func start() throws {
        guard !isWriting else {
            throw AudioCaptureError.alreadyRecording
        }
        
        // Settings for CAF + Apple Lossless
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: fileFormat.sampleRate,
            AVNumberOfChannelsKey: fileFormat.channelCount,
            AVEncoderBitDepthHintKey: 16
        ]
        
        do {
            // Create CAF file - use Float32 for microphone input
            audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            
            isWriting = true
            totalFramesWritten = 0
            
            print("✅ Audio file created: \(fileURL.lastPathComponent)")
            
        } catch {
            throw AudioCaptureError.fileCreationFailed(error.localizedDescription)
        }
    }
    
    /// Write audio buffer to file
    func write(_ buffer: AVAudioPCMBuffer) {
        guard isWriting, let file = audioFile else { return }
        guard buffer.frameLength > 0 else { return }
        
        writeQueue.async { [weak self] in
            do {
                try file.write(from: buffer)
                self?.totalFramesWritten += buffer.frameLength
            } catch {
                print("❌ Audio write error: \(error.localizedDescription)")
                self?.onWriteError?(error)
            }
        }
    }
    
    /// Finalize and close the file
    func finalize() {
        guard isWriting else { return }
        
        // Wait for all writes to complete
        writeQueue.sync {
            audioFile = nil
        }
        
        isWriting = false
        
        let duration = Double(totalFramesWritten) / fileFormat.sampleRate
        print("✅ Recording finalized: \(String(format: "%.1f", duration))s, \(totalFramesWritten) frames")
    }
    
    /// Get total recording duration
    var duration: TimeInterval {
        return Double(totalFramesWritten) / fileFormat.sampleRate
    }
    
    /// Get file size in bytes
    var fileSize: Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
}
