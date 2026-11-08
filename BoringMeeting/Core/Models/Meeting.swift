import Foundation
import SwiftData

/// Transcription status enum
enum TranscriptionStatus: String, Codable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
}

// MARK: - Schema V1 (v0.4.x — had summary field)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SchemaV1.Meeting.self] }

    @Model final class Meeting {
        var id: UUID
        var date: Date
        var duration: TimeInterval
        var audioFilePath: String
        var transcript: String
        var summary: String
        var title: String
        var isTranscribed: Bool
        var transcriptionStatus: String
        var transcriptionError: String?
        var transcriptionModelUsedID: String?
        var transcriptionLanguageUsedRaw: String?
        var transcriptionLanguageOverrideRaw: String?
        var transcriptionDuration: TimeInterval?
        var fileSize: Int64
        var transcriptSegmentsJSON: Data?

        init(
            date: Date = Date(),
            duration: TimeInterval = 0,
            audioFilePath: String = "",
            title: String = ""
        ) {
            self.id = UUID()
            self.date = date
            self.duration = duration
            self.audioFilePath = audioFilePath
            self.transcript = ""
            self.summary = ""
            self.title = title
            self.isTranscribed = false
            self.transcriptionStatus = "not_started"
            self.fileSize = 0
        }
    }
}

// MARK: - Schema V2 (v0.5.0 — current, no summary)

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [SchemaV2.Meeting.self] }

    @Model final class Meeting {

        var id: UUID
        var date: Date
        var duration: TimeInterval
        var audioFilePath: String
        var transcript: String
        var title: String
        var isTranscribed: Bool
        var transcriptionStatus: String
        var transcriptionError: String?
        var transcriptionModelUsedID: String?
        var transcriptionLanguageUsedRaw: String?
        var transcriptionLanguageOverrideRaw: String?
        var transcriptionDuration: TimeInterval?
        var fileSize: Int64
        var transcriptSegmentsJSON: Data?

        init(
            date: Date = Date(),
            duration: TimeInterval = 0,
            audioFilePath: String,
            title: String = "New Meeting"
        ) {
            self.id = UUID()
            self.date = date
            self.duration = duration
            self.audioFilePath = audioFilePath
            self.transcript = ""
            self.title = title
            self.isTranscribed = false
            self.transcriptionStatus = TranscriptionStatus.notStarted.rawValue
            self.transcriptionError = nil
            self.transcriptionModelUsedID = nil
            self.transcriptionLanguageUsedRaw = nil
            self.transcriptionLanguageOverrideRaw = nil
            self.transcriptionDuration = nil
            self.fileSize = 0
            self.transcriptSegmentsJSON = nil
        }

        var status: TranscriptionStatus {
            get { TranscriptionStatus(rawValue: transcriptionStatus) ?? .notStarted }
            set { transcriptionStatus = newValue.rawValue }
        }

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        var formattedDuration: String {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            let seconds = Int(duration) % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%02d:%02d", minutes, seconds)
            }
        }

        var formattedFileSize: String {
            let kb = Double(fileSize) / 1024
            let mb = kb / 1024
            let gb = mb / 1024
            if gb >= 1 {
                return String(format: "%.1f GB", gb)
            } else if mb >= 1 {
                return String(format: "%.1f MB", mb)
            } else {
                return String(format: "%.1f KB", kb)
            }
        }

        var fullAudioPath: URL? {
            AppSettings.recordingsRootURL.appendingPathComponent(audioFilePath)
        }
    }
}

// MARK: - Current alias — all app code uses Meeting without namespace

typealias Meeting = SchemaV2.Meeting
