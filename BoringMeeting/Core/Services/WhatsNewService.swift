import Foundation

@MainActor
final class WhatsNewService {
    struct ReleaseNote: Codable, Equatable, Identifiable {
        let version: String
        let title: String
        let highlights: [String]
        let details: String?

        var id: String { version }
    }

    private struct Manifest: Codable {
        let schemaVersion: Int
        let versions: [ReleaseNote]
    }

    private let decoder = JSONDecoder()
    private let manifestLoader: () -> Data?
    private let appVersionProvider: () -> String?

    init(
        manifestLoader: @escaping () -> Data? = WhatsNewService.defaultManifestLoader,
        appVersionProvider: @escaping () -> String? = WhatsNewService.defaultAppVersion
    ) {
        self.manifestLoader = manifestLoader
        self.appVersionProvider = appVersionProvider
    }

    func currentReleaseNote() -> ReleaseNote? {
        guard let currentVersion = currentAppVersion() else { return nil }
        return releaseNote(for: currentVersion)
    }

    func allReleaseNotes() -> [ReleaseNote] {
        guard let manifest = loadManifest() else { return [] }
        return manifest.versions.sorted { lhs, rhs in
            VersionComparator.compare(lhs.version, rhs.version) == .orderedDescending
        }
    }

    func shouldShowOnLaunch(settings: AppSettings) -> Bool {
        guard let release = currentReleaseNote() else { return false }
        return settings.suppressedWhatsNewVersion != release.version
    }

    func markSeen(_ version: String, settings: AppSettings) {
        settings.lastSeenWhatsNewVersion = version
    }

    func setSuppressedForCurrentVersion(_ suppress: Bool, settings: AppSettings) {
        guard let release = currentReleaseNote() else { return }

        if suppress {
            settings.suppressedWhatsNewVersion = release.version
        } else if settings.suppressedWhatsNewVersion == release.version {
            settings.suppressedWhatsNewVersion = ""
        }
    }

    func isSuppressedForCurrentVersion(settings: AppSettings) -> Bool {
        guard let release = currentReleaseNote() else { return false }
        return settings.suppressedWhatsNewVersion == release.version
    }

    func releaseNote(for version: String) -> ReleaseNote? {
        guard let manifest = loadManifest() else { return nil }
        return manifest.versions.first { $0.version == version }
    }

    private func loadManifest() -> Manifest? {
        guard let data = manifestLoader() else { return nil }

        return try? decoder.decode(Manifest.self, from: data)
    }

    private func currentAppVersion() -> String? {
        let version = appVersionProvider()
        guard let version, !version.isEmpty else { return nil }
        return version
    }

    nonisolated private static func defaultManifestLoader() -> Data? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json") else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    nonisolated private static func defaultAppVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
