import ArgumentParser
import Foundation

struct TranscriptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript",
        abstract: "Print the transcript for a meeting."
    )

    @Argument(help: "Meeting ID (UUID)")
    var id: String

    func run() throws {
        let client = BoringMeetingClient()
        let data: Data
        do {
            data = try client.get("/meetings/\(id)/transcript")
        } catch {
            handleConnectionError(error)
        }

        if let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            fputs("Error: could not decode transcript\n", stderr)
            throw ExitCode(1)
        }
    }
}
