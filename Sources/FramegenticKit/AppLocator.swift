import Foundation

public struct RunningAppInfo: Equatable, Sendable {
    public let bundleID: String?
    public let localizedName: String?

    public init(bundleID: String?, localizedName: String?) {
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

/// How to bring a delivery target to the front. Distinct from `DeliveryTarget`,
/// which is the destination itself rather than the plan for reaching it.
public enum ActivationPlan: Equatable, Sendable {
    case activateRunning
    case launch(URL)
    case notFound
}

public enum AppLocator {
    /// Matches on bundle identifier only. An app is trivially able to claim
    /// another's display name, so the name is never used to decide.
    public static func resolve(bundleID: String,
                               runningApps: [RunningAppInfo],
                               installedAppURL: URL?) -> ActivationPlan {
        if runningApps.contains(where: { $0.bundleID == bundleID }) {
            return .activateRunning
        }
        if let installedAppURL {
            return .launch(installedAppURL)
        }
        return .notFound
    }
}
