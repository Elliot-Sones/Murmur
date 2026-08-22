import AppKit
import Observation
import os

/// Speak-on-highlight mode: while enabled, polls the focused app's selected
/// text through Accessibility and reads stable selections aloud with the
/// configured voice. Toggled from the pill button at the bottom of the screen.
@MainActor
@Observable
final class SelectionSpeaker {
    static let shared = SelectionSpeaker()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "speakSelection")
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var logic = SelectionWatcherLogic()
    /// Last raw AX value, for change-only diagnostics logging.
    @ObservationIgnored private var lastSeen: String??

    var enabled: Bool = SettingsStore.shared.speakSelectionEnabled {
        didSet {
            SettingsStore.shared.speakSelectionEnabled = enabled
            enabled ? start() : stop()
        }
    }

    /// Re-arms polling from the persisted setting at launch.
    func syncWithSettings() {
        if enabled { start() }
    }

    private func start() {
        guard timer == nil else { return }
        logic = SelectionWatcherLogic()
        lastSeen = nil
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in SelectionSpeaker.shared.poll() }
        }
        log.notice("speak-on-highlight on, polling")
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        ReaderController.shared.stop()
        log.notice("speak-on-highlight off")
    }

    /// True while a hotkey capture is in flight. Concurrent captures race
    /// on the shared pasteboard and each other's snapshot restores.
    @ObservationIgnored private var capturing = false

    /// Option+Esc: speak whatever is selected right now, in any app.
    /// Uses the synthetic Cmd+C fallback when AX can't see the selection
    /// (Warp, some browsers), so it works where auto-speak can't. Runs
    /// regardless of the pill toggle; the keypress itself is the consent.
    func speakCurrentSelection() {
        guard !capturing else { return }
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            let viaAX = SelectionCapturer.axSelectedText()
            let text = (await SelectionCapturer.capture())?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log.notice("hotkey speak: ax \(viaAX?.count ?? -1, privacy: .public) chars, final \(text.count, privacy: .public) chars")
            guard !text.isEmpty else {
                DictationController.shared.surfaceNotice("No selected text to speak.")
                return
            }
            let capped = String(text.prefix(SelectionWatcherLogic.maxCharacters))
            _ = logic.settle(capped)
            log.notice("hotkey speak (\(capped.count, privacy: .public) chars)")
            ReaderController.shared.start(capped)
        }
    }

    /// Mouse released after a drag: check once, ~no delay. The release is
    /// the settle signal, so this speaks a beat faster than the poll and
    /// catches selections the 400ms cadence straddles.
    func mouseUpNudge() {
        guard enabled else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard let selection = readSelection() else { return }
            if let text = logic.settle(selection) {
                speak(text)
            }
        }
    }

    private func poll() {
        guard enabled else { return }
        guard let selection = readSelection() else { return }
        if let text = logic.observe(selection) {
            speak(text)
        }
    }

    /// nil means "conditions wrong, skip this cycle" as opposed to "no selection".
    private func readSelection() -> String?? {
        // Leave dictation alone, and ignore selections inside Murmur itself.
        guard case .idle = DictationController.shared.state else { return nil }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost != Bundle.main.bundleIdentifier else { return nil }

        SelectionCapturer.enableAccessibilityOfFrontmostAppIfNeeded()
        let selection = SelectionCapturer.axSelectedText()
        if lastSeen != .some(selection) {
            lastSeen = .some(selection)
            let length = selection?.count ?? -1
            log.notice("ax selection \(length, privacy: .public) chars in \(frontmost ?? "?", privacy: .public) [\(SelectionCapturer.axTrace(), privacy: .public)]")
        }
        return .some(selection)
    }

    private func speak(_ text: String) {
        log.notice("reading selection (\(text.count, privacy: .public) chars)")
        ReaderController.shared.start(text)
    }
}
