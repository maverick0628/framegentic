import Foundation

public struct RunningAppInfo: Equatable, Sendable {
    public let bundleID: String?
    public let localizedName: String?

    public init(bundleID: String?, localizedName: String?) {
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

public enum ClaudeTarget: Equatable, Sendable {
    case activateRunning
    case launch(URL)
    case notFound
}

public enum ClaudeLocator {
    public static let bundleID = "com.anthropic.claudefordesktop"

    public static func resolve(runningApps: [RunningAppInfo],
                               installedAppURL: URL?) -> ClaudeTarget {
        if runningApps.contains(where: { $0.bundleID == bundleID }) {
            return .activateRunning
        }
        if let installedAppURL {
            return .launch(installedAppURL)
        }
        return .notFound
    }
}
