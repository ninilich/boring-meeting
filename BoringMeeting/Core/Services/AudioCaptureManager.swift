import Foundation
import AVFoundation
import Combine

/// Manages dual audio recording (microphone + system audio)
/// Records to folder structure: recording_<timestamp>/mic.caf, system.caf, mixed.caf
@MainActor
class AudioCaptureManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether recording is currently active
    @Published var isRecording = false
    
    /// Current recording duration in seconds
    @Published var duration: TimeInterval = 0
    
    /// Microphone input level (0.0 - 1.0)
    @Published var inputLevel: Float = 0.0
    
    /// Error message if something goes wrong
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    /// Microphone capture
    private var micCapture: MicrophoneCapture?
    
    /// System audio capture
    private var systemCapture: SystemAudioCapture?
    
    /// Microphone file writer
    private var micWriter: AudioFileWriter?
    
    /// System audio file writer
    private var systemWriter: AudioFileWriter?
    
    /// Current recording folder URL
    private var recordingFolderURL: URL?
    
    /// Timer for tracking duration
    private var durationTimer: Timer?
    
    /// Recording start time
    private var startTime: Date?

    /// Callback when any active audio source stops delivering buffers
    var onSourceDropoutDetected: ((String) -> Void)?

    private var sourceHealthTimer: Timer?
    private var lastMicBufferAt: Date?
    private var lastSystemBufferAt: Date?
    private var monitorSystemSource = false
    private var didReportSourceDropout = false
    private let sourceDropoutTimeout: TimeInterval = 4.0
    
    // MARK: - Public Methods
    
    /// Start recording from microphone and system audio
    func startRecording() async throws {
        guard !isRecording else {
            throw AudioCaptureError.alreadyRecording
        }
        
        // Step 1: Create recording folder
        let folderURL = try createRecordingFolder()
        recordingFolderURL = folderURL
        
        // Step 2: Create microphone capture and start to get format
        let mic = MicrophoneCapture()
        micCapture = mic
        try mic.start()
        
        guard let micFormat = mic.recordingFormat else {
            mic.stop()
            throw AudioCaptureError.invalidAudioFormat
        }
        
        // Step 3: Try to create system audio capture (graceful degradation if fails)
        let system = SystemAudioCapture()
        systemCapture = system
        
        var systemFormat: AVAudioFormat?
        do {
            try await system.start()
            systemFormat = system.recordingFormat
        } catch {
            print("⚠️ System audio capture failed: \(error.localizedDescription)")
            print("📝 Recording microphone only. Grant Screen Recording permission in System Settings for system audio.")
            // Continue with mic only
            systemCapture = nil
        }
        
        // Step 4: Create file writers
        let micFileURL = folderURL.appendingPathComponent("mic.caf")
        
        let micWriter = try AudioFileWriter(
            url: micFileURL,
            sampleRate: micFormat.sampleRate,
            channels: micFormat.channelCount
        )
        micWriter.onWriteError = { [weak self] error in
            Task { @MainActor in
                self?.onSourceDropoutDetected?("write-error: \(error.localizedDescription)")
            }
        }
        self.micWriter = micWriter
        try micWriter.start()

        // Only create system writer if system audio is available
        if let systemFormat = systemFormat {
            let systemFileURL = folderURL.appendingPathComponent("system.caf")
            let systemWriter = try AudioFileWriter(
                url: systemFileURL,
                sampleRate: systemFormat.sampleRate,
                channels: systemFormat.channelCount
            )
            systemWriter.onWriteError = { [weak self] error in
                Task { @MainActor in
                    self?.onSourceDropoutDetected?("write-error: \(error.localizedDescription)")
                }
            }
            self.systemWriter = systemWriter
            try systemWriter.start()
        }
        
        // Step 6: Setup audio callbacks
        mic.onAudioBuffer = { [weak self, weak micWriter] buffer, time in
            self?.lastMicBufferAt = Date()
            micWriter?.write(buffer)

            Task { @MainActor in
                self?.inputLevel = mic.inputLevel
            }
        }

        mic.onConfigurationChanged = { [weak self] in
            self?.lastMicBufferAt = Date()
        }

        mic.onEngineFailed = { [weak self] in
            self?.onSourceDropoutDetected?("microphone")
        }
        
        // Setup system audio callback only if available
        if let system = systemCapture {
            system.onAudioBuffer = { [weak self, weak systemWriter] buffer, time in
                self?.lastSystemBufferAt = Date()
                systemWriter?.write(buffer)
            }
        }

        configureSourceHealthMonitoring(systemAvailable: systemCapture != nil)
        
        // Step 7: Start duration timer
        startDurationTimer()
        
        isRecording = true
    }
    
    /// Stop recording, mix audio files, and return mixed file URL
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        // Stop duration timer
        durationTimer?.invalidate()
        durationTimer = nil
        sourceHealthTimer?.invalidate()
        sourceHealthTimer = nil
        
        // Stop captures
        micCapture?.stop()
        micCapture = nil
        
        systemCapture?.stop()
        systemCapture = nil
        
        // Finalize files
        micWriter?.finalize()
        micWriter = nil
        
        systemWriter?.finalize()
        systemWriter = nil
        
        isRecording = false
        inputLevel = 0.0
        
        guard let folderURL = recordingFolderURL else {
            return nil
        }

        didReportSourceDropout = false
        
        let micURL = folderURL.appendingPathComponent("mic.caf")
        let systemURL = folderURL.appendingPathComponent("system.caf")
        
        // Check if we have both mic and system audio files
        if FileManager.default.fileExists(atPath: systemURL.path) {
            // Mix audio files
            let mixedURL = folderURL.appendingPathComponent("mixed.caf")
            
            do {
                try await AudioMixer.mix(
                    micURL: micURL,
                    systemURL: systemURL,
                    outputURL: mixedURL,
                    micGain: 0.5,
                    systemGain: 0.5
                )
                
                recordingFolderURL = nil
                return mixedURL
            } catch {
                errorMessage = "Failed to mix audio: \(error.localizedDescription)"
                return nil
            }
        } else {
            // Only microphone recorded - return mic.caf
            print("📝 Using microphone recording only (no system audio)")
            recordingFolderURL = nil
            return micURL
        }
    }
    
    // MARK: - Private Methods
    
    /// Create recording folder with timestamp
    private func createRecordingFolder() throws -> URL {
        let recordingsRootURL = try AppSettings.ensureRecordingsRootExists()
        
        // Generate folder name with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folderName = "recording_\(timestamp)"
        let folderURL = recordingsRootURL.appendingPathComponent(folderName)
        
        // Create recording folder
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        return folderURL
    }
    
    /// Start timer for tracking duration
    private func startDurationTimer() {
        let recordingStart = Date()
        startTime = recordingStart
        duration = 0
        
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.duration = Date().timeIntervalSince(recordingStart)
            }
        }
    }

    private func configureSourceHealthMonitoring(systemAvailable: Bool) {
        didReportSourceDropout = false
        monitorSystemSource = systemAvailable

        let now = Date()
        lastMicBufferAt = now
        lastSystemBufferAt = systemAvailable ? now : nil

        sourceHealthTimer?.invalidate()
        sourceHealthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkSourceHealth()
            }
        }
    }

    private func checkSourceHealth() {
        guard isRecording, !didReportSourceDropout else { return }

        let now = Date()

        if let lastMicBufferAt,
           now.timeIntervalSince(lastMicBufferAt) > sourceDropoutTimeout {
            reportSourceDropout(reason: "microphone")
            return
        }

        if monitorSystemSource,
           let lastSystemBufferAt,
           now.timeIntervalSince(lastSystemBufferAt) > sourceDropoutTimeout {
            reportSourceDropout(reason: "system-audio")
        }
    }

    private func reportSourceDropout(reason: String) {
        guard !didReportSourceDropout else { return }
        didReportSourceDropout = true
        sourceHealthTimer?.invalidate()
        sourceHealthTimer = nil
        print("⚠️ Audio source dropout detected: \(reason)")
        onSourceDropoutDetected?(reason)
    }
}
