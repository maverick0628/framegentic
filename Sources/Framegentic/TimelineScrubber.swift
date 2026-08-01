import SwiftUI

struct TimelineScrubber: View {
    let frameCount: Int
    @Binding var playhead: Int
    @Binding var clipStart: Int
    @Binding var clipEnd: Int
    let selectedDuration: String
    let oldestTimeAgo: String

    private enum DragHandle { case start, end, playhead }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(oldestTimeAgo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("selected: \(selectedDuration)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("now")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let totalFrames = max(frameCount - 1, 1)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    let startX = xPosition(for: clipStart, in: width, total: totalFrames)
                    let endX = xPosition(for: clipEnd, in: width, total: totalFrames)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: max(endX - startX, 2), height: 4)
                        .offset(x: startX)

                    ForEach(0..<frameCount, id: \.self) { i in
                        let x = xPosition(for: i, in: width, total: totalFrames)
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 1, height: 6)
                            .offset(x: x - 0.5, y: -1)
                    }

                    handleView()
                        .offset(x: xPosition(for: clipStart, in: width, total: totalFrames) - 6)
                        .gesture(dragGesture(for: .start, width: width, total: totalFrames))

                    handleView()
                        .offset(x: xPosition(for: clipEnd, in: width, total: totalFrames) - 6)
                        .gesture(dragGesture(for: .end, width: width, total: totalFrames))

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                        .offset(x: xPosition(for: playhead, in: width, total: totalFrames) - 1)
                        .gesture(dragGesture(for: .playhead, width: width, total: totalFrames))
                }
                .frame(height: 24)
            }
            .frame(height: 24)
        }
    }

    private func xPosition(for index: Int, in width: CGFloat, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(index) / CGFloat(total) * width
    }

    private func indexForPosition(_ x: CGFloat, in width: CGFloat, total: Int) -> Int {
        guard width > 0, total > 0 else { return 0 }
        let ratio = max(0, min(1, x / width))
        let raw = Int(round(ratio * CGFloat(total)))
        // `total` is padded to 1 even for a single frame so the ratio math
        // above never divides by zero, but that padding makes it one larger
        // than the last real index. Without this clamp, a one-frame buffer
        // hands clipEnd an index outside frames.indices, and selectedFrames
        // wedges Copy to Clipboard disabled for the rest of the session.
        return min(raw, max(frameCount - 1, 0))
    }

    private func handleView() -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: 12, height: 16)
            .shadow(radius: 2)
    }

    private func dragGesture(for handle: DragHandle, width: CGFloat, total: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let index = indexForPosition(value.location.x, in: width, total: total)
                switch handle {
                case .start:
                    clipStart = min(index, clipEnd)
                case .end:
                    clipEnd = max(index, clipStart)
                case .playhead:
                    playhead = max(clipStart, min(clipEnd, index))
                }
            }
    }
}
