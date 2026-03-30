import Cocoa
import CoreGraphics

/// Monitors Right Control key press/release via CGEvent tap.
/// Distinguishes left (keycode 59) from right (keycode 62) Control.
/// Suppresses Right Control events to prevent interference with other apps.
final class KeyMonitor {
    var onRightControlDown: (() -> Void)?
    var onRightControlUp: (() -> Void)?
    var onShortTap: (() -> Void)? // tap < 200ms, detected on release
    var onDoubleTap: (() -> Void)? // two short taps within 400ms

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    private var isRightControlDown = false
    private var rightControlDownTime: Date?
    private var lastShortTapTime: Date?
    private var pendingDownWorkItem: DispatchWorkItem?

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        tapThread = Thread { [weak self] in
            self?.setupEventTap()
            CFRunLoopRun()
        }
        tapThread?.name = "com.cifer.VoiceInk.KeyMonitor"
        tapThread?.start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
        tapThread?.cancel()
        tapThread = nil
    }

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // Use a pointer to self as userInfo
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // active tap so we can suppress events
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(event)
            },
            userInfo: selfPtr
        ) else {
            DispatchQueue.main.async {
                Permissions.requestAccessibility()
            }
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Only handle Right Control (keycode 62). Let everything else pass through.
        guard keycode == Constants.rightControlKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        if flags.contains(.maskControl) && !isRightControlDown {
            // Right Control pressed — delay onRightControlDown to distinguish
            // short tap / double tap from long press
            isRightControlDown = true
            rightControlDownTime = Date()

            let workItem = DispatchWorkItem { [weak self] in
                self?.pendingDownWorkItem = nil
                self?.onRightControlDown?()
            }
            pendingDownWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.shortPressDuration, execute: workItem)

        } else if !flags.contains(.maskControl) && isRightControlDown {
            // Right Control released
            isRightControlDown = false
            let duration = rightControlDownTime.map { Date().timeIntervalSince($0) } ?? 1.0

            if duration < Constants.shortPressDuration {
                // Cancel the pending onRightControlDown — this was a short tap, not a hold
                pendingDownWorkItem?.cancel()
                pendingDownWorkItem = nil

                // Check for double tap
                let now = Date()
                if let lastTap = lastShortTapTime, now.timeIntervalSince(lastTap) < 0.4 {
                    lastShortTapTime = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                } else {
                    lastShortTapTime = now
                    // Delay single tap to wait for potential second tap
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        guard let self, let lastTap = self.lastShortTapTime, lastTap == now else { return }
                        self.lastShortTapTime = nil
                        self.onShortTap?()
                    }
                }
            } else {
                // Normal release after hold
                DispatchQueue.main.async { [weak self] in
                    self?.onRightControlUp?()
                }
            }
            rightControlDownTime = nil
        }

        // Suppress Right Control event so it doesn't reach other apps
        return nil
    }
}
