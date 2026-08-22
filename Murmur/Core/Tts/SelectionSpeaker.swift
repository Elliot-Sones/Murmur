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
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in SelectionSpeaker.shared.poll() }
        }
        log.notice("speak-on-highlight on")
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        TtsService.shared.stop()
        log.notice("speak-on-highlight off")
    }

    private func poll() {
        guard enabled else { return }
        // Leave dictation alone, and ignore selections inside Murmur itself.
        guard case .idle = DictationController.shared.state else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost != Bundle.main.bundleIdentifier else { return }

        let selection = SelectionCapturer.axSelectedText()
        guard let text = logic.observe(selection) else { return }
        log.notice("speaking selection (\(text.count, privacy: .public) chars)")
        Task {
            if let failure = await TtsService.shared.speakLatest(text) {
                DictationController.shared.surfaceNotice(failure)
            }
        }
    }
}
