import AppKit
import CoreGraphics
import os

/// Owns the CGEventTap that watches the dictation key system-wide.
/// The tap is active (not listen-only) so combo hotkeys like Option+P can be
/// swallowed instead of typing "π" into the focused app. Lone-modifier hotkeys
/// (Fn, Right Command) are never consumed.
/// The tap source lives on the main run loop, so callbacks arrive on the main thread.
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "hotkey")
    private var machine = HotkeyStateMachine()
    private var commandMachine = HotkeyStateMachine()
    /// Physical state of the Control+Option chord, tracked independently of
    /// the state machine so press and release pair up correctly.
    private var dictationChordDown = false
    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private var tickTimer: Timer?

    /// Creates the tap, retrying until Input Monitoring permission exists.
    func ensureRunning() {
        guard tap == nil else { return }
        if createTap() {
            log.notice("Event tap created")
            retryTimer?.invalidate()
            retryTimer = nil
            return
        }
        log.error("Event tap creation failed, likely missing Input Monitoring; retrying")
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in HotkeyService.shared.ensureRunning() }
        }
    }

    private func createTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            // The tap runs on the main run loop; hop is safe to assume.
            let consumed = MainActor.assumeIsolated {
                HotkeyService.shared.handle(type: type, event: event)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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

    /// Returns true when the event must be swallowed (not delivered to apps).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        let choice = SettingsStore.shared.hotkey
        let commandChoice = SettingsStore.shared.commandHotkey
        let now = ProcessInfo.processInfo.systemUptime

        // Escape cancels whichever machine is currently capturing.
        if type == .keyDown, keyCode == HotkeyEventClassifier.escapeKeyCode {
            if machine.isCapturing {
                dispatch(machine.handle(.escapeDown), mode: .insert)
                return true
            }
            if commandMachine.isCapturing {
                dispatch(commandMachine.handle(.escapeDown), mode: .command)
                return true
            }
            return false
        }

        if let classified = HotkeyEventClassifier.classify(
            type: type, keyCode: keyCode, flags: event.flags,
            isAutorepeat: isAutorepeat, chordActive: dictationChordDown, choice: choice
        ), classified != .escape {
            if choice == .controlOption {
                if classified == .hotkeyDown { dictationChordDown = true }
                if classified == .hotkeyUp { dictationChordDown = false }
            }
            guard !commandMachine.isCapturing else { return false }
            let wasCapturing = machine.isCapturing
            let actions: [HotkeyStateMachine.Action]
            switch classified {
            case .hotkeyDown:
                actions = machine.handle(.hotkeyDown(now))
            case .hotkeyUp:
                actions = machine.handle(.hotkeyUp(now))
                scheduleTick()
            case .escape:
                return false
            }
            if !actions.isEmpty || machine.isCapturing {
                log.info("dictate \(String(describing: classified), privacy: .public) -> \(String(describing: actions), privacy: .public)")
            }
            dispatch(actions, mode: .insert)
            return choice == .controlI && (wasCapturing || machine.isCapturing || !actions.isEmpty)
        }

        if let classified = HotkeyEventClassifier.classifyCommand(
            type: type, keyCode: keyCode, flags: event.flags,
            isAutorepeat: isAutorepeat, choice: commandChoice
        ) {
            guard !machine.isCapturing else { return false }
            let wasCapturing = commandMachine.isCapturing
            let actions: [HotkeyStateMachine.Action]
            switch classified {
            case .hotkeyDown:
                actions = commandMachine.handle(.hotkeyDown(now))
            case .hotkeyUp:
                actions = commandMachine.handle(.hotkeyUp(now))
                scheduleTick()
            case .escape:
                return false
            }
            if !actions.isEmpty || commandMachine.isCapturing {
                log.info("command \(String(describing: classified), privacy: .public) -> \(String(describing: actions), privacy: .public)")
            }
            dispatch(actions, mode: .command)
            return commandChoice == .controlO
                && (wasCapturing || commandMachine.isCapturing || !actions.isEmpty)
        }

        // Swallow combo-key autorepeats and strays while their capture runs
        // so they do not type into the focused app.
        if choice == .controlI, keyCode == HotkeyEventClassifier.iKeyCode, machine.isCapturing {
            return true
        }
        if commandChoice == .controlO, keyCode == HotkeyEventClassifier.oKeyCode,
            commandMachine.isCapturing {
            return true
        }
        return false
    }

    /// A short tap parks a machine in pendingDecision; the tick resolves it
    /// (discard) when no second tap arrives inside the double-tap window.
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
            Task { @MainActor in
                let service = HotkeyService.shared
                let now = ProcessInfo.processInfo.systemUptime
                service.dispatch(service.machine.handle(.tick(now)), mode: .insert)
                service.dispatch(service.commandMachine.handle(.tick(now)), mode: .command)
            }
        }
    }

    private func dispatch(_ actions: [HotkeyStateMachine.Action], mode: DictationController.Mode) {
        for action in actions {
            switch action {
            case .startRecording: DictationController.shared.beginDictation(mode: mode)
            case .finishRecording: DictationController.shared.finishDictation()
            case .cancelRecording: DictationController.shared.cancelDictation()
            }
        }
    }
}
