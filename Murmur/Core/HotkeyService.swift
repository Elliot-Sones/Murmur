import AppKit
import CoreGraphics

/// Owns the CGEventTap that watches the dictation key system-wide.
/// The tap source lives on the main run loop, so callbacks arrive on the main thread.
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var machine = HotkeyStateMachine()
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private var tickTimer: Timer?

    /// Creates the tap, retrying until Input Monitoring permission exists.
    func ensureRunning() {
        guard tap == nil else { return }
        if createTap() {
            retryTimer?.invalidate()
            retryTimer = nil
            return
        }
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in HotkeyService.shared.ensureRunning() }
        }
    }

    private func createTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            // The tap runs on the main run loop; hop is safe to assume.
            MainActor.assumeIsolated {
                HotkeyService.shared.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }
        tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let classified = HotkeyEventClassifier.classify(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            choice: SettingsStore.shared.hotkey
        ) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let actions: [HotkeyStateMachine.Action]
        switch classified {
        case .hotkeyDown:
            actions = machine.handle(.hotkeyDown(now))
        case .hotkeyUp:
            actions = machine.handle(.hotkeyUp(now))
            scheduleTick()
        case .escape:
            guard machine.isCapturing else { return }
            actions = machine.handle(.escapeDown)
        }
        dispatch(actions)
    }

    /// A short tap parks the machine in pendingDecision; the tick resolves it
    /// (discard) when no second tap arrives inside the double-tap window.
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
            Task { @MainActor in
                let service = HotkeyService.shared
                let actions = service.machine.handle(.tick(ProcessInfo.processInfo.systemUptime))
                service.dispatch(actions)
            }
        }
    }

    private func dispatch(_ actions: [HotkeyStateMachine.Action]) {
        for action in actions {
            switch action {
            case .startRecording: DictationController.shared.beginDictation()
            case .finishRecording: DictationController.shared.finishDictation()
            case .cancelRecording: DictationController.shared.cancelDictation()
            }
        }
    }
}
