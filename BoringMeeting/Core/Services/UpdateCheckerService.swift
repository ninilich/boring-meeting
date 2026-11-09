import Foundation
import Combine

@MainActor
final class UpdateCheckerService: ObservableObject {
    enum ManualCheckState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(String)
        case failed(String)
    }

    struct KnownUpdate: Codable, Equatable {
        let version: String
        let appStoreURLString: String
        let detectedAt: Date
    }

    private enum CheckResult {
        case upToDate
        case updateAvailable(KnownUpdate)
        case failed(String)
    }

    private enum Keys {
        static let knownUpdate = "knownAvailableAppStoreUpdate"
        static let lastAutomaticCheckAt = "lastAutomaticAppStoreUpdateCheckAt"
    }

    @Published private(set) var knownUpdate: KnownUpdate?
    @Published private(set) var manualCheckState: ManualCheckState = .idle

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        loadKnownUpdateFromDefaults()
        clearKnownUpdateIfCurrentVersionCatchesUp()
    }

    var hasKnownUpdate: Bool {
        knownUpdate != nil
    }

    var knownUpdateURL: URL? {
        guard let urlString = knownUpdate?.appStoreURLString, !urlString.isEmpty else {
            return nil
        }
        return URL(string: urlString)
    }

    var knownUpdateVersion: String? {
        knownUpdate?.version
    }

    func checkForUpdatesIfNeeded(automaticChecksEnabled: Bool, intervalDays: Int) async {
        clearKnownUpdateIfCurrentVersionCatchesUp()

        guard automaticChecksEnabled else { return }
        guard knownUpdate == nil else { return }
        guard shouldPerformAutomaticCheck(intervalDays: intervalDays) else { return }

        _ = await performLookup(markAutomaticCheckDate: true)
    }

    func checkForUpdatesManually() async {
        clearKnownUpdateIfCurrentVersionCatchesUp()

        if let knownUpdate {
            manualCheckState = .updateAvailable(knownUpdate.version)
            return
        }

        manualCheckState = .checking

        switch await performLookup(markAutomaticCheckDate: true) {
        case .upToDate:
            manualCheckState = .upToDate
        case .updateAvailable(let known):
            manualCheckState = .updateAvailable(known.version)
        case .failed(let reason):
            manualCheckState = .failed(reason)
        }
    }

    func resetManualCheckState() {
        manualCheckState = .idle
    }

    private func performLookup(markAutomaticCheckDate: Bool) async -> CheckResult {
        defer {
            if markAutomaticCheckDate {
                defaults.set(Date(), forKey: Keys.lastAutomaticCheckAt)
            }
        }

        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return .failed("Missing bundle identifier")
        }

        let encodedBundle = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleID
        guard let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encodedBundle)") else {
            return .failed("Invalid App Store lookup URL")
        }

        do {
            let (data, response) = try await session.data(from: lookupURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return .failed("App Store lookup failed")
            }

            let payload = try JSONDecoder().decode(AppStoreLookupPayload.self, from: data)
            guard let app = payload.results.first else {
                return .failed("App not found in App Store")
            }

            let currentVersion = currentAppVersion()
            switch VersionComparator.compare(app.version, currentVersion) {
            case .orderedDescending:
                let known = KnownUpdate(
                    version: app.version,
                    appStoreURLString: resolveAppStoreURLString(for: app),
                    detectedAt: Date()
                )
                knownUpdate = known
                saveKnownUpdateToDefaults(known)
                return .updateAvailable(known)
            case .orderedSame, .orderedAscending:
                clearKnownUpdate()
                return .upToDate
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func resolveAppStoreURLString(for app: AppStoreResult) -> String {
        if let trackViewURL = app.trackViewUrl, !trackViewURL.isEmpty {
            return trackViewURL
        }

        if let trackID = app.trackId {
            return "macappstore://itunes.apple.com/app/id\(trackID)"
        }

        return ""
    }

    private func shouldPerformAutomaticCheck(intervalDays: Int) -> Bool {
        let minDays = max(intervalDays, 1)
        let interval = TimeInterval(minDays * 24 * 60 * 60)

        guard let lastCheckAt = defaults.object(forKey: Keys.lastAutomaticCheckAt) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastCheckAt) >= interval
    }

    private func clearKnownUpdateIfCurrentVersionCatchesUp() {
        guard let known = knownUpdate else { return }

        if VersionComparator.compare(currentAppVersion(), known.version) != .orderedAscending {
            clearKnownUpdate()
        }
    }

    private func currentAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func loadKnownUpdateFromDefaults() {
        guard let raw = defaults.data(forKey: Keys.knownUpdate) else {
            knownUpdate = nil
            return
        }

        knownUpdate = try? JSONDecoder().decode(KnownUpdate.self, from: raw)
    }

    private func saveKnownUpdateToDefaults(_ update: KnownUpdate) {
        guard let encoded = try? JSONEncoder().encode(update) else { return }
        defaults.set(encoded, forKey: Keys.knownUpdate)
    }

    private func clearKnownUpdate() {
        knownUpdate = nil
        defaults.removeObject(forKey: Keys.knownUpdate)
    }
}

private struct AppStoreLookupPayload: Decodable {
    let results: [AppStoreResult]
}

private struct AppStoreResult: Decodable {
    let version: String
    let trackViewUrl: String?
    let trackId: Int?
}
