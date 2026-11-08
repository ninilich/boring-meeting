import ArgumentParser

struct BMeeting: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bmeeting",
        abstract: "CLI for BoringMeeting — list meetings, read transcripts, trigger transcription.",
        discussion: """
            Requires BoringMeeting to be running with CLI API enabled:
            Settings → General → CLI API → Enable CLI API

            Examples:
              bmeeting list --format text
              bmeeting info <id>
              bmeeting transcribe <id> --wait
              bmeeting transcript <id>
              bmeeting rename <id> "New title"

            The port can be overridden via the BMEETING_PORT environment variable (default: 49484).
            """,
        version: "0.5.0",
        subcommands: [
            ListCommand.self,
            InfoCommand.self,
            TranscriptCommand.self,
            TranscribeCommand.self,
            RenameCommand.self,
        ]
    )
}

BMeeting.main()
