import Foundation

public struct HotKeyStore {
    public static let defaultsKey = "CaptureHotKey"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Falls back to the default on absent, undecodable or invalid data: a corrupt
    /// blob should leave a working hotkey, not no hotkey. Validating here rather
    /// than at the registration site keeps a foreign `defaults write` of a bare
    /// key from reaching RegisterEventHotKey through any caller.
    public func load() -> HotKeyConfig {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let config = try? JSONDecoder().decode(HotKeyConfig.self, from: data),
              HotKeyValidator.validate(config) == .valid
        else { return .default }
        return config
    }

    public func save(_ config: HotKeyConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
