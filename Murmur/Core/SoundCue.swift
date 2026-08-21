import AppKit

/// Subtle system-sound feedback for dictation state changes.
@MainActor
enum SoundCue {
    static func recordingStarted() {
        play("Pop")
    }

    static func inserted() {
        play("Tink")
    }

    private static func play(_ name: String) {
        guard SettingsStore.shared.soundCuesEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
