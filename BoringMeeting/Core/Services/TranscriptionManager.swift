import Foundation
import SwiftData
import Combine
import WhisperKit

extension Notification.Name {
    static let requestAppReview = Notification.Name("requestAppReview")
}

enum TranscriptionSource {
    case both
    case micOnly
    case systemOnly
}

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published private(set) var progressByMeetingID: [UUID: Double] = [:]
    @Published private(set) var batchQueue: [UUID] = []
    @Published private(set) var batchTotal: Int = 0
    @Published private(set) var batchCompleted: Int = 0

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var batchTask: Task<Void, Never>?
    private var sleepAssertions: [UUID: NSObjectProtocol] = [:]
    private var cachedWhisperModelID: String?
    private var cachedWhisper: WhisperKit?
    private let modelContainer: ModelContainer
    private let modelManager: AIModelManager

    enum StartError: LocalizedError {
        case modelNotInstalled
        case noAudioFile
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .modelNotInstalled:
                return "Selected model is not downloaded yet"
            case .noAudioFile:
                return "Audio file is not available"
            case .alreadyRunning:
                return "Transcription already running for this recording"
            }
        }
    }

    init(modelContainer: ModelContainer, modelManager: AIModelManager) {
        self.modelContainer = modelContainer
        self.modelManager = modelManager
    }

    func progress(for meetingID: UUID) -> Double {
        progressByMeetingID[meetingID] ?? 0
    }

    func isRunning(for meetingID: UUID) -> Bool {
        tasks[meetingID] != nil
    }

    func startTranscription(for meeting: Meeting, modelID: String, audioURL: URL? = nil) throws {
        modelManager.refreshInstalledTranscriptionModelsFromDisk()

        let resolvedURL = audioURL ?? meeting.fullAudioPath
        guard resolvedURL != nil else {
            throw StartError.noAudioFile
        }

        guard !isRunning(for: meeting.id) else {
            throw StartError.alreadyRunning
        }

        guard modelManager.isInstalled(modelID) else {
            throw StartError.modelNotInstalled
        }

        let modelContext = modelContainer.mainContext
        let selectedLanguage = meetingLanguage(for: meeting, modelID: modelID)

        meeting.status = .inProgress
        meeting.transcriptionError = nil
        meeting.isTranscribed = false
        meeting.transcriptionModelUsedID = modelID
        meeting.transcriptionLanguageUsedRaw = selectedLanguage.rawValue
        progressByMeetingID[meeting.id] = 0

        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to save transcription start: \(error.localizedDescription)")
        }

        let meetingID = meeting.id
        let audioPath = resolvedURL?.path
        let estimatedDurationSeconds = max(meeting.duration, 1)
        let estimatedWindows = max(1, Int(ceil(estimatedDurationSeconds / 30.0)))

        sleepAssertions[meetingID] = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transcribing audio"
        )

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.tasks[meetingID] = nil
                if let activity = self.sleepAssertions.removeValue(forKey: meetingID) {
                    ProcessInfo.processInfo.endActivity(activity)
                }
                if AppSettings.shared.unloadModelAfterTranscription {
                    self.clearCachedWhisper()
                }
            }

            let transcriptionStartDate = Date()

            guard let audioPath else {
                meeting.status = .failed
                meeting.transcriptionError = StartError.noAudioFile.localizedDescription
                self.progressByMeetingID[meetingID] = 0
                self.saveContext("no audio path")
                return
            }

            do {
                let whisperKit = try await self.whisper(for: modelID)
                let decodeOptions = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: selectedLanguage == .auto ? nil : selectedLanguage.rawValue,
                    detectLanguage: false,
                    wordTimestamps: false
                )

                let results = try await whisperKit.transcribe(
                    audioPath: audioPath,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let current = self.progressByMeetingID[meetingID] ?? 0
                            let windowBasedProgress = Double(progress.windowId + 1) / Double(estimatedWindows)
                            self.progressByMeetingID[meetingID] = min(0.99, max(current, windowBasedProgress))
                        }
                        return true
                    }
                )

                let transcriptionDuration = Date().timeIntervalSince(transcriptionStartDate)
                meeting.transcript = self.mergeTranscriptionText(results)
                meeting.status = .completed
                meeting.transcriptionError = nil
                meeting.isTranscribed = true
                meeting.transcriptionDuration = transcriptionDuration
                AppSettings.shared.updateSpeedFactor(
                    modelID: modelID,
                    audioDuration: estimatedDurationSeconds,
                    transcriptionDuration: transcriptionDuration
                )
                self.progressByMeetingID[meetingID] = 1.0

                do {
                    try modelContext.save()
                    self.requestReviewIfNeeded()
                } catch {
                    meeting.status = .failed
                    meeting.transcriptionError = "Failed to save transcript"
                    self.progressByMeetingID[meetingID] = 0
                    self.saveContext("save after failed transcript save")
                }
            } catch is CancellationError {
                meeting.status = .notStarted
                meeting.transcriptionError = nil
                meeting.isTranscribed = false
                self.progressByMeetingID[meetingID] = 0
                self.saveContext("cancellation")
            } catch {
                meeting.status = .failed
                meeting.transcriptionError = "Transcription failed: \(error.localizedDescription)"
                meeting.isTranscribed = false
                self.progressByMeetingID[meetingID] = 0
                self.saveContext("transcription error")
            }
        }

        tasks[meeting.id] = task
    }

    func recoverSleepInterruptedTranscriptions() {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.transcriptionStatus == "in_progress" }
        )
        guard let meetings = try? modelContainer.mainContext.fetch(descriptor),
              !meetings.isEmpty else { return }
        for meeting in meetings {
            meeting.status = .failed
            meeting.transcriptionError = "Transcription was interrupted because the Mac went to sleep. Please try again."
        }
        saveContext("sleep recovery")
    }

    /// Resets any meetings that were left in `.inProgress` from a previous session.
    /// Call this once on app launch to prevent permanently stuck UI state.
    func recoverInterruptedTranscriptions() {
        let modelContext = modelContainer.mainContext
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.transcriptionStatus == "in_progress" }
        )
        guard let meetings = try? modelContext.fetch(descriptor), !meetings.isEmpty else { return }
        for meeting in meetings {
            meeting.status = .failed
            meeting.transcriptionError = "Transcription was interrupted by an app restart. Please try again."
        }
        saveContext("recover interrupted")
    }

    private func requestReviewIfNeeded() {
        let settings = AppSettings.shared
        guard settings.reviewPromptsEnabled else { return }

        settings.transcriptionsCompleted += 1
        let count = settings.transcriptionsCompleted
        let milestones = [10, 25, 50]
        guard milestones.contains(count) else { return }

        NotificationCenter.default.post(name: .requestAppReview, object: nil)
    }

    func cancelTranscription(for meeting: Meeting) {
        tasks[meeting.id]?.cancel()
    }

    func enqueueTranscriptions(for meetings: [Meeting], modelID: String) {
        let eligible = meetings.filter { $0.status == .notStarted || $0.status == .failed }
        guard !eligible.isEmpty else { return }
        cancelBatch()
        batchQueue = eligible.map(\.id)
        batchTotal = eligible.count
        batchCompleted = 0
        batchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait for any in-flight single transcription to finish so we don't load two WhisperKit instances simultaneously.
            while !self.tasks.isEmpty && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            for meeting in eligible {
                guard !Task.isCancelled else { break }
                do {
                    if AppSettings.shared.splitAudioSources && self.dualAudioPaths(for: meeting) != nil {
                        try self.startDualSourceTranscription(for: meeting, modelID: modelID)
                    } else {
                        try self.startTranscription(for: meeting, modelID: modelID)
                    }
                } catch {
                    meeting.status = .failed
                    meeting.transcriptionError = error.localizedDescription
                    self.saveContext("batch start error")
                    self.batchCompleted += 1
                    if !self.batchQueue.isEmpty { self.batchQueue.removeFirst() }
                    continue
                }
                while self.isRunning(for: meeting.id) {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled { break }
                }
                if Task.isCancelled { break }
                self.batchCompleted += 1
                if !self.batchQueue.isEmpty { self.batchQueue.removeFirst() }
            }
            guard !Task.isCancelled else { return }
            self.batchQueue = []
            self.batchTotal = 0
            self.batchCompleted = 0
        }
    }

    func cancelBatch() {
        if let currentID = batchQueue.first {
            tasks[currentID]?.cancel()
        }
        batchTask?.cancel()
        batchTask = nil
        batchQueue = []
        batchTotal = 0
        batchCompleted = 0
    }

    func retryTranscription(for meeting: Meeting, modelID: String, audioURL: URL? = nil) throws {
        progressByMeetingID[meeting.id] = 0
        try startTranscription(for: meeting, modelID: modelID, audioURL: audioURL)
    }

    private func saveContext(_ label: String = "") {
        do { try modelContainer.mainContext.save() }
        catch { print("⚠️ save failed [\(label)]: \(error.localizedDescription)") }
    }

    func deleteTranscription(for meeting: Meeting) {
        guard !isRunning(for: meeting.id) else { return }

        let modelContext = modelContainer.mainContext
        meeting.transcript = ""
        meeting.isTranscribed = false
        meeting.status = .notStarted
        meeting.transcriptionError = nil
        meeting.transcriptionModelUsedID = nil
        meeting.transcriptionLanguageUsedRaw = nil
        meeting.transcriptSegmentsJSON = nil
        progressByMeetingID[meeting.id] = 0

        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to delete transcription: \(error.localizedDescription)")
        }
    }

    private func whisper(for modelID: String) async throws -> WhisperKit {
        if cachedWhisperModelID == modelID,
           let whisper = cachedWhisper {
            return whisper
        }

        guard let folderURL = modelManager.localModelFolderURL(for: modelID) else {
            throw StartError.modelNotInstalled
        }

        let whisper = try await WhisperKit(
            model: modelID,
            downloadBase: modelManager.whisperDownloadBaseURL(),
            modelFolder: folderURL.path,
            tokenizerFolder: modelManager.whisperDownloadBaseURL(),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false
        )

        // Keep at most one model in RAM for predictable memory usage.
        cachedWhisperModelID = modelID
        cachedWhisper = whisper
        return whisper
    }

    private func clearCachedWhisper() {
        cachedWhisperModelID = nil
        cachedWhisper = nil
    }

    private func mergeTranscriptionText(_ results: [TranscriptionResult]) -> String {
        let chunks = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if chunks.isEmpty {
            return ""
        }

        return chunks.joined(separator: "\n\n")
    }

    // MARK: - Dual-source transcription

    private static let hallucinationPhrases: [String] = [
        "thank you", "thanks for watching", "thanks for listening",
        "♪", "subtitles by", "subscribe", "please subscribe"
    ]

    private static let bracketedLabelRegex = try! NSRegularExpression(pattern: #"^\[.*\]$|^\(.*\)$"#)

    private func isHallucination(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compact = normalized.filter { !$0.isWhitespace }
        let range = NSRange(compact.startIndex..., in: compact)
        if TranscriptionManager.bracketedLabelRegex.firstMatch(in: compact, range: range) != nil {
            return true
        }
        return TranscriptionManager.hallucinationPhrases.contains { normalized.contains($0) }
    }

    func dualAudioPaths(for meeting: Meeting) -> (mic: URL, system: URL)? {
        let folder = (meeting.audioFilePath as NSString).deletingLastPathComponent
        guard !folder.isEmpty else { return nil }
        let folderURL = AppSettings.recordingsRootURL.appendingPathComponent(folder)
        let micURL = folderURL.appendingPathComponent("mic.caf")
        let systemURL = folderURL.appendingPathComponent("system.caf")
        guard FileManager.default.fileExists(atPath: micURL.path),
              FileManager.default.fileExists(atPath: systemURL.path) else { return nil }
        return (mic: micURL, system: systemURL)
    }

    private func stripWhisperTokens(_ text: String) -> String {
        var result = ""
        var s = text[...]
        while let open = s.range(of: "<|") {
            result += s[..<open.lowerBound]
            s = s[open.lowerBound...]
            if let close = s.range(of: "|>") {
                s = s[close.upperBound...]
            } else {
                break
            }
        }
        result += s
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeSegments(from results: [TranscriptionResult], source: AudioSource) -> [TranscriptSegment] {
        results.flatMap { result in
            result.segments.compactMap { seg -> TranscriptSegment? in
                let text = stripWhisperTokens(seg.text)
                guard !text.isEmpty, !isHallucination(text) else { return nil }
                return TranscriptSegment(
                    text: text,
                    startTime: Double(seg.start),
                    endTime: Double(seg.end),
                    source: source,
                    avgLogprob: Double(seg.avgLogprob),
                    noSpeechProb: Double(seg.noSpeechProb),
                    compressionRatio: Double(seg.compressionRatio)
                )
            }
        }
    }

    private func groupSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var i = 0
        while i < segments.count {
            var groupText = segments[i].text
            var groupEnd = segments[i].endTime
            let groupSource = segments[i].source
            let groupStart = segments[i].startTime
            let groupMeta = segments[i]
            var j = i + 1
            while j < segments.count,
                  segments[j].source == groupSource,
                  segments[j].startTime - groupEnd < 1.5 {
                groupText += " " + segments[j].text
                groupEnd = segments[j].endTime
                j += 1
            }
            result.append(TranscriptSegment(
                text: groupText,
                startTime: groupStart,
                endTime: groupEnd,
                source: groupSource,
                avgLogprob: groupMeta.avgLogprob,
                noSpeechProb: groupMeta.noSpeechProb,
                compressionRatio: groupMeta.compressionRatio
            ))
            i = j
        }
        return result
    }

    private func formattedTranscript(from segments: [TranscriptSegment], settings: AppSettings) -> String {
        var lines: [String] = []
        var lastSource: AudioSource? = nil
        for seg in segments {
            if seg.source != lastSource {
                let minutes = Int(seg.startTime) / 60
                let seconds = Int(seg.startTime) % 60
                let name = seg.source == .microphone ? settings.micSourceName : settings.systemSourceName
                lines.append("[\(String(format: "%02d:%02d", minutes, seconds))] [\(name)]")
                lastSource = seg.source
            }
            lines.append(seg.text)
        }
        return lines.joined(separator: "\n")
    }

    func startDualSourceTranscription(for meeting: Meeting, modelID: String) throws {
        modelManager.refreshInstalledTranscriptionModelsFromDisk()

        guard !isRunning(for: meeting.id) else {
            throw StartError.alreadyRunning
        }

        guard modelManager.isInstalled(modelID) else {
            throw StartError.modelNotInstalled
        }

        guard let paths = dualAudioPaths(for: meeting) else {
            throw StartError.noAudioFile
        }

        let modelContext = modelContainer.mainContext
        let selectedLanguage = meetingLanguage(for: meeting, modelID: modelID)

        meeting.status = .inProgress
        meeting.transcriptionError = nil
        meeting.isTranscribed = false
        meeting.transcriptionModelUsedID = modelID
        meeting.transcriptionLanguageUsedRaw = selectedLanguage.rawValue
        progressByMeetingID[meeting.id] = 0

        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to save dual transcription start: \(error.localizedDescription)")
        }

        let meetingID = meeting.id
        let micPath = paths.mic.path
        let systemPath = paths.system.path
        let estimatedDurationSeconds = max(meeting.duration, 1)
        let estimatedWindows = max(1, Int(ceil(estimatedDurationSeconds / 30.0)))

        sleepAssertions[meetingID] = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transcribing audio"
        )

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.tasks[meetingID] = nil
                if let activity = self.sleepAssertions.removeValue(forKey: meetingID) {
                    ProcessInfo.processInfo.endActivity(activity)
                }
                if AppSettings.shared.unloadModelAfterTranscription {
                    self.clearCachedWhisper()
                }
            }

            let transcriptionStartDate = Date()
            let appSettings = AppSettings.shared

            do {
                let whisperKit = try await self.whisper(for: modelID)
                let decodeOptions = DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: selectedLanguage == .auto ? nil : selectedLanguage.rawValue,
                    detectLanguage: false,
                    wordTimestamps: false
                )

                // Pass 1: microphone (progress 0.0 → 0.5)
                let micResults = try await whisperKit.transcribe(
                    audioPath: micPath,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let current = self.progressByMeetingID[meetingID] ?? 0
                            let p = Double(progress.windowId + 1) / Double(estimatedWindows) * 0.5
                            self.progressByMeetingID[meetingID] = min(0.49, max(current, p))
                        }
                        return true
                    }
                )

                // Pass 2: system audio (progress 0.5 → 1.0)
                let systemResults = try await whisperKit.transcribe(
                    audioPath: systemPath,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let current = self.progressByMeetingID[meetingID] ?? 0
                            let p = 0.5 + Double(progress.windowId + 1) / Double(estimatedWindows) * 0.5
                            self.progressByMeetingID[meetingID] = min(0.99, max(current, p))
                        }
                        return true
                    }
                )

                let micSegments = self.makeSegments(from: micResults, source: .microphone)
                let sysSegments = self.makeSegments(from: systemResults, source: .system)
                let merged = (micSegments + sysSegments).sorted { $0.startTime < $1.startTime }
                let grouped = self.groupSegments(merged)

                let transcriptionDuration = Date().timeIntervalSince(transcriptionStartDate)
                meeting.transcriptSegmentsJSON = try? JSONEncoder().encode(grouped)
                meeting.transcript = self.formattedTranscript(from: grouped, settings: appSettings)
                meeting.status = .completed
                meeting.transcriptionError = nil
                meeting.isTranscribed = true
                meeting.transcriptionDuration = transcriptionDuration
                AppSettings.shared.updateSpeedFactor(
                    modelID: modelID,
                    audioDuration: estimatedDurationSeconds,
                    transcriptionDuration: transcriptionDuration
                )
                self.progressByMeetingID[meetingID] = 1.0

                do {
                    try modelContext.save()
                    self.requestReviewIfNeeded()
                } catch {
                    meeting.status = .failed
                    meeting.transcriptionError = "Failed to save transcript"
                    self.progressByMeetingID[meetingID] = 0
                    self.saveContext("dual save after failed transcript save")
                }
            } catch is CancellationError {
                meeting.status = .notStarted
                meeting.transcriptionError = nil
                meeting.isTranscribed = false
                self.progressByMeetingID[meetingID] = 0
                self.saveContext("dual cancellation")
            } catch {
                meeting.status = .failed
                meeting.transcriptionError = "Dual-source transcription failed: \(error.localizedDescription)"
                meeting.isTranscribed = false
                self.progressByMeetingID[meetingID] = 0
                self.saveContext("dual transcription error")
            }
        }

        tasks[meeting.id] = task
    }

    private func meetingLanguage(for meeting: Meeting, modelID: String) -> AppSettings.TranscriptionLanguage {
        // Model's locked language takes highest priority
        if let descriptor = modelManager.descriptor(for: modelID),
           let lockedRaw = descriptor.lockedLanguage,
           let lang = AppSettings.TranscriptionLanguage(rawValue: lockedRaw) {
            return lang
        }
        // Per-meeting override
        if let raw = meeting.transcriptionLanguageOverrideRaw,
           let override = AppSettings.TranscriptionLanguage(rawValue: raw) {
            return override
        }
        return AppSettings.shared.transcriptionLanguage
    }
}
