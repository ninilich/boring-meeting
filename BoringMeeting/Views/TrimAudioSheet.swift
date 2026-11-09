import SwiftUI
import AVFoundation

struct TrimAudioSheet: View {
    let audioURL: URL
    let totalDuration: TimeInterval
    let onTrimComplete: (TimeInterval, Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayerManager()

    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var isTrimming = false
    @State private var trimError: String?
    @State private var showConfirmation = false

    private var newDuration: TimeInterval { max(0, trimEnd - trimStart) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Trim Recording")
                .font(.title2).bold()

            Divider()

            playerSection

            Divider()

            markerInfoRow

            if let error = trimError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(isTrimming)

                Spacer()

                if isTrimming {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button {
                    showConfirmation = true
                } label: {
                    Label("Trim & Save", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTrimming || newDuration <= 0 || (trimStart == 0 && trimEnd == totalDuration))
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            player.loadAudio(url: audioURL)
            trimEnd = totalDuration
        }
        .onDisappear {
            player.stop()
        }
        .alert("Replace Recording?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Trim & Save", role: .destructive) { performTrim() }
        } message: {
            Text("This will permanently replace the recording. It cannot be undone.")
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { player.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!player.isLoaded)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!player.isLoaded)

                Button { player.skip(by: 15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!player.isLoaded)

                Spacer()

                Text("\(player.currentTime.formattedTime()) / \(player.duration.formattedTime())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }

            TrimRangeSlider(
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                duration: totalDuration,
                currentTime: player.currentTime
            ) { newTime in
                player.seek(to: totalDuration > 0 ? newTime / totalDuration : 0)
            }
            .disabled(!player.isLoaded)
        }
    }

    // MARK: - Marker Info Row

    private var markerInfoRow: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Set Start") {
                    trimStart = player.currentTime
                    if trimStart >= trimEnd { trimEnd = min(totalDuration, trimStart + 1) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!player.isLoaded)

                Spacer()

                Text(trimStart.formattedTime())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.5))

                Text(trimEnd.formattedTime())
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Set End") {
                    trimEnd = player.currentTime
                    if trimEnd <= trimStart { trimStart = max(0, trimEnd - 1) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!player.isLoaded)
            }

            Text("Keeping \(newDuration.formattedTime()) of \(totalDuration.formattedTime())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Actions

    private func performTrim() {
        isTrimming = true
        trimError = nil
        Task {
            do {
                let result = try await AudioTrimmer.trim(url: audioURL, from: trimStart, to: trimEnd)
                await MainActor.run {
                    onTrimComplete(result.duration, result.fileSize)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    trimError = error.localizedDescription
                    isTrimming = false
                }
            }
        }
    }
}
