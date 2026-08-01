import SwiftUI

struct ToastView: View {
    let frameCount: Int
    let ttlMinutes: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.blue)
            Text("\(frameCount) frames copied · deletes in \(ttlMinutes) min")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}
