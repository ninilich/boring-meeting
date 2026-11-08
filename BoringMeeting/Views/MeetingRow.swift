import SwiftUI

/// Row view for displaying a single meeting in the list
struct MeetingRow: View {
    let meeting: Meeting
    var isQueued: Bool = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title and status icon
            HStack {
                Text(meeting.title)
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                // Status icon with tooltip
                statusIcon
            }
            
            // Date/time on the left, duration on the right.
            HStack(spacing: 8) {
                Text(AppSettings.shared.formatDate(meeting.date))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text(meeting.formattedDuration)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isHovered ? 0.07 : 0))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch meeting.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Transcribed")
                
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
                .help("Transcribing...")
                
        case .failed:
            if isQueued {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
                    .help("Queued for re-transcription")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("Transcription failed")
            }
                
        case .notStarted:
            if isQueued {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
                    .help("Queued for transcription")
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .help("Not transcribed")
            }
        }
    }
}

#Preview {
    let meeting1 = Meeting(
        date: Date(),
        duration: 1845, // 30:45
        audioFilePath: "test1.m4a",
        title: "Recording 11.02.2026 11:30"
    )
    meeting1.status = .completed
    meeting1.fileSize = 5_242_880
    
    let meeting2 = Meeting(
        date: Date(),
        duration: 525, // 08:45
        audioFilePath: "test2.m4a",
        title: "Recording 10.02.2026 09:15"
    )
    meeting2.status = .inProgress
    
    let meeting3 = Meeting(
        date: Date(),
        duration: 731, // 12:11
        audioFilePath: "test3.m4a",
        title: "Recording 09.02.2026 16:20"
    )
    meeting3.status = .notStarted
    
    return VStack(spacing: 8) {
        MeetingRow(meeting: meeting1)
        Divider()
        MeetingRow(meeting: meeting2)
        Divider()
        MeetingRow(meeting: meeting3)
    }
    .padding()
    .frame(width: 250)
}
