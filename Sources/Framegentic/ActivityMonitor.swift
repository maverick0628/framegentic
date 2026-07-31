import Foundation
import CoreGraphics

// Ported from FrameSnap unchanged apart from the refcon force-unwrap (this
// project's no-force-unwraps rule). Not an actor: the event tap callback is a
// C function pointer with no Swift concurrency of its own, and every call site
// in this app drives it from CaptureService's MainActor-isolated methods, so
// start()/stop() always run on the main run loop and there is nothing to
// isolate here.
final class ActivityMonitor {
    enum State { case idle, active }

    private var lastActivityTime = Date()
    private let idleThreshold: TimeInterval = 5.0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var currentState: State {
        Date().timeIntervalSince(lastActivityTime) > idleThreshold ? .idle : .active
    }

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.lastActivityTime = Date()
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
