import SwiftUI

struct TrimRangeSlider: View {
    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval
    let duration: TimeInterval
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragTarget: DragTarget? = nil

    private enum DragTarget { case start, end, seek }

    private let trackHeight: CGFloat = 4
    private let handleWidth: CGFloat = 5
    private let handleHeight: CGFloat = 22
    private let hitSlop: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let startX = xPos(trimStart, in: w)
            let endX = xPos(trimEnd, in: w)
            let headX = xPos(currentTime, in: w)

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity)

                // Active (kept) region
                Rectangle()
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)
                    .frame(maxHeight: .infinity)

                // Playhead
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: 2, height: handleHeight - 4)
                    .offset(x: headX - 1)

                // Start handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.accentColor)
                    .frame(width: handleWidth, height: handleHeight)
                    .offset(x: startX - handleWidth / 2)

                // End handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.accentColor)
                    .frame(width: handleWidth, height: handleHeight)
                    .offset(x: endX - handleWidth / 2)
            }
            .frame(height: handleHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedX = max(0, min(w, value.location.x))
                        let t = xToTime(clampedX, in: w)

                        if dragTarget == nil {
                            let sx = xPos(trimStart, in: w)
                            let ex = xPos(trimEnd, in: w)
                            let ox = value.startLocation.x
                            if abs(ox - sx) <= hitSlop {
                                dragTarget = .start
                            } else if abs(ox - ex) <= hitSlop {
                                dragTarget = .end
                            } else {
                                dragTarget = .seek
                            }
                        }

                        switch dragTarget {
                        case .start:
                            trimStart = max(0, min(trimEnd - 0.5, t))
                        case .end:
                            trimEnd = max(trimStart + 0.5, min(duration, t))
                        case .seek:
                            onSeek(max(0, min(duration, t)))
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in dragTarget = nil }
            )
        }
        .frame(height: handleHeight)
    }

    private func xPos(_ time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func xToTime(_ x: CGFloat, in width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return TimeInterval(x / width) * duration
    }
}
