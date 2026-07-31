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
        case empty
        case ready
    }

    private let captureService: CaptureService
    let settings: SettingsModel

    private(set) var frames: [CapturedFrame] = []
    var playheadIndex = 0
    var clipStart = 0
    var clipEnd = 0
    private(set) var showToast = false
    private(set) var copiedCount = 0

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
        return frames.isEmpty ? .empty : .ready
    }

    func refreshFrames() {
        frames = captureService.currentFrames()
        clipStart = 0
        clipEnd = max(frames.count - 1, 0)
        playheadIndex = clipEnd
    }

    /// Called when the popover closes, so a decoded frame buffer doesn't sit
    /// in memory between Rewind sessions.
    func releaseFrames() {
        frames = []
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

    /// Stands in for real delivery until Task 6 wires this through
    /// OptimizationPipeline and DeliveryService. The interaction it drives —
    /// pick a range, confirm, see the count and the deletion deadline, then
    /// the popover closes — is real; only the clipboard write behind it isn't.
    func confirmSelection() {
        let selected = selectedFrames
        guard !selected.isEmpty else { return }
        copiedCount = selected.count
        showToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showToast = false
            onRequestClose?()
        }
    }
}

struct RewindPopoverView: View {
    @Bindable var model: RewindViewModel
    let onOpenSettings: () -> Void
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
            Text("Copy to Clipboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.selectedFrames.isEmpty)
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

    init(viewModel: RewindViewModel, onOpenSettings: @escaping () -> Void) {
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
