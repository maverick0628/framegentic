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
    private(set) var hotKeyRegistered = false
    private(set) var isRecording = false
    private(set) var shortcutError: String?
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
        self.hotKeyConfig = store.load()
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

    func registerStoredHotKey() {
        hotKeyRegistered = hotKey.register(hotKeyConfig)
        refreshStartAtLogin()
    }

    /// Validate, register, then persist — in that order, so a shortcut that
    /// Carbon refuses is never written to the store.
    @discardableResult
    func apply(_ candidate: HotKeyConfig) -> Bool {
        switch HotKeyValidator.validate(candidate) {
        case .rejected(.missingRequiredModifier):
            shortcutError = "Add ⌘, ⌃ or ⌥ — without one it would fire while you type."
            return false
        case .rejected(.reserved(let owner)):
            shortcutError = "\(candidate.displayString) belongs to \(owner)."
            return false
        case .valid:
            break
        }

        guard hotKey.register(candidate) else {
            hotKeyRegistered = hotKey.register(hotKeyConfig)
            shortcutError = "\(candidate.displayString) is already taken by another app."
            return false
        }

        hotKeyConfig = candidate
        store.save(candidate)
        hotKeyRegistered = true
        shortcutError = nil
        return true
    }

    func resetToDefault() {
        apply(.default)
    }

    /// Carbon consumes the registered combo before AppKit dispatch, so the
    /// hotkey must be suspended or the current shortcut can never be re-recorded.
    func beginRecording() {
        isRecording = true
        shortcutError = nil
        hotKey.unregister()
        onRecordingStateChange?(true)
    }

    func endRecording() {
        isRecording = false
        hotKeyRegistered = hotKey.register(hotKeyConfig)
        onRecordingStateChange?(false)
    }

    /// The window is reused across openings, so a rejection from an earlier session
    /// would otherwise still sit in red under a shortcut that works. Safe here and
    /// not on close: apply() runs while the window is already open, so the user has
    /// seen nothing yet at this point.
    func windowWillShow() {
        shortcutError = nil
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
