import AppKit
import SwiftUI
import FramegenticKit

/// Reads CaptureService's buffer once, when the popover opens, rather than
/// live. The buffer keeps recording underneath an open popover, so a live
/// read would shift clipStart/clipEnd/playhead out from under a drag already
/// in progress; re-querying CaptureService on every drag event would also
/// mean an O(n) copy of the buffer per pixel of mouse movement. A snapshot
/// taken once gives a stable range to scrub for as long as the popover stays
/// open — the same thing FrameSnap's own CaptureViewModel.refreshFrames() did,
/// carried forward rather than reinvented.
@MainActor
@Observable
final class RewindViewModel {
    enum State {
        case disabled
        case permissionDenied
        case empty
        case ready
    }

    private let captureService: CaptureService
    private let delivery = DeliveryService()
    let settings: SettingsModel

    private(set) var frames: [CapturedFrame] = []
    var playheadIndex = 0
    var clipStart = 0
    var clipEnd = 0
    private(set) var showToast = false
    private(set) var copiedCount = 0
    private(set) var isDelivering = false
    private(set) var deliveryError: String?
    private var deliveryTask: Task<Void, Never>?

    /// Set by RewindPopoverController. confirmSelection() calls it once the
    /// toast has had time to be read, so the popover closes itself without
    /// this type needing to know anything about NSPopover.
    var onRequestClose: (() -> Void)?

    init(captureService: CaptureService, settings: SettingsModel) {
        self.captureService = captureService
        self.settings = settings
    }

    var state: State {
        guard settings.bufferEnabled else { return .disabled }
        guard frames.isEmpty else { return .ready }
        // A denied/revoked Screen Recording permission and a buffer that
        // simply hasn't filled in yet are both "enabled, zero frames" at the
        // instant the popover opens — indistinguishable without asking the OS
        // directly. This is the same preflight check AppDelegate's menu uses
        // for the identical question, called live rather than cached on
        // CaptureService, so it can never answer stale.
        return CGPreflightScreenCaptureAccess() ? .empty : .permissionDenied
    }

    func refreshFrames() {
        frames = captureService.currentFrames()
        clipStart = 0
        clipEnd = max(frames.count - 1, 0)
        playheadIndex = clipEnd
        deliveryError = nil
    }

    /// Called when the popover closes, so a decoded frame buffer doesn't sit
    /// in memory between Rewind sessions. Also cancels a delivery still in
    /// flight — the paste it already started can't be undone, this only stops
    /// a stale toast or close from firing once the popover is gone.
    func releaseFrames() {
        frames = []
        deliveryTask?.cancel()
    }

    var currentFrame: CapturedFrame? {
        guard frames.indices.contains(playheadIndex) else { return nil }
        return frames[playheadIndex]
    }

    var selectedFrames: [CapturedFrame] {
        guard clipStart <= clipEnd,
              frames.indices.contains(clipStart),
              frames.indices.contains(clipEnd) else { return [] }
        return Array(frames[clipStart...clipEnd])
    }

    var selectedDurationText: String {
        guard let first = selectedFrames.first, let last = selectedFrames.last else { return "0s" }
        let seconds = Int(last.timestamp.timeIntervalSince(first.timestamp))
        let minutes = seconds / 60
        let remaining = seconds % 60
        return minutes > 0 ? String(format: "%dm %02ds", minutes, remaining) : "\(seconds)s"
    }

    /// Delivers the trimmed range through DeliveryService, to whatever target
    /// Settings has configured — the same activation-and-paste sequence a
    /// snap uses. `deliveryTask` lets releaseFrames() stop a stale success
    /// from toasting or closing a popover the user already dismissed.
    func confirmSelection() {
        guard !isDelivering else { return }
        let selected = selectedFrames
        guard !selected.isEmpty else { return }
        deliveryError = nil
        isDelivering = true
        deliveryTask = Task {
            defer { isDelivering = false }
            do {
                let count = try await delivery.deliverClip(
                    selected,
                    to: settings.deliveryTarget,
                    autoSend: settings.autoSend,
                    ttl: TimeInterval(settings.autoDeleteTTLSeconds)
                )
                guard !Task.isCancelled else { return }
                guard count > 0 else {
                    deliveryError = "Couldn't copy those frames. Try again."
                    return
                }
                copiedCount = count
                showToast = true
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                showToast = false
                onRequestClose?()
            } catch {
                guard !Task.isCancelled else { return }
                Log.paste.error("Rewind delivery failed: \(error.localizedDescription, privacy: .public)")
                deliveryError = error.localizedDescription
            }
        }
    }
}

struct RewindPopoverView: View {
    @Bindable var model: RewindViewModel
    let onOpenSettings: () -> Void
    let onOpenScreenRecordingSettings: () -> Void
    let onEscape: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .disabled:
                RewindEmptyStateView(
                    systemImage: "record.circle",
                    title: "Rewind is off",
                    message: "It keeps a rolling recording of your screen in memory, so you can scrub back and grab a moment after it happens. Turn it on in Settings.",
                    actionTitle: "Open Settings",
                    action: onOpenSettings
                )
            case .permissionDenied:
                // Message text and button wording both come from the same
                // established copy this app already uses for this exact
                // condition (CaptureError's alert text, AppDelegate's menu
                // item) rather than inventing a third phrasing of the same fact.
                RewindEmptyStateView(
                    systemImage: "video.slash",
                    title: "Screen Recording is off",
                    message: CaptureError.screenRecordingDenied.localizedDescription,
                    actionTitle: "Grant Screen Recording…",
                    action: onOpenScreenRecordingSettings
                )
            case .empty:
                RewindEmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "Nothing captured yet",
                    message: "Rewind just turned on. Give it a few seconds to start filling in, then reopen.",
                    actionTitle: nil,
                    action: nil
                )
                footer
            case .ready:
                FramePreview(frame: model.currentFrame, frameCount: model.frames.count)
                TimelineScrubber(
                    frameCount: model.frames.count,
                    playhead: $model.playheadIndex,
                    clipStart: $model.clipStart,
                    clipEnd: $model.clipEnd,
                    selectedDuration: model.selectedDurationText,
                    oldestTimeAgo: model.frames.first?.formattedTimeAgo() ?? "0s"
                )
                if let deliveryError = model.deliveryError {
                    Text(deliveryError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                confirmButton
                footer
            }

            if model.showToast {
                ToastView(frameCount: model.copiedCount, ttlMinutes: model.settings.autoDeleteTTLSeconds / 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.2), value: model.showToast)
        .onExitCommand(perform: onEscape)
    }

    private var confirmButton: some View {
        Button(action: { model.confirmSelection() }) {
            Text(model.isDelivering ? "Copying…" : "Copy to Clipboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.selectedFrames.isEmpty || model.isDelivering)
    }

    private var footer: some View {
        Button(action: onOpenSettings) {
            Text("Buffer: \(model.settings.bufferWindowSeconds / 60) min · 1 frame / \(Int(model.settings.frameIntervalSeconds))s · Auto-delete: \(model.settings.autoDeleteTTLSeconds / 60) min")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }
}

private struct RewindEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

/// Owns the NSPopover and the focus dance an LSUIElement app needs to make it
/// key. SettingsWindowController solves the identical problem for the
/// settings NSWindow; this follows the same shape for a popover instead.
@MainActor
final class RewindPopoverController: NSObject, NSPopoverDelegate {
    private let viewModel: RewindViewModel
    private let popover: NSPopover

    init(
        viewModel: RewindViewModel,
        onOpenSettings: @escaping () -> Void,
        onOpenScreenRecordingSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        let popover = NSPopover()
        popover.behavior = .transient
        self.popover = popover
        super.init()

        viewModel.onRequestClose = { [weak self] in self?.close() }
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RewindPopoverView(
                model: viewModel,
                onOpenSettings: onOpenSettings,
                onOpenScreenRecordingSettings: onOpenScreenRecordingSettings,
                onEscape: { [weak self] in self?.close() }
            )
        )
    }

    /// The hotkey both opens and closes Rewind, so a second press while it's
    /// already open dismisses it rather than doing nothing.
    func toggle(relativeTo statusItem: NSStatusItem) {
        if popover.isShown {
            close()
        } else {
            show(relativeTo: statusItem)
        }
    }

    private func show(relativeTo statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }
        viewModel.refreshFrames()
        // LSUIElement apps do not get focus from showing a popover alone, and
        // without focus neither Escape nor the scrubber's drag gestures would
        // arrive — the same fix SettingsWindowController uses for its window.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func close() {
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.releaseFrames()
    }
}
