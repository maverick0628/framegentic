import Foundation
import CoreGraphics

// CGImage is immutable once created and Sendable in the SDK this package targets,
// so this conformance is real rather than @unchecked.
public struct CapturedFrame: Sendable {
    public let image: CGImage
    public let timestamp: Date

    public init(image: CGImage, timestamp: Date = Date()) {
        self.image = image
        self.timestamp = timestamp
    }

    public func timeAgo(relativeTo now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(timestamp)
    }

    public func formattedTimeAgo(relativeTo now: Date = Date()) -> String {
        let seconds = Int(timeAgo(relativeTo: now))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return String(format: "−%dm %02ds", minutes, remainingSeconds)
        }
        return String(format: "−%ds", remainingSeconds)
    }
}
