import Foundation

/// Describes one downloadable AI model shown in settings and action sheets.
struct AIModelDescriptor: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let memoryLabel: String
    let qualityLabel: String
    let speedLabel: String
    /// Numeric real-time speed factor from the catalog (used as baseline for machine-profile inference).
    let catalogSpeedFactor: Double
    /// If non-nil, this model only supports that language (rawValue of TranscriptionLanguage, e.g. "en").
    let lockedLanguage: String?
    /// Override variant string passed to WhisperKit download/load when it differs from `id` (e.g. a HuggingFace repo variant name that doesn't match the catalog ID). nil means use `id` as-is.
    let whisperKitVariantID: String?

    var subtitle: String {
        let langSuffix = lockedLanguage.map { " • \($0.uppercased()) only" } ?? ""
        return "\(sizeLabel) • \(memoryLabel) • \(qualityLabel) • \(speedLabel)\(langSuffix)"
    }

    init(id: String, displayName: String, sizeLabel: String, memoryLabel: String,
         qualityLabel: String, speedLabel: String, catalogSpeedFactor: Double,
         lockedLanguage: String? = nil, whisperKitVariantID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.sizeLabel = sizeLabel
        self.memoryLabel = memoryLabel
        self.qualityLabel = qualityLabel
        self.speedLabel = speedLabel
        self.catalogSpeedFactor = catalogSpeedFactor
        self.lockedLanguage = lockedLanguage
        self.whisperKitVariantID = whisperKitVariantID
    }
}

enum AIModelCatalog {
    static let transcriptionModels: [AIModelDescriptor] = [
        // Multilingual models
        .init(id: "tiny",          displayName: "tiny",          sizeLabel: "75 MB",   memoryLabel: "~1 GB",  qualityLabel: "Low",       speedLabel: "~30x",  catalogSpeedFactor: 30),
        .init(id: "base",          displayName: "base",          sizeLabel: "142 MB",  memoryLabel: "~1 GB",  qualityLabel: "Basic",     speedLabel: "~15x",  catalogSpeedFactor: 15),
        .init(id: "small",         displayName: "small",         sizeLabel: "466 MB",  memoryLabel: "~2 GB",  qualityLabel: "Standard",  speedLabel: "~6x",   catalogSpeedFactor: 6),
        .init(id: "medium",        displayName: "medium",        sizeLabel: "1.5 GB",  memoryLabel: "~5 GB",  qualityLabel: "High",      speedLabel: "~2x",   catalogSpeedFactor: 2),
        // English-only variants — faster and more accurate for English
        .init(id: "tiny.en",   displayName: "tiny.en",   sizeLabel: "75 MB",   memoryLabel: "~1 GB",  qualityLabel: "Low",       speedLabel: "~35x",  catalogSpeedFactor: 35,  lockedLanguage: "en"),
        .init(id: "base.en",   displayName: "base.en",   sizeLabel: "142 MB",  memoryLabel: "~1 GB",  qualityLabel: "Basic",     speedLabel: "~18x",  catalogSpeedFactor: 18,  lockedLanguage: "en"),
        .init(id: "small.en",  displayName: "small.en",  sizeLabel: "466 MB",  memoryLabel: "~2 GB",  qualityLabel: "Standard",  speedLabel: "~8x",   catalogSpeedFactor: 8,   lockedLanguage: "en"),
        .init(id: "medium.en", displayName: "medium.en", sizeLabel: "1.5 GB",  memoryLabel: "~5 GB",  qualityLabel: "High",      speedLabel: "~2.5x", catalogSpeedFactor: 2.5, lockedLanguage: "en"),
        // Distil-whisper: ~6x faster than large-v3 at near-equivalent quality for English
        .init(id: "distil-large-v3", displayName: "distil-large-v3", sizeLabel: "~1.5 GB", memoryLabel: "~5 GB", qualityLabel: "Very high", speedLabel: "~6x", catalogSpeedFactor: 6, lockedLanguage: "en"),
        .init(id: "large-v3_turbo", displayName: "large-v3 turbo", sizeLabel: "~3 GB",  memoryLabel: "~8 GB",  qualityLabel: "Very high", speedLabel: "~1.5x", catalogSpeedFactor: 1.5),
        .init(id: "large-v3",       displayName: "large-v3",       sizeLabel: "3 GB",    memoryLabel: "~10 GB", qualityLabel: "Very high", speedLabel: "~1x",   catalogSpeedFactor: 1),
    ]
}
