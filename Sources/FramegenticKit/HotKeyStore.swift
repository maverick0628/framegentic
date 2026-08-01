import Foundation

public struct HotKeyStore {
    /// Identifies one of the app's independently-stored shortcuts. A future third
    /// shortcut is one more case here, not a duplicated pair of load/save members.
    public enum Shortcut: String, Sendable, Hashable, CaseIterable {
        case capture = "CaptureHotKey"
        case rewind = "RewindHotKey"

        var fallback: HotKeyConfig {
            switch self {
            case .capture: .default
            case .rewind: .rewindDefault
            }
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Falls back to `shortcut`'s own default on absent, undecodable or invalid
    /// data: a corrupt blob should leave a working hotkey, not no hotkey. Validating
    /// here rather than at the registration site keeps a foreign `defaults write` of
    /// a bare key from reaching RegisterEventHotKey through any caller. Each
    /// shortcut is keyed and validated independently, so a corrupt blob under one
    /// can never take the other down with it.
    public func load(_ shortcut: Shortcut) -> HotKeyConfig {
        guard let data = defaults.data(forKey: shortcut.rawValue),
              let config = try? JSONDecoder().decode(HotKeyConfig.self, from: data),
              HotKeyValidator.validate(config) == .valid
        else { return shortcut.fallback }
        return config
    }

    public func save(_ config: HotKeyConfig, for shortcut: Shortcut) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: shortcut.rawValue)
    }
}
