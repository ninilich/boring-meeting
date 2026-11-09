import ArgumentParser
import Foundation

struct RenameCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a meeting."
    )

    @Argument(help: "Meeting ID (UUID)")
    var id: String

    @Argument(help: "New title")
    var title: String

    @Option(name: .long, help: "Output format: json (default) or text")
    var format: OutputFormat = .json

    func run() throws {
        let client = BoringMeetingClient()
        let body = try JSONEncoder().encode(["title": title])

        let data: Data
        do {
            data = try client.patch("/meetings/\(id)", body: body)
        } catch {
            handleConnectionError(error)
        }

        let meeting = decodeOrExit(MeetingItem.self, from: data)

        switch format {
        case .json:
            printOutput(meeting, format: .json)
        case .text:
            print("Renamed to: \(meeting.title)")
        }
    }
}
