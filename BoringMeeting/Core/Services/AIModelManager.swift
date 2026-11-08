import Foundation
import Combine
import WhisperKit

@MainActor
final class AIModelManager: ObservableObject {
    @Published private(set) var installedTranscriptionModelIDs: Set<String>
    @Published private(set) var downloadProgressByModelID: [String: Double] = [:]
    @Published private(set) var installedSizeBytesByModelID: [String: Int64]
    @Published private(set) var downloadErrorByModelID: [String: String] = [:]

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var downloadErrorDetailByModelID: [String: String] = [:]
    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    private let installedSizeCacheKey = "installedTranscriptionModelSizeBytesByModelID"

    private let modelFilePrefixes = ["melspectrogram", "audioencoder", "textdecoder"]

    init() {
        self.installedTranscriptionModelIDs = []
        self.installedSizeBytesByModelID = [:]
        loadInstalledSizeCacheFromDefaults()
        migrateLegacyWhisperRepoIfNeeded()
        refreshInstalledTranscriptionModelsFromDisk()
    }

    var transcriptionModels: [AIModelDescriptor] {
        AIModelCatalog.transcriptionModels
    }

    func isInstalled(_ modelID: String) -> Bool {
        installedTranscriptionModelIDs.contains(modelID)
    }

    func isDownloading(_ modelID: String) -> Bool {
        downloadTasks[modelID] != nil
    }

    func progress(for modelID: String) -> Double {
        downloadProgressByModelID[modelID] ?? 0
    }

    func errorDetail(for modelID: String) -> String {
        downloadErrorDetailByModelID[modelID] ?? ""
    }

    func cachedInstalledSizeBytes(for modelID: String) -> Int64? {
        installedSizeBytesByModelID[modelID]
    }

    func descriptor(for modelID: String) -> AIModelDescriptor? {
        transcriptionModels.first { $0.id == modelID }
    }

    func lockedLanguage(for modelID: String) -> AppSettings.TranscriptionLanguage? {
        guard let raw = descriptor(for: modelID)?.lockedLanguage else { return nil }
        return AppSettings.TranscriptionLanguage(rawValue: raw)
    }

    func downloadTranscriptionModel(_ modelID: String) {
        guard !isInstalled(modelID), !isDownloading(modelID) else { return }

        downloadProgressByModelID[modelID] = 0
        downloadErrorByModelID[modelID] = nil
        downloadErrorDetailByModelID[modelID] = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                // Check service availability first
                let (available, statusCode, checkError) = await self.checkModelDownloadServiceAvailability(modelID: modelID)
                
                if !available {
                    let errorMsg = "Download service unavailable. Check your internet connection."
                    let details = "Status: \(statusCode ?? -1)\nError: \(checkError ?? "Unknown")"
                    self.downloadErrorByModelID[modelID] = errorMsg
                    self.downloadErrorDetailByModelID[modelID] = details
                    print("❌ Download check failed for \(modelID): \(details)")
                    self.downloadProgressByModelID[modelID] = 0
                    self.downloadTasks[modelID] = nil
                    return
                }

                // Service available, proceed with download
                let variantID = self.descriptor(for: modelID)?.whisperKitVariantID ?? modelID
                _ = try await WhisperKit.download(
                    variant: variantID,
                    downloadBase: self.whisperDownloadBaseURL(),
                    progressCallback: { progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.downloadProgressByModelID[modelID] = max(
                                self.downloadProgressByModelID[modelID] ?? 0,
                                progress.fractionCompleted
                            )
                        }
                    }
                )

                self.downloadProgressByModelID[modelID] = 1.0
                self.refreshInstalledTranscriptionModelsFromDisk()
                self.cacheInstalledSizeIfAvailable(for: modelID)
            } catch {
                let errorDescription = error.localizedDescription
                self.downloadErrorByModelID[modelID] = "Download failed. Please try again."
                self.downloadErrorDetailByModelID[modelID] = "Error: \(errorDescription)\nModel: \(modelID)"
                print("❌ Download failed for \(modelID): \(errorDescription)")
                self.downloadProgressByModelID[modelID] = 0
            }

            self.downloadTasks[modelID] = nil
        }

        downloadTasks[modelID] = task
    }

    private func checkModelDownloadServiceAvailability(modelID: String) async -> (available: Bool, statusCode: Int?, error: String?) {
        // Check if HuggingFace model service is reachable via API
        let apiURL = "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml"
        
        guard let url = URL(string: apiURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, nil, "Invalid response")
            }
            
            let isAvailable = (200..<300).contains(httpResponse.statusCode)
            return (isAvailable, httpResponse.statusCode, isAvailable ? nil : "HTTP \(httpResponse.statusCode)")
        } catch {
            let nsError = error as NSError
            let errorDetail = "\(nsError.domain): \(nsError.localizedDescription)"
            return (false, nil, errorDetail)
        }
    }

    func removeTranscriptionModel(_ modelID: String, fallbackDefault defaultModelID: String) {
        guard installedTranscriptionModelIDs.contains(modelID) else { return }
        guard installedTranscriptionModelIDs.count > 1 else { return }

        removeModelFolders(for: modelID)
        removeCachedInstalledSize(for: modelID)
        refreshInstalledTranscriptionModelsFromDisk()

        if defaultModelID == modelID {
            if let fallback = installedTranscriptionModelIDs.sorted().first {
                AppSettings.shared.defaultTranscriptionModelID = fallback
            }
        }
    }

    func refreshInstalledTranscriptionModelsFromDisk() {
        installedTranscriptionModelIDs = detectedInstalledTranscriptionModelIDs()
        pruneInstalledSizeCache()
    }

    private func loadInstalledSizeCacheFromDefaults() {
        guard let raw = userDefaults.dictionary(forKey: installedSizeCacheKey) else {
            installedSizeBytesByModelID = [:]
            return
        }

        var parsed: [String: Int64] = [:]
        for (key, value) in raw {
            switch value {
            case let number as NSNumber:
                parsed[key] = number.int64Value
            case let integer as Int:
                parsed[key] = Int64(integer)
            case let int64 as Int64:
                parsed[key] = int64
            case let double as Double:
                parsed[key] = Int64(double)
            default:
                continue
            }
        }

        installedSizeBytesByModelID = parsed
    }

    private func persistInstalledSizeCacheToDefaults() {
        let serializable = installedSizeBytesByModelID.mapValues { NSNumber(value: $0) }
        userDefaults.set(serializable, forKey: installedSizeCacheKey)
    }

    private func pruneInstalledSizeCache() {
        let filtered = installedSizeBytesByModelID.filter { installedTranscriptionModelIDs.contains($0.key) }
        guard filtered != installedSizeBytesByModelID else { return }
        installedSizeBytesByModelID = filtered
        persistInstalledSizeCacheToDefaults()
    }

    private func cacheInstalledSizeIfAvailable(for modelID: String) {
        guard let folder = localModelFolderURL(for: modelID) else { return }
        let size = folderSizeInBytes(folder)
        guard size > 0 else { return }
        installedSizeBytesByModelID[modelID] = size
        persistInstalledSizeCacheToDefaults()
    }

    private func removeCachedInstalledSize(for modelID: String) {
        guard installedSizeBytesByModelID.removeValue(forKey: modelID) != nil else { return }
        persistInstalledSizeCacheToDefaults()
    }

    private func folderSizeInBytes(_ folder: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }

        return total
    }

    private func detectedInstalledTranscriptionModelIDs() -> Set<String> {
        let availableModelIDs = Set(transcriptionModels.map { $0.id })
        let repoRoots = existingWhisperRepoRoots()
        guard !repoRoots.isEmpty else {
            return []
        }

        let candidateFolders = Set(repoRoots.flatMap { discoverModelCandidateFolders(in: $0) })
        guard !candidateFolders.isEmpty else {
            return []
        }

        return Set(availableModelIDs.filter { modelID in
            // Folder must match the model name AND contain ALL required model file prefixes
            candidateFolders.contains(where: { folder in
                folderNameMatchesModel(folder.lastPathComponent, modelID: modelID)
                    && isModelFolderComplete(folder)
            })
        })
    }

    /// Returns true only when every required model-file prefix is present in the folder,
    /// i.e. the download is complete and not partial.
    private func isModelFolderComplete(_ folder: URL) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        let lower = contents.map { $0.lowercased() }
        return modelFilePrefixes.allSatisfy { prefix in
            lower.contains { $0.hasPrefix(prefix) }
        }
    }

    func whisperDownloadBaseURL() -> URL? {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appSupportRoot = applicationSupport
            .appending(path: "BoringMeeting")
            .appending(path: "huggingface")

        do {
            try fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
            return appSupportRoot
        } catch {
            print("⚠️ Failed to create Whisper download base: \(error.localizedDescription)")
            return nil
        }
    }

    private func sandboxWhisperRepoRoot() -> URL? {
        guard let downloadBase = whisperDownloadBaseURL() else {
            return nil
        }

        return downloadBase
            .appending(path: "models")
            .appending(path: "argmaxinc")
            .appending(path: "whisperkit-coreml")
    }

    private func legacyWhisperRepoRoot() -> URL? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        return documents
            .appending(path: "huggingface")
            .appending(path: "models")
            .appending(path: "argmaxinc")
            .appending(path: "whisperkit-coreml")
    }

    private func existingWhisperRepoRoots() -> [URL] {
        var roots: [URL] = []

        if let sandboxRoot = sandboxWhisperRepoRoot(), fileManager.fileExists(atPath: sandboxRoot.path) {
            roots.append(sandboxRoot)
        }

        if let legacyRoot = legacyWhisperRepoRoot(),
           fileManager.fileExists(atPath: legacyRoot.path),
           !roots.contains(where: { $0.path == legacyRoot.path }) {
            roots.append(legacyRoot)
        }

        return roots
    }

    private func migrateLegacyWhisperRepoIfNeeded() {
        guard let legacyRoot = legacyWhisperRepoRoot(), fileManager.fileExists(atPath: legacyRoot.path) else {
            return
        }

        guard let sandboxRoot = sandboxWhisperRepoRoot() else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: sandboxRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !fileManager.fileExists(atPath: sandboxRoot.path) {
                try fileManager.moveItem(at: legacyRoot, to: sandboxRoot)
                return
            }

            let legacyItems = try fileManager.contentsOfDirectory(
                at: legacyRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in legacyItems {
                let destination = sandboxRoot.appending(path: item.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                try? fileManager.moveItem(at: item, to: destination)
            }

            let remaining = try fileManager.contentsOfDirectory(atPath: legacyRoot.path)
            if remaining.isEmpty {
                try? fileManager.removeItem(at: legacyRoot)
            }
        } catch {
            print("⚠️ Failed to migrate legacy Whisper models: \(error.localizedDescription)")
        }
    }

    private func discoverModelCandidateFolders(in root: URL) -> Set<URL> {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var folders: Set<URL> = []
        for case let item as URL in enumerator {
            let filename = item.lastPathComponent.lowercased()
            guard modelFilePrefixes.contains(where: { filename.hasPrefix($0) }) else {
                continue
            }

            folders.insert(item.deletingLastPathComponent())
        }

        return folders
    }

    private func folderNameMatchesModel(_ folderName: String, modelID: String) -> Bool {
        let normalizedFolderName = normalize(folderName)
        let normalizedModelID = normalize(modelID)

        if normalizedFolderName.hasSuffix(normalizedModelID) {
            return true
        }

        let tokens = normalizedFolderName
            .split(separator: "-")
            .map(String.init)

        return tokens.contains(normalizedModelID)
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Returns the path to the already-downloaded local folder for `modelID`, or nil if not found.
    func localModelFolderURL(for modelID: String) -> URL? {
        if let sandboxRoot = sandboxWhisperRepoRoot(), fileManager.fileExists(atPath: sandboxRoot.path) {
            let sandboxCandidates = discoverModelCandidateFolders(in: sandboxRoot)
            if let match = sandboxCandidates.first(where: { folder in
                folderNameMatchesModel(folder.lastPathComponent, modelID: modelID)
                    && isModelFolderComplete(folder)
            }) {
                return match
            }
        }

        if let legacyRoot = legacyWhisperRepoRoot(), fileManager.fileExists(atPath: legacyRoot.path) {
            let legacyCandidates = discoverModelCandidateFolders(in: legacyRoot)
            return legacyCandidates.first(where: { folder in
                folderNameMatchesModel(folder.lastPathComponent, modelID: modelID)
                    && isModelFolderComplete(folder)
            })
        }

        return nil
    }

    private func removeModelFolders(for modelID: String) {
        for repoRoot in existingWhisperRepoRoots() {
            guard let directoryItems = try? fileManager.contentsOfDirectory(
                at: repoRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let matches = directoryItems.filter { url in
                folderNameMatchesModel(url.lastPathComponent, modelID: modelID)
            }

            for folder in matches {
                try? fileManager.removeItem(at: folder)
            }
        }
    }
}
