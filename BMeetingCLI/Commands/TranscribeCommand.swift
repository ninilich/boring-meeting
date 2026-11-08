import ArgumentParser
import Foundation

struct TranscribeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Start transcription for a meeting."
    )

    @Argument(help: "Meeting ID (UUID)")
    var id: String

    @Flag(name: .long, help: "Wait for transcription to complete before exiting")
    var wait = false

    @Option(name: .long, help: "Polling interval in seconds when --wait is used (default: 5)")
    var pollInterval: Int = 5

    @Option(name: .long, help: "Output format: json (default) or text")
    var format: OutputFormat = .json

    func run() throws {
        let client = BoringMeetingClient()

        // Start transcription
        do {
            _ = try client.post("/meetings/\(id)/transcribe")
        } catch {
            handleConnectionError(error)
        }

        if format == .text {
            print("Transcription started.")
        } else {
            print(#"{"status":"transcription_started"}"#)
        }

        guard wait else { return }

        // Poll until done
        while true {
            Thread.sleep(forTimeInterval: Double(pollInterval))

            let infoData: Data
            do {
                infoData = try client.get("/meetings/\(id)")
            } catch {
                handleConnectionError(error)
            }

            let meeting = decodeOrExit(MeetingItem.self, from: infoData)

            switch meeting.transcriptionStatus {
            case "completed":
                if format == .text {
                    print("Transcription completed.")
                } else {
                    printOutput(meeting, format: .json)
                }
                return

            case "failed":
                let msg = meeting.transcriptionError ?? "Unknown error"
                fputs("Error: transcription failed — \(msg)\n", stderr)
                throw ExitCode(1)

            default:
                let pct = Int(meeting.progress * 100)
                fputs("Progress: \(pct)%\n", stderr)
            }
        }
    }
}
