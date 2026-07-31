import AppKit
import Observation
import ServiceManagement
import FramegenticKit

@MainActor
@Observable
final class SettingsModel {
    private static let autoSendKey = "AutoSendAfterPaste"
    private static let deliveryTargetKey = "DeliveryTargetID"
    private static let bufferEnabledKey = "BufferEnabled"
    private static let bufferWindowKey = "BufferWindowSeconds"
    private static let frameIntervalKey = "FrameIntervalSeconds"
    private static let autoDeleteTTLKey = "AutoDeleteTTLSeconds"

    private let store: HotKeyStore
    private let hotKey: HotKeyManager

    private(set) var hotKeyConfig: HotKeyConfig
    private(set) var rewindHotKeyConfig: HotKeyConfig
    private(set) var hotKeyRegistered = false
    private(set) var rewindHotKeyRegistered = false
    private(set) var isRecording = false
    private(set) var shortcutError: String?
    private(set) var rewindShortcutError: String?
    private(set) var startAtLogin = false

    var autoSend: Bool {
        didSet { UserDefaults.standard.set(autoSend, forKey: Self.autoSendKey) }
    }

    var deliveryTarget: DeliveryTarget {
        didSet { UserDefaults.standard.set(deliveryTarget.id, forKey: Self.deliveryTargetKey) }
    }

    /// Off by default: an always-on screen recorder is not something to opt a
    /// user out of. Snap works without it; enabling Rewind is what starts it.
    var bufferEnabled: Bool {
        didSet {
            UserDefaults.standard.set(bufferEnabled, forKey: Self.bufferEnabledKey)
            onBufferEnabledChange?(bufferEnabled)
        }
    }

    var bufferWindowSeconds: Int {
        didSet { UserDefaults.standard.set(bufferWindowSeconds, forKey: Self.bufferWindowKey) }
    }

    var frameIntervalSeconds: Double {
        didSet { UserDefaults.standard.set(frameIntervalSeconds, forKey: Self.frameIntervalKey) }
    }

    var autoDeleteTTLSeconds: Int {
        didSet { UserDefaults.standard.set(autoDeleteTTLSeconds, forKey: Self.autoDeleteTTLKey) }
    }

    var bufferCapacity: Int {
        max(1, Int(Double(bufferWindowSeconds) / max(frameIntervalSeconds, 0.1)))
    }

    var onRecordingStateChange: ((Bool) -> Void)?
    var onBufferEnabledChange: ((Bool) -> Void)?

    init(store: HotKeyStore, hotKey: HotKeyManager) {
        self.store = store
        self.hotKey = hotKey
        self.hotKeyConfig = store.load(.capture)
        self.rewindHotKeyConfig = store.load(.rewind)
        self.autoSend = UserDefaults.standard.bool(forKey: Self.autoSendKey)

        let storedID = UserDefaults.standard.string(forKey: Self.deliveryTargetKey)
        self.deliveryTarget = storedID.flatMap(TargetRegistry.target(id:)) ?? TargetRegistry.defaultTarget

        // Values match FrameSnap's AppSettings.swift registered defaults (120s window,
        // 10s interval, 300s TTL). bufferEnabled has no such fallback on purpose: an
        // unset key must read false, not whatever true/false FrameSnap shipped with.
        let storedBufferWindow = UserDefaults.standard.object(forKey: Self.bufferWindowKey) as? Int
        self.bufferWindowSeconds = storedBufferWindow ?? 120

        let storedFrameInterval = UserDefaults.standard.object(forKey: Self.frameIntervalKey) as? Double
        self.frameIntervalSeconds = storedFrameInterval ?? 10.0

        let storedAutoDeleteTTL = UserDefaults.standard.object(forKey: Self.autoDeleteTTLKey) as? Int
        self.autoDeleteTTLSeconds = storedAutoDeleteTTL ?? 300

        self.bufferEnabled = UserDefaults.standard.bool(forKey: Self.bufferEnabledKey)
    }

    var canResetToDefault: Bool { hotKeyConfig != .default }
    var canResetRewindToDefault: Bool { rewindHotKeyConfig != .rewindDefault }

    func registerStoredHotKeys() {
        hotKeyRegistered = hotKey.register(hotKeyConfig, for: .capture)
        rewindHotKeyRegistered = hotKey.register(rewindHotKeyConfig, for: .rewind)
        refreshStartAtLogin()
    }

    private func config(for shortcut: HotKeyStore.Shortcut) -> HotKeyConfig {
        switch shortcut {
        case .capture: return hotKeyConfig
        case .rewind: return rewindHotKeyConfig
        }
    }

    private func setConfig(_ config: HotKeyConfig, for shortcut: HotKeyStore.Shortcut) {
        switch shortcut {
        case .capture: hotKeyConfig = config
        case .rewind: rewindHotKeyConfig = config
        }
    }

    private func setRegistered(_ registered: Bool, for shortcut: HotKeyStore.Shortcut) {
        switch shortcut {
        case .capture: hotKeyRegistered = registered
        case .rewind: rewindHotKeyRegistered = registered
        }
    }

    private func setError(_ message: String?, for shortcut: HotKeyStore.Shortcut) {
        switch shortcut {
        case .capture: shortcutError = message
        case .rewind: rewindShortcutError = message
        }
    }

    private func displayName(for shortcut: HotKeyStore.Shortcut) -> String {
        switch shortcut {
        case .capture: return "Snap"
        case .rewind: return "Rewind"
        }
    }

    /// Validate, reject a collision with the app's *other* shortcut, register,
    /// then persist — in that order, so a shortcut that collides or that Carbon
    /// refuses is never written to the store. The collision check lives here
    /// rather than in HotKeyValidator because this is the only place that knows
    /// both of the app's current bindings at once.
    @discardableResult
    func apply(_ candidate: HotKeyConfig, for shortcut: HotKeyStore.Shortcut) -> Bool {
        switch HotKeyValidator.validate(candidate) {
        case .rejected(.missingRequiredModifier):
            setError("Add ⌘, ⌃ or ⌥ — without one it would fire while you type.", for: shortcut)
            return false
        case .rejected(.reserved(let owner)):
            setError("\(candidate.displayString) belongs to \(owner).", for: shortcut)
            return false
        case .valid:
            break
        }

        let other: HotKeyStore.Shortcut = shortcut == .capture ? .rewind : .capture
        guard candidate != config(for: other) else {
            setError("\(candidate.displayString) is already \(displayName(for: other))'s shortcut.", for: shortcut)
            return false
        }

        guard hotKey.register(candidate, for: shortcut) else {
            setRegistered(hotKey.register(config(for: shortcut), for: shortcut), for: shortcut)
            setError("\(candidate.displayString) is already taken by another app.", for: shortcut)
            return false
        }

        setConfig(candidate, for: shortcut)
        store.save(candidate, for: shortcut)
        setRegistered(true, for: shortcut)
        setError(nil, for: shortcut)
        return true
    }

    func resetToDefault() {
        apply(.default, for: .capture)
    }

    func resetRewindToDefault() {
        apply(.rewindDefault, for: .rewind)
    }

    /// Carbon consumes a registered combo before AppKit dispatch, so recording
    /// either shortcut suspends both — leaving the other live while recording
    /// would let its combo fire instead of being captured by the recorder.
    func beginRecording() {
        isRecording = true
        shortcutError = nil
        rewindShortcutError = nil
        hotKey.unregister()
        onRecordingStateChange?(true)
    }

    func endRecording() {
        isRecording = false
        hotKeyRegistered = hotKey.register(hotKeyConfig, for: .capture)
        rewindHotKeyRegistered = hotKey.register(rewindHotKeyConfig, for: .rewind)
        onRecordingStateChange?(false)
    }

    /// The window is reused across openings, so a rejection from an earlier session
    /// would otherwise still sit in red under a shortcut that works. Safe here and
    /// not on close: apply() runs while the window is already open, so the user has
    /// seen nothing yet at this point.
    func windowWillShow() {
        shortcutError = nil
        rewindShortcutError = nil
        refreshStartAtLogin()
    }

    func refreshStartAtLogin() {
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStartAtLogin()
    }
}
