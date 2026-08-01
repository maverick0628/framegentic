import AppKit
import SwiftUI
import FramegenticKit

struct FramePreview: View {
    let frame: CapturedFrame?
    let frameCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)

            if let frame, let nsImage = nsImage(from: frame.image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(6)
                    .padding(2)
            } else {
                Text("No frames captured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                HStack {
                    Text("\(frameCount) frames")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    if let frame {
                        Text(frame.formattedTimeAgo())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(6)
        }
        .frame(height: 160)
    }

    private func nsImage(from cgImage: CGImage) -> NSImage? {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
