import ArgumentParser
import Foundation

struct MeetingItem: Codable {
    let id: String
    let title: String
    let date: String
    let duration: Double
    let fileSize: Int64
    let transcriptionStatus: String
    let progress: Double
    let isTranscribed: Bool
    let transcriptionError: String?
}

struct MeetingList: Codable {
    let meetings: [MeetingItem]
    let total: Int
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all recorded meetings."
    )

    @Option(name: .long, help: "Output format: json (default) or text")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Maximum number of meetings to show")
    var limit: Int?

    func run() throws {
        let client = BoringMeetingClient()
        let data: Data
        do {
            data = try client.get("/meetings")
        } catch {
            handleConnectionError(error)
        }

        var list = decodeOrExit(MeetingList.self, from: data)
        if let limit {
            list = MeetingList(meetings: Array(list.meetings.prefix(limit)), total: list.total)
        }

        switch format {
        case .json:
            printOutput(list, format: .json)
        case .text:
            if list.meetings.isEmpty {
                print("No meetings found.")
                return
            }
            print(String(format: "%-38s %-30s %-10s %-12s", "ID", "Title", "Duration", "Status"))
            print(String(repeating: "-", count: 96))
            for m in list.meetings {
                let dur = formatDuration(m.duration)
                let title = String(m.title.prefix(28))
                let status = m.transcriptionStatus
                print(String(format: "%-38s %-30s %-10s %-12s", m.id, title, dur, status))
            }
            print("\nTotal: \(list.total) meetings")
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
