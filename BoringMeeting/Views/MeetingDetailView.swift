import SwiftUI
@preconcurrency import AVFoundation
import Combine
import SwiftData

/// Detail view for a single meeting with audio playback
struct MeetingDetailView: View {
    let meeting: Meeting
    let isRecording: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appDelegate: AppDelegate
    @EnvironmentObject private var modelManager: AIModelManager
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    @ObservedObject private var settings = AppSettings.shared
    
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var selectedTranscriptionModelID = AppSettings.shared.defaultTranscriptionModelID
    @State private var selectedSource: TranscriptionSource = .both
    @State private var selectedTranscriptionLanguageRaw = Self.defaultLanguageSelectionRaw
    @State private var transcriptionActionError: String?
    @State private var showDeleteTranscriptAlert = false
    @State private var transcriptCopied = false
    @State private var showTrimSheet = false

    private static let defaultLanguageSelectionRaw = "__default__"
    
    private func saveContext() {
        do { try modelContext.save() }
        catch { print("⚠️ save failed: \(error.localizedDescription)") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Recording banner
            if isRecording {
                recordingBanner
            }

            // Fixed top: audio player, transcript settings
            VStack(spacing: 16) {
                audioPlayerSection

                Divider()

                transcriptHeaderSection
            }
            .padding()

            // Flexible bottom: fills remaining height
            transcriptBodySection
        }
        .onAppear {
            modelManager.refreshInstalledTranscriptionModelsFromDisk()

            if let url = meeting.fullAudioPath {
                audioPlayer.loadAudio(url: url)
            } else {
                audioPlayer.setLoadError("Audio file path is missing")
            }
            selectedTranscriptionModelID = settings.defaultTranscriptionModelID
            selectedTranscriptionLanguageRaw = meeting.transcriptionLanguageOverrideRaw ?? Self.defaultLanguageSelectionRaw
            selectedSource = .both
            applySavedTranscriptionSettingsIfAvailable()
        }
        .onChange(of: meeting.audioFilePath) {
            if let url = meeting.fullAudioPath {
                audioPlayer.loadAudio(url: url)
            } else {
                audioPlayer.setLoadError("Audio file path is missing")
            }
        }
        .onChange(of: meeting.persistentModelID) { _, _ in
            selectedTranscriptionModelID = settings.defaultTranscriptionModelID
            selectedTranscriptionLanguageRaw = meeting.transcriptionLanguageOverrideRaw ?? Self.defaultLanguageSelectionRaw
            selectedSource = .both
            applySavedTranscriptionSettingsIfAvailable()
        }
        .onChange(of: selectedSource) { _, newSource in
            switch newSource {
            case .both:
                if let url = meeting.fullAudioPath { audioPlayer.loadAudio(url: url) }
            case .micOnly:
                if let paths = dualAudioFiles { audioPlayer.loadAudio(url: paths.mic) }
            case .systemOnly:
                if let paths = dualAudioFiles { audioPlayer.loadAudio(url: paths.system) }
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .sheet(isPresented: $showTrimSheet) {
            if let url = meeting.fullAudioPath {
                TrimAudioSheet(
                    audioURL: url,
                    totalDuration: meeting.duration
                ) { newDuration, newFileSize in
                    meeting.duration = newDuration
                    meeting.fileSize = newFileSize
                    saveContext()
                    if let url = meeting.fullAudioPath {
                        audioPlayer.loadAudio(url: url)
                    }
                }
            }
        }
        .alert("Delete Transcript?", isPresented: $showDeleteTranscriptAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTranscription()
            }
        } message: {
            Text("Transcript text will be removed. Audio recording will stay unchanged.")
        }
    }
    
    // MARK: - Recording Banner
    
    private var recordingBanner: some View {
        HStack {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
            Text("Recording in progress...")
                .fontWeight(.medium)
            Spacer()
            Text(appDelegate.recordingDuration.formattedTime())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.18), Color.red.opacity(0.04)],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }
    
    // MARK: - Transcript Header (fixed top portion)

    private var transcriptHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelSelectionSection

            if let transcriptionActionError {
                Label(transcriptionActionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if !isTranscriptionSelectionLocked && !modelManager.isInstalled(selectedTranscriptionModelID) {
                modelDownloadSection
            }
        }
    }

    // MARK: - Transcript Body (fills remaining height)

    private var transcriptBodySection: some View {
        Group {
            switch meeting.status {
            case .notStarted:
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("No transcript yet")
                        .foregroundStyle(.secondary)

                    Button {
                        startTranscription()
                    } label: {
                        Label("Start Transcription", systemImage: "waveform")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.opacity(0.8))
                    .disabled(!canStartTranscription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .inProgress:
                VStack(spacing: 16) {
                    ProgressView(value: transcriptionProgress) {
                        Text(transcriptionProgressLabel)
                    }
                    .frame(maxWidth: 300)

                    Text("\(Int(transcriptionProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let modelID = meeting.transcriptionModelUsedID,
                       let catalogFactor = modelManager.descriptor(for: modelID)?.catalogSpeedFactor,
                       let resolved = AppSettings.shared.resolvedSpeedFactor(for: modelID, catalogFactor: catalogFactor),
                       meeting.duration > 0 {
                        Text("Estimated total: ~\(formatTranscriptionDuration(meeting.duration / resolved.factor))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        transcriptionManager.cancelTranscription(for: meeting)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed:
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Transcription failed:")
                            .foregroundStyle(.secondary)
                        if let error = meeting.transcriptionError {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }

                    Button {
                        retryTranscription()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStartTranscription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .completed:
                if meeting.transcript.isEmpty {
                    VStack(spacing: 12) {
                        Text("Transcript is empty")
                            .foregroundStyle(.secondary)
                        Button("Remove Transcript", role: .destructive) {
                            showDeleteTranscriptAlert = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(transcriptionManager.isRunning(for: meeting.id))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: .constant(meeting.transcript))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(meeting.transcript, forType: .string)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    transcriptCopied = true
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        transcriptCopied = false
                                    }
                                }
                            } label: {
                                Label(
                                    transcriptCopied ? "Copied!" : "Copy Transcript",
                                    systemImage: transcriptCopied ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(transcriptCopied ? .green : Color.blue.opacity(0.8))

                            Spacer()

                            Button("Remove Transcript", role: .destructive) {
                                showDeleteTranscriptAlert = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(transcriptionManager.isRunning(for: meeting.id))
                        }
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .id(meeting.status)
        .transition(.opacity.combined(with: .scale(0.97)))
        .animation(.easeInOut(duration: 0.2), value: meeting.status)
    }

    // MARK: - Audio Player Section
    
    private var audioPlayerSection: some View {
        VStack(spacing: 6) {
            // Metadata row
            HStack {
                Text("\(AppSettings.shared.formatDate(meeting.date)) • \(meeting.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if meeting.status == .notStarted && audioPlayer.isLoaded {
                    Button {
                        audioPlayer.stop()
                        showTrimSheet = true
                    } label: {
                        Label("Trim", systemImage: "scissors")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let loadError = audioPlayer.loadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Controls + slider + time in one row
            HStack(spacing: 10) {
                Button {
                    audioPlayer.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.isLoaded)
                .help("Back 15 seconds")

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.isLoaded)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                Button {
                    audioPlayer.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.isLoaded)
                .help("Forward 15 seconds")

                Slider(value: Binding(
                    get: { audioPlayer.progress },
                    set: { audioPlayer.seek(to: $0) }
                ), in: 0...1)
                .disabled(!audioPlayer.isLoaded)

                Text("\(audioPlayer.currentTime.formattedTime()) / \(audioPlayer.duration.formattedTime())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Actions

    private var dualAudioFiles: (mic: URL, system: URL)? {
        transcriptionManager.dualAudioPaths(for: meeting)
    }

    @ViewBuilder
    private func audioSourceButton(_ label: String, source: TranscriptionSource) -> some View {
        Button { selectedSource = source } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedSource == source ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedSource == source ? Color.accentColor : .secondary)
                Text(label).font(.callout)
            }
        }
        .buttonStyle(.plain)
    }

    private var canStartTranscription: Bool {
        modelManager.isInstalled(selectedTranscriptionModelID) && !transcriptionManager.isRunning(for: meeting.id)
    }

    private var isTranscriptionSelectionLocked: Bool {
        meeting.status == .completed && !meeting.transcript.isEmpty
    }

    private var visibleLanguages: [AppSettings.TranscriptionLanguage] {
        AppSettings.allNonAutoLanguages.filter { settings.visibleLanguageIDs.contains($0.rawValue) }
    }

    private var currentLanguageIfHidden: AppSettings.TranscriptionLanguage? {
        guard selectedTranscriptionLanguageRaw != Self.defaultLanguageSelectionRaw,
              let lang = AppSettings.TranscriptionLanguage(rawValue: selectedTranscriptionLanguageRaw),
              !settings.visibleLanguageIDs.contains(lang.rawValue) else { return nil }
        return lang
    }

    private var lockedTranscriptLabel: String {
        var label = "Model and language are locked for completed transcripts"
        if let duration = meeting.transcriptionDuration {
            label += " • transcribed in \(formatTranscriptionDuration(duration))"
        }
        return label
    }

    private func formatTranscriptionDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
        return "\(s)s"
    }

    private var transcriptionProgress: Double {
        transcriptionManager.progress(for: meeting.id)
    }

    private var transcriptionProgressLabel: String {
        if transcriptionProgress >= 1.0 {
            return "Finalizing..."
        } else if transcriptionProgress > 0 {
            return "Transcribing..."
        } else {
            return "Initializing model, this may take a moment..."
        }
    }

    private var selectedTranscriptionModel: AIModelDescriptor? {
        modelManager.descriptor(for: selectedTranscriptionModelID)
    }

    private var modelLockedLanguage: AppSettings.TranscriptionLanguage? {
        modelManager.lockedLanguage(for: selectedTranscriptionModelID)
    }

    private func modelPickerTitle(for model: AIModelDescriptor) -> String {
        let speedText: String
        if let resolved = AppSettings.shared.resolvedSpeedFactor(for: model.id, catalogFactor: model.catalogSpeedFactor) {
            let label = "~\(Int(resolved.factor.rounded()))x"
            speedText = resolved.isMeasured ? label : "\(label)*"
        } else {
            speedText = "\(model.speedLabel)*"
        }
        let langSuffix = model.lockedLanguage.map { ", \($0.uppercased()) only" } ?? ""
        return "\(model.displayName) (\(model.qualityLabel), \(speedText)\(langSuffix))"
    }

    private func applySavedTranscriptionSettingsIfAvailable() {
        guard isTranscriptionSelectionLocked else { return }

        if let usedModelID = meeting.transcriptionModelUsedID,
           modelManager.descriptor(for: usedModelID) != nil {
            selectedTranscriptionModelID = usedModelID
        }

        if let usedLanguageRaw = meeting.transcriptionLanguageUsedRaw,
           AppSettings.TranscriptionLanguage(rawValue: usedLanguageRaw) != nil {
            selectedTranscriptionLanguageRaw = usedLanguageRaw
        } else if let override = meeting.transcriptionLanguageOverrideRaw,
                  AppSettings.TranscriptionLanguage(rawValue: override) != nil {
            // Legacy fallback when used language was not persisted in older records.
            selectedTranscriptionLanguageRaw = override
        } else {
            selectedTranscriptionLanguageRaw = Self.defaultLanguageSelectionRaw
        }
    }

    @ViewBuilder
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Settings")
                .font(.subheadline)
                .fontWeight(.semibold)

            if isTranscriptionSelectionLocked {
                Label(lockedTranscriptLabel, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if isTranscriptionSelectionLocked,
                       selectedTranscriptionModel == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Unknown (legacy)")
                                .font(.callout)
                        }
                    } else if modelManager.installedTranscriptionModelIDs.isEmpty {
                        HStack(spacing: 4) {
                            Text("No models installed.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                appDelegate.openSettingsWindow(tab: .transcription)
                            }
                            .font(.callout)
                        }
                    } else {
                        Picker("Model", selection: $selectedTranscriptionModelID) {
                            ForEach(modelManager.transcriptionModels.filter { modelManager.isInstalled($0.id) }) { model in
                                Text(modelPickerTitle(for: model)).tag(model.id)
                            }
                            if modelManager.installedTranscriptionModelIDs.count < modelManager.transcriptionModels.count {
                                Section("Not installed") {
                                    ForEach(modelManager.transcriptionModels.filter { !modelManager.isInstalled($0.id) }) { model in
                                        Text(modelPickerTitle(for: model)).tag(model.id)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isTranscriptionSelectionLocked)
                        .onChange(of: selectedTranscriptionModelID) { _, newID in
                            // Skip programmatic changes from applySavedTranscriptionSettingsIfAvailable
                            guard !isTranscriptionSelectionLocked else { return }
                            settings.defaultTranscriptionModelID = newID
                            transcriptionActionError = nil
                            // Clear per-meeting language override when switching to a locked-language model
                            if let locked = modelManager.lockedLanguage(for: newID) {
                                selectedTranscriptionLanguageRaw = locked.rawValue
                                meeting.transcriptionLanguageOverrideRaw = nil
                                saveContext()
                                // Override is not restored when switching back to a multilingual model — intentional.
                            }
                        }
                    }
                }
                .frame(minWidth: 320, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Picker("Language", selection: $selectedTranscriptionLanguageRaw) {
                            Text("Default (\(settings.transcriptionLanguage.displayName))")
                                .tag(Self.defaultLanguageSelectionRaw)

                            ForEach(visibleLanguages) { language in
                                Text(language.displayName).tag(language.rawValue)
                            }

                            // Always show the currently selected language even if hidden
                            if let current = currentLanguageIfHidden {
                                Text(current.displayName).tag(current.rawValue)
                            }

                            // Ensure locked language appears in the list even if not in visibleLanguages
                            if let locked = modelLockedLanguage,
                               !visibleLanguages.contains(where: { $0.rawValue == locked.rawValue }) {
                                Text(locked.displayName).tag(locked.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isTranscriptionSelectionLocked || modelLockedLanguage != nil)
                        .onChange(of: selectedTranscriptionLanguageRaw) { _, newRaw in
                            guard modelLockedLanguage == nil else { return }
                            if newRaw == Self.defaultLanguageSelectionRaw {
                                meeting.transcriptionLanguageOverrideRaw = nil
                            } else {
                                meeting.transcriptionLanguageOverrideRaw = newRaw
                            }
                            saveContext()
                            transcriptionActionError = nil
                        }

                        if modelLockedLanguage != nil {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        appDelegate.openSettingsWindow(tab: .transcription)
                    } label: {
                        Text("Add more languages in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isTranscriptionSelectionLocked || modelLockedLanguage != nil ? 0 : 1)
                    .allowsHitTesting(!isTranscriptionSelectionLocked && modelLockedLanguage == nil)
                }
                .frame(minWidth: 240, alignment: .leading)
            }

            if !isTranscriptionSelectionLocked, dualAudioFiles != nil {
                HStack(spacing: 16) {
                    Text("Audio source:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    audioSourceButton("Both", source: .both)
                    audioSourceButton("Mic only", source: .micOnly)
                    audioSourceButton("System audio only", source: .systemOnly)
                }
            }
        }
    }

    @ViewBuilder
    private var modelDownloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modelManager.isDownloading(selectedTranscriptionModelID)
            || modelManager.progress(for: selectedTranscriptionModelID) > 0 {
                Label("Downloading model...", systemImage: "arrow.down.circle")
                    .font(.callout)

                ProgressView(value: modelManager.progress(for: selectedTranscriptionModelID))
                    .frame(maxWidth: 300)

                Text("\(Int(modelManager.progress(for: selectedTranscriptionModelID) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("Model not downloaded", systemImage: "arrow.down.circle")
                        .font(.callout)

                    Spacer()

                    Button {
                        appDelegate.openSettingsWindow(tab: .transcription)
                    } label: {
                        Label("Download in Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
    
    private func startTranscription() {
        transcriptionActionError = nil
        do {
            switch selectedSource {
            case .both:
                if AppSettings.shared.splitAudioSources {
                    try transcriptionManager.startDualSourceTranscription(for: meeting, modelID: selectedTranscriptionModelID)
                } else {
                    try transcriptionManager.startTranscription(for: meeting, modelID: selectedTranscriptionModelID)
                }
            case .micOnly:
                try transcriptionManager.startTranscription(
                    for: meeting, modelID: selectedTranscriptionModelID,
                    audioURL: dualAudioFiles?.mic
                )
            case .systemOnly:
                try transcriptionManager.startTranscription(
                    for: meeting, modelID: selectedTranscriptionModelID,
                    audioURL: dualAudioFiles?.system
                )
            }
        } catch {
            transcriptionActionError = error.localizedDescription
        }
    }

    private func retryTranscription() {
        transcriptionActionError = nil
        do {
            switch selectedSource {
            case .both:
                if AppSettings.shared.splitAudioSources {
                    try transcriptionManager.startDualSourceTranscription(for: meeting, modelID: selectedTranscriptionModelID)
                } else {
                    try transcriptionManager.retryTranscription(for: meeting, modelID: selectedTranscriptionModelID)
                }
            case .micOnly:
                try transcriptionManager.retryTranscription(
                    for: meeting, modelID: selectedTranscriptionModelID,
                    audioURL: dualAudioFiles?.mic
                )
            case .systemOnly:
                try transcriptionManager.retryTranscription(
                    for: meeting, modelID: selectedTranscriptionModelID,
                    audioURL: dualAudioFiles?.system
                )
            }
        } catch {
            transcriptionActionError = error.localizedDescription
        }
    }

    private func deleteTranscription() {
        transcriptionActionError = nil
        transcriptionManager.deleteTranscription(for: meeting)
    }
    
    // MARK: - Helpers
    
}

// MARK: - Audio Player Manager

@MainActor
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Double = 0
    @Published var loadError: String?
    @Published var volume: Double = 0.7 {
        didSet {
            player?.volume = Float(volume)
        }
    }

    var isLoaded: Bool {
        player != nil
    }
    
    private var player: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
    }
    
    func loadAudio(url: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            setLoadError("Audio file not found")
            return
        }

          if let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
              bytes == 0 {
            setLoadError("Audio file is empty")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.volume = Float(volume)
            duration = player?.duration ?? 0
            currentTime = 0
            progress = 0
            loadError = nil
        } catch {
            setLoadError("Failed to load audio: \(error.localizedDescription)")
        }
    }

    func setLoadError(_ message: String) {
        player = nil
        duration = 0
        currentTime = 0
        progress = 0
        isPlaying = false
        stopTimer()
        loadError = message
        print("❌ \(message)")
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            if player.currentTime >= max(duration - 0.05, 0) {
                player.currentTime = 0
                currentTime = 0
                progress = 0
            }

            let didStartPlaying = player.play()
            isPlaying = didStartPlaying

            if didStartPlaying {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }
    
    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        progress = 0
        stopTimer()
    }
    
    func seek(to progress: Double) {
        guard let player = player else { return }
        guard duration > 0 else { return }

        let clampedProgress = max(0, min(1, progress))
        let time = duration * clampedProgress
        player.currentTime = time
        currentTime = time
        self.progress = clampedProgress
    }
    
    func skip(by seconds: TimeInterval) {
        guard let player = player else { return }
        let newTime = max(0, min(duration, player.currentTime + seconds))
        player.currentTime = newTime
        currentTime = newTime
        progress = duration > 0 ? newTime / duration : 0
    }
    
    private func startTimer() {
        stopTimer()

        guard let activePlayer = player else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.currentTime = activePlayer.currentTime
                self.progress = self.duration > 0 ? activePlayer.currentTime / self.duration : 0
                
                if !activePlayer.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.progress = self.duration > 0 ? 1 : 0
            self.stopTimer()
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Meeting.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let modelManager = AIModelManager()
    let transcriptionManager = TranscriptionManager(modelContainer: container, modelManager: modelManager)

    let meeting: Meeting = {
        let value = Meeting(
            date: Date(),
            duration: 1845,
            audioFilePath: "test.m4a",
            title: "Recording 11.02.2026 11:30"
        )
        value.fileSize = 5_242_880
        value.status = .completed
        value.transcript = "[Speaker 1, 00:15] Welcome everyone to today's meeting\n[Speaker 2, 00:23] Thanks for having me. Let's start with the quarterly results\n[Speaker 1, 00:45] As you can see in the presentation, we've made significant progress"
        return value
    }()
    
    MeetingDetailView(meeting: meeting, isRecording: false)
        .environmentObject(AppDelegate())
        .environmentObject(modelManager)
        .environmentObject(transcriptionManager)
        .frame(width: 700, height: 600)
}
