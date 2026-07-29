import Carbon.HIToolbox

public enum HotKeyRejection: Equatable, Sendable {
    case missingRequiredModifier
    case reserved(owner: String)
}

public enum HotKeyValidation: Equatable, Sendable {
    case valid
    case rejected(HotKeyRejection)
}

public enum HotKeyValidator {
    private struct Reserved {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let owner: String
    }

    private static let cmd = UInt32(cmdKey)
    private static let shift = UInt32(shiftKey)
    private static let opt = UInt32(optionKey)
    private static let ctrl = UInt32(controlKey)

    /// A courtesy in front of RegisterEventHotKey, which reports failure without
    /// a reason. Deliberately does not list ⌘⇧6: it is only taken on Touch Bar
    /// Macs, and it is this app's own default — registration reports it there.
    private static let reserved: [Reserved] = [
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: cmd, owner: "Spotlight"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: opt | cmd, owner: "Finder search"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: ctrl | cmd, owner: "Emoji & Symbols"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: ctrl, owner: "input source switching"),
        Reserved(keyCode: UInt32(kVK_Tab), carbonModifiers: cmd, owner: "the app switcher"),
        Reserved(keyCode: UInt32(kVK_Tab), carbonModifiers: cmd | shift, owner: "the app switcher"),
        Reserved(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: cmd, owner: "Quit"),
        Reserved(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: cmd, owner: "Close Window"),
        Reserved(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: cmd, owner: "Hide"),
        Reserved(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: cmd, owner: "Minimise"),
        Reserved(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_UpArrow), carbonModifiers: ctrl, owner: "Mission Control"),
        Reserved(keyCode: UInt32(kVK_DownArrow), carbonModifiers: ctrl, owner: "Mission Control"),
        Reserved(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: ctrl, owner: "Spaces"),
        Reserved(keyCode: UInt32(kVK_RightArrow), carbonModifiers: ctrl, owner: "Spaces"),
        Reserved(keyCode: UInt32(kVK_Escape), carbonModifiers: opt | cmd, owner: "Force Quit"),
        Reserved(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: ctrl | cmd, owner: "Lock Screen")
    ]

    public static func validate(_ config: HotKeyConfig) -> HotKeyValidation {
        let required = cmd | ctrl | opt
        guard config.carbonModifiers & required != 0 else {
            return .rejected(.missingRequiredModifier)
        }
        if let hit = reserved.first(where: {
            $0.keyCode == config.keyCode && $0.carbonModifiers == config.carbonModifiers
        }) {
            return .rejected(.reserved(owner: hit.owner))
        }
        return .valid
    }
}
