import ArgumentParser
import Foundation

struct InfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show details for a specific meeting."
    )

    @Argument(help: "Meeting ID (UUID)")
    var id: String

    @Option(name: .long, help: "Output format: json (default) or text")
    var format: OutputFormat = .json

    func run() throws {
        let client = BoringMeetingClient()
        let data: Data
        do {
            data = try client.get("/meetings/\(id)")
        } catch {
            handleConnectionError(error)
        }

        let meeting = decodeOrExit(MeetingItem.self, from: data)

        switch format {
        case .json:
            printOutput(meeting, format: .json)
        case .text:
            print("ID:        \(meeting.id)")
            print("Title:     \(meeting.title)")
            print("Date:      \(meeting.date)")
            print("Duration:  \(formatDuration(meeting.duration))")
            print("Size:      \(ByteCountFormatter.string(fromByteCount: meeting.fileSize, countStyle: .file))")
            print("Status:    \(meeting.transcriptionStatus)")
            if meeting.transcriptionStatus == "in_progress" {
                print("Progress:  \(Int(meeting.progress * 100))%")
            }
            if let err = meeting.transcriptionError {
                print("Error:     \(err)")
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
