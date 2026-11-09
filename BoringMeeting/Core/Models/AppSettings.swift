import Foundation
import Combine

/// Application settings stored in UserDefaults
class AppSettings: ObservableObject {

    static let debugLogsEnvKey = "BORINGMEETING_DEBUG_LOGS"

    static var isDebugLogsEnabled: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment[debugLogsEnvKey] == "1"
#else
        return false
#endif
    }

    static let shared = AppSettings()

    static var recordingsRootURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        return appSupportURL
            .appendingPathComponent("BoringMeeting", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static let updateCheckIntervalDays = 3

    private let defaults = UserDefaults.standard

    // Keys
    private enum Keys {
        static let dateTimeFormat = "dateTimeFormat"
        static let defaultTranscriptionModelID = "defaultTranscriptionModelID"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let unloadModelAfterTranscription = "unloadModelAfterTranscription"
        static let transcriptionsCompleted = "transcriptionsCompleted"
        static let reviewPromptsEnabled = "reviewPromptsEnabled"
        static let visibleLanguageIDs = "visibleLanguageIDs"
        static let updatesCheckEnabled = "updatesCheckEnabled"
        static let splitAudioSources = "splitAudioSources"
        static let micSourceName = "micSourceName"
        static let systemSourceName = "systemSourceName"
        static let suppressedWhatsNewVersion = "suppressedWhatsNewVersion"
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
        static let hideMenuBarIcon = "hideMenuBarIcon"
        static let cliAPIEnabled = "cliAPIEnabled"
        static let cliAPIPort = "cliAPIPort"
        static let transcriptionSpeedSamples = "transcriptionSpeedSamples"
        static let speedFactorsMigrated = "speedFactorsMigrated"
        static let autoDeleteAfterDays = "autoDeleteAfterDays"
        static let lastMeetingCleanupDate = "lastMeetingCleanupDate"
        static let recordingPanelPosition = "recordingPanelPosition"
    }

    static let defaultVisibleLanguageIDs: Set<String> = [
        "en", "ru", "es", "fr", "de", "it", "ja", "ko", "zh", "pt"
    ]

    enum RecordingPanelPosition: String, CaseIterable, Identifiable {
        case top
        case bottom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .top: return "Top"
            case .bottom: return "Bottom"
            }
        }
    }

    // Date/Time format options
    enum DateTimeFormat: String, CaseIterable, Identifiable {
        case ddMMyyyyHHmm = "dd.MM.yyyy HH:mm"
        case MMddyyyyHHmm = "MM/dd/yyyy HH:mm"
        case yyyyMMddHHmm = "yyyy-MM-dd HH:mm"
        case ddMMMyyyyHHmm = "dd MMM yyyy HH:mm"
        case custom = "custom"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ddMMyyyyHHmm: return "DD.MM.YYYY HH:mm"
            case .MMddyyyyHHmm: return "MM/DD/YYYY HH:mm"
            case .yyyyMMddHHmm: return "YYYY-MM-DD HH:mm"
            case .ddMMMyyyyHHmm: return "DD MMM YYYY HH:mm"
            case .custom: return "Custom..."
            }
        }
    }

    enum TranscriptionLanguage: String, CaseIterable, Identifiable {
        case auto
        case english = "en"
        case spanish = "es"
        case russian = "ru"
        case german = "de"
        case french = "fr"
        case portuguese = "pt"
        case italian = "it"
        case dutch = "nl"
        case polish = "pl"
        case turkish = "tr"
        case ukrainian = "uk"
        case arabic = "ar"
        case bulgarian = "bg"
        case catalan = "ca"
        case chinese = "zh"
        case croatian = "hr"
        case czech = "cs"
        case danish = "da"
        case finnish = "fi"
        case greek = "el"
        case hebrew = "he"
        case hindi = "hi"
        case hungarian = "hu"
        case indonesian = "id"
        case japanese = "ja"
        case korean = "ko"
        case norwegian = "no"
        case romanian = "ro"
        case serbian = "sr"
        case slovak = "sk"
        case swedish = "sv"
        case vietnamese = "vi"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .english: return "English"
            case .spanish: return "Spanish"
            case .russian: return "Russian"
            case .german: return "German"
            case .french: return "French"
            case .portuguese: return "Portuguese"
            case .italian: return "Italian"
            case .dutch: return "Dutch"
            case .polish: return "Polish"
            case .turkish: return "Turkish"
            case .ukrainian: return "Ukrainian"
            case .arabic: return "Arabic"
            case .bulgarian: return "Bulgarian"
            case .catalan: return "Catalan"
            case .chinese: return "Chinese"
            case .croatian: return "Croatian"
            case .czech: return "Czech"
            case .danish: return "Danish"
            case .finnish: return "Finnish"
            case .greek: return "Greek"
            case .hebrew: return "Hebrew"
            case .hindi: return "Hindi"
            case .hungarian: return "Hungarian"
            case .indonesian: return "Indonesian"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .norwegian: return "Norwegian"
            case .romanian: return "Romanian"
            case .serbian: return "Serbian"
            case .slovak: return "Slovak"
            case .swedish: return "Swedish"
            case .vietnamese: return "Vietnamese"
            }
        }
    }

    // MARK: - Properties

    /// Selected date/time format
    @Published var dateTimeFormat: DateTimeFormat {
        didSet {
            defaults.set(dateTimeFormat.rawValue, forKey: Keys.dateTimeFormat)
        }
    }

    /// Custom date format pattern (if dateTimeFormat == .custom)
    @Published var customDateFormat: String {
        didSet {
            defaults.set(customDateFormat, forKey: "customDateFormat")
        }
    }

    /// Default model for manual transcription
    @Published var defaultTranscriptionModelID: String {
        didSet {
            defaults.set(defaultTranscriptionModelID, forKey: Keys.defaultTranscriptionModelID)
        }
    }

    /// Preferred language for transcription
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            defaults.set(transcriptionLanguage.rawValue, forKey: Keys.transcriptionLanguage)
        }
    }

    /// If enabled, unloads the transcription model from RAM after each completed run
    @Published var unloadModelAfterTranscription: Bool {
        didSet {
            defaults.set(unloadModelAfterTranscription, forKey: Keys.unloadModelAfterTranscription)
        }
    }

    /// Total number of successfully completed transcriptions
    @Published var transcriptionsCompleted: Int {
        didSet {
            defaults.set(transcriptionsCompleted, forKey: Keys.transcriptionsCompleted)
        }
    }

    /// Whether to prompt the user for an App Store review at milestones
    @Published var reviewPromptsEnabled: Bool {
        didSet {
            defaults.set(reviewPromptsEnabled, forKey: Keys.reviewPromptsEnabled)
        }
    }

    /// Set of language rawValues visible in the transcription picker
    @Published var visibleLanguageIDs: Set<String> {
        didSet {
            defaults.set(Array(visibleLanguageIDs), forKey: Keys.visibleLanguageIDs)
        }
    }

    /// Whether app can perform background update checks for new App Store versions
    @Published var updatesCheckEnabled: Bool {
        didSet {
            defaults.set(updatesCheckEnabled, forKey: Keys.updatesCheckEnabled)
        }
    }

    /// Version for which launch-time What's New is suppressed
    @Published var suppressedWhatsNewVersion: String {
        didSet {
            defaults.set(suppressedWhatsNewVersion, forKey: Keys.suppressedWhatsNewVersion)
        }
    }

    /// Last app version for which What's New was shown
    @Published var lastSeenWhatsNewVersion: String {
        didSet {
            defaults.set(lastSeenWhatsNewVersion, forKey: Keys.lastSeenWhatsNewVersion)
        }
    }

    /// Whether to run dual-source (mic + system) transcription (beta)
    @Published var splitAudioSources: Bool {
        didSet {
            defaults.set(splitAudioSources, forKey: Keys.splitAudioSources)
        }
    }

    /// Display name for the microphone audio source
    @Published var micSourceName: String {
        didSet {
            let trimmed = micSourceName.trimmingCharacters(in: .whitespaces)
            if trimmed != micSourceName { micSourceName = trimmed; return }
            defaults.set(micSourceName, forKey: Keys.micSourceName)
        }
    }

    /// Display name for the system audio source
    @Published var systemSourceName: String {
        didSet {
            let trimmed = systemSourceName.trimmingCharacters(in: .whitespaces)
            if trimmed != systemSourceName { systemSourceName = trimmed; return }
            defaults.set(systemSourceName, forKey: Keys.systemSourceName)
        }
    }

    /// Whether to hide the menu bar icon
    @Published var hideMenuBarIcon: Bool {
        didSet {
            defaults.set(hideMenuBarIcon, forKey: Keys.hideMenuBarIcon)
        }
    }

    /// Whether the local CLI HTTP API server is enabled
    @Published var cliAPIEnabled: Bool {
        didSet {
            defaults.set(cliAPIEnabled, forKey: Keys.cliAPIEnabled)
        }
    }

    /// Port for the local CLI HTTP API server
    @Published var cliAPIPort: Int {
        didSet {
            defaults.set(cliAPIPort, forKey: Keys.cliAPIPort)
        }
    }

    /// Auto-delete recordings older than this many days. 0 = disabled.
    @Published var autoDeleteAfterDays: Int {
        didSet {
            defaults.set(autoDeleteAfterDays, forKey: Keys.autoDeleteAfterDays)
        }
    }

    /// Position of the recording panel in the sidebar
    @Published var recordingPanelPosition: RecordingPanelPosition {
        didSet {
            defaults.set(recordingPanelPosition.rawValue, forKey: Keys.recordingPanelPosition)
        }
    }

    /// Last time the auto-delete cleanup ran (used to enforce once-per-day cadence).
    var lastMeetingCleanupDate: Date? {
        get { defaults.object(forKey: Keys.lastMeetingCleanupDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastMeetingCleanupDate) }
    }

    /// All non-auto languages sorted alphabetically
    static let allNonAutoLanguages: [TranscriptionLanguage] = TranscriptionLanguage.allCases
        .filter { $0 != .auto }
        .sorted { $0.displayName < $1.displayName }

    // MARK: - Initialization

    private init() {
        // Load saved settings or use defaults
        if let savedFormat = defaults.string(forKey: Keys.dateTimeFormat),
           let format = DateTimeFormat(rawValue: savedFormat) {
            self.dateTimeFormat = format
        } else {
            self.dateTimeFormat = .ddMMyyyyHHmm
        }

        self.customDateFormat = defaults.string(forKey: "customDateFormat") ?? "dd.MM.yyyy HH:mm"

        self.defaultTranscriptionModelID = defaults.string(forKey: Keys.defaultTranscriptionModelID) ?? "base"

        if let savedLanguage = defaults.string(forKey: Keys.transcriptionLanguage),
           let language = TranscriptionLanguage(rawValue: savedLanguage) {
            self.transcriptionLanguage = language
        } else {
            self.transcriptionLanguage = .auto
        }

        self.unloadModelAfterTranscription = defaults.object(forKey: Keys.unloadModelAfterTranscription) as? Bool ?? false

        self.transcriptionsCompleted = defaults.integer(forKey: Keys.transcriptionsCompleted)
        self.reviewPromptsEnabled = defaults.object(forKey: Keys.reviewPromptsEnabled) as? Bool ?? true

        if let saved = defaults.array(forKey: Keys.visibleLanguageIDs) as? [String] {
            self.visibleLanguageIDs = Set(saved)
        } else {
            self.visibleLanguageIDs = AppSettings.defaultVisibleLanguageIDs
        }

        self.updatesCheckEnabled = defaults.object(forKey: Keys.updatesCheckEnabled) as? Bool ?? true
        self.splitAudioSources = defaults.object(forKey: Keys.splitAudioSources) as? Bool ?? true
        self.micSourceName = (defaults.string(forKey: Keys.micSourceName) ?? "Microphone").trimmingCharacters(in: .whitespaces)
        self.systemSourceName = (defaults.string(forKey: Keys.systemSourceName) ?? "System Audio").trimmingCharacters(in: .whitespaces)
        self.suppressedWhatsNewVersion = defaults.string(forKey: Keys.suppressedWhatsNewVersion) ?? ""
        self.lastSeenWhatsNewVersion = defaults.string(forKey: Keys.lastSeenWhatsNewVersion) ?? ""
        self.hideMenuBarIcon = defaults.object(forKey: Keys.hideMenuBarIcon) as? Bool ?? false
        self.cliAPIEnabled = defaults.object(forKey: Keys.cliAPIEnabled) as? Bool ?? false
        self.cliAPIPort = defaults.object(forKey: Keys.cliAPIPort) as? Int ?? 49484
        self.autoDeleteAfterDays = defaults.object(forKey: Keys.autoDeleteAfterDays) as? Int ?? 0

        if let saved = defaults.string(forKey: Keys.recordingPanelPosition),
           let position = RecordingPanelPosition(rawValue: saved) {
            self.recordingPanelPosition = position
        } else {
            self.recordingPanelPosition = .top
        }
    }

    // MARK: - Helpers

    /// Get current date format pattern
    var currentDateFormatPattern: String {
        if dateTimeFormat == .custom {
            return customDateFormat
        } else {
            return dateTimeFormat.rawValue
        }
    }

    /// Format date with current settings
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = currentDateFormatPattern
        return formatter.string(from: date)
    }

    /// Generate default recording title
    func generateRecordingTitle(for date: Date) -> String {
        return "Recording \(formatDate(date))"
    }

    // MARK: - Transcription Speed Statistics

    /// Returns the best available speed factor estimate for a model.
    /// - isMeasured = true: direct samples exist for this model on this machine.
    /// - isMeasured = false: inferred from other models' measurements via machine profile,
    ///   or falls back to pure catalog value — both show with asterisk in UI.
    /// Returns nil only when there are no measurements at all AND catalogFactor is nil.
    func resolvedSpeedFactor(for modelID: String, catalogFactor: Double) -> (factor: Double, isMeasured: Bool)? {
        if let direct = directMeasuredFactor(for: modelID) {
            return (direct, true)
        }
        if let machineFactor = averageMachineFactor(), machineFactor > 0 {
            return (catalogFactor * machineFactor, false)
        }
        return nil
    }

    /// Returns the average real-time speed factor for a model based on measured samples.
    /// Returns nil if no valid samples exist (use catalog fallback).
    func speedFactor(for modelID: String) -> Double? {
        directMeasuredFactor(for: modelID)
    }

    private func directMeasuredFactor(for modelID: String) -> Double? {
        let samples = loadSpeedSamples()
        guard let values = samples[modelID], !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Computes how much faster/slower this machine is compared to catalog baseline,
    /// averaged across all models that have at least one measurement.
    private func averageMachineFactor() -> Double? {
        let samples = loadSpeedSamples()
        guard !samples.isEmpty else { return nil }
        var factors: [Double] = []
        for model in AIModelCatalog.transcriptionModels {
            guard let values = samples[model.id], !values.isEmpty else { continue }
            let measured = values.reduce(0, +) / Double(values.count)
            factors.append(measured / model.catalogSpeedFactor)
        }
        guard !factors.isEmpty else { return nil }
        return factors.reduce(0, +) / Double(factors.count)
    }

    var isSpeedFactorsMigrated: Bool {
        get { defaults.bool(forKey: Keys.speedFactorsMigrated) }
        set { defaults.set(newValue, forKey: Keys.speedFactorsMigrated) }
    }

    var hasAnySpeedFactorData: Bool {
        !loadSpeedSamples().isEmpty
    }

    /// Records a new speed factor sample. Only accepts runs where audio is ≥10 minutes.
    /// Keeps the last 10 samples per model, discarding the oldest when the cap is reached.
    func updateSpeedFactor(modelID: String, audioDuration: TimeInterval, transcriptionDuration: TimeInterval) {
        guard audioDuration >= 600, transcriptionDuration > 0 else { return }
        let factor = audioDuration / transcriptionDuration
        var samples = loadSpeedSamples()
        var values = samples[modelID] ?? []
        values.append(factor)
        if values.count > 10 { values.removeFirst() }
        samples[modelID] = values
        saveSpeedSamples(samples)
    }

    private func loadSpeedSamples() -> [String: [Double]] {
        guard let data = defaults.data(forKey: Keys.transcriptionSpeedSamples),
              let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveSpeedSamples(_ samples: [String: [Double]]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: Keys.transcriptionSpeedSamples)
    }

    @discardableResult
    static func ensureRecordingsRootExists() throws -> URL {
        let rootURL = recordingsRootURL

        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }
}
