import AVFoundation

enum AudioTrimmerError: LocalizedError {
    case exportSessionUnavailable
    case exportFailed(String?)

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable:
            return "Cannot create export session for this audio file"
        case .exportFailed(let msg):
            return "Trim failed: \(msg ?? "unknown error")"
        }
    }
}

struct AudioTrimmer {
    /// Trims `url` to [start, end] seconds, atomically replacing the original file.
    /// Returns the new duration and file size.
    static func trim(url: URL, from start: TimeInterval, to end: TimeInterval) async throws -> (duration: TimeInterval, fileSize: Int64) {
        let asset = AVURLAsset(url: url)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AudioTrimmerError.exportSessionUnavailable
        }

        let ext = url.pathExtension.lowercased()
        let fileType: AVFileType = ext == "m4a" ? .m4a : .caf

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 1000),
            end: CMTime(seconds: end, preferredTimescale: 1000)
        )

        try await session.export(to: tempURL, as: fileType)

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        return (duration: end - start, fileSize: fileSize)
    }
}
