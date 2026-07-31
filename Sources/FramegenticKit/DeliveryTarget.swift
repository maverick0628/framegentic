import Foundation

/// Where a capture goes after it reaches the clipboard.
public struct DeliveryTarget: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let displayName: String
    /// nil for clipboard-only, which activates nothing.
    public let bundleID: String?
    /// Whether delivery activates the app and simulates ⌘V. Requires Accessibility.
    public let autoPaste: Bool

    public init(id: String, displayName: String, bundleID: String?, autoPaste: Bool) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.autoPaste = autoPaste
    }

    public static let clipboardOnly = DeliveryTarget(
        id: "clipboard",
        displayName: "Clipboard only",
        bundleID: nil,
        autoPaste: false
    )
}

public enum TargetRegistry {
    /// Clipboard-only is first and default: the auto-paste path needs Accessibility,
    /// simulates keystrokes and steals focus, so it is opted into rather than out of.
    public static let all: [DeliveryTarget] = [
        .clipboardOnly,
        DeliveryTarget(
            id: "claude",
            displayName: "Claude",
            bundleID: "com.anthropic.claudefordesktop",
            autoPaste: true
        )
    ]

    public static var defaultTarget: DeliveryTarget { .clipboardOnly }

    public static func target(id: String) -> DeliveryTarget? {
        all.first { $0.id == id }
    }
}
