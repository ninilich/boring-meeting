import Foundation
import AVFoundation
import Combine

/// Captures audio from microphone using AVAudioEngine
@MainActor
class MicrophoneCapture: ObservableObject {

    // MARK: - Published Properties

    @Published var isCapturing = false
    @Published var inputLevel: Float = 0.0

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var engineConfigObserver: NSObjectProtocol?
    private var lastRestartAt: Date?
    private let restartCooldown: TimeInterval = 1.0

    /// Callback for captured audio buffers
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    /// Recording format - use microphone's native format, no conversion
    private(set) var recordingFormat: AVAudioFormat?

    /// Called when engine restarts successfully after a configuration change
    var onConfigurationChanged: (() -> Void)?

    /// Called when engine cannot be restarted after a configuration change
    var onEngineFailed: (() -> Void)?

    // MARK: - Initialization

    init() {}

    deinit {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
    }

    // MARK: - Public Methods

    /// Start capturing audio from microphone
    func start() throws {
        guard !isCapturing else {
            throw AudioCaptureError.alreadyRecording
        }

        print("🎤 Starting microphone capture...")

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        inputNode = input

        let micFormat = input.inputFormat(forBus: 0)
        recordingFormat = micFormat

        guard micFormat.channelCount > 0 else {
            throw AudioCaptureError.noMicrophoneFound
        }

        print("🎤 Format: \(micFormat.sampleRate)Hz, \(micFormat.channelCount)ch")

        installTap(on: input, format: micFormat)

        do {
            try engine.start()
            isCapturing = true
            print("✅ Microphone capture started")
        } catch {
            input.removeTap(onBus: 0)
            audioEngine = nil
            recordingFormat = nil
            throw AudioCaptureError.audioEngineStartFailed(error.localizedDescription)
        }

        observeEngineConfigurationChanges(engine: engine)
    }

    /// Stop capturing audio
    func stop() {
        guard isCapturing else { return }

        stopObservingEngineConfigurationChanges()
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        audioEngine = nil
        inputNode = nil
        recordingFormat = nil
        isCapturing = false
        inputLevel = 0.0

        print("✅ Microphone stopped")
    }

    // MARK: - Private Methods

    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            guard let self else { return }
            Task { @MainActor in
                self.calculateInputLevel(buffer: buffer)
            }
            self.onAudioBuffer?(buffer, time)
        }
    }

    private func observeEngineConfigurationChanges(engine: AVAudioEngine) {
        stopObservingEngineConfigurationChanges()
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEngineConfigurationChange()
            }
        }
    }

    private func stopObservingEngineConfigurationChanges() {
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
    }

    private func handleEngineConfigurationChange() {
        guard isCapturing else { return }

        if let lastRestartAt, Date().timeIntervalSince(lastRestartAt) < restartCooldown {
            print("⚠️ Engine config change ignored — within cooldown")
            return
        }

        print("⚠️ AVAudioEngine configuration changed — attempting restart")
        restartEngine()
    }

    private func restartEngine() {
        guard let oldFormat = recordingFormat else {
            onEngineFailed?()
            return
        }

        // Tear down old engine (already stopped by the notification)
        stopObservingEngineConfigurationChanges()
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        // Build new engine
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let newFormat = input.inputFormat(forBus: 0)

        // Format mismatch means the file we're writing to would get corrupt data
        guard newFormat.sampleRate == oldFormat.sampleRate,
              newFormat.channelCount == oldFormat.channelCount else {
            print("❌ Engine restart aborted — format changed (\(oldFormat) → \(newFormat))")
            isCapturing = false
            onEngineFailed?()
            return
        }

        guard newFormat.channelCount > 0 else {
            print("❌ Engine restart aborted — no input channels")
            isCapturing = false
            onEngineFailed?()
            return
        }

        installTap(on: input, format: newFormat)

        do {
            try engine.start()
            audioEngine = engine
            inputNode = input
            recordingFormat = newFormat
            lastRestartAt = Date()
            observeEngineConfigurationChanges(engine: engine)
            print("✅ Microphone engine restarted after configuration change")
            onConfigurationChanged?()
        } catch {
            input.removeTap(onBus: 0)
            print("❌ Microphone engine restart failed: \(error.localizedDescription)")
            isCapturing = false
            onEngineFailed?()
        }
    }

    private func calculateInputLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                sum += abs(samples[frame])
            }
        }

        let average = sum / Float(frameLength * channelCount)

        let smoothing: Float = 0.7
        inputLevel = (inputLevel * smoothing) + (average * (1.0 - smoothing))
    }
}
