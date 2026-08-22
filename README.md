# Murmur

System-wide AI dictation and text-to-speech for macOS. All models run on this Mac.

Tap the dictation key (default Ctrl+I) in any app. Speak. Tap again. Clean text appears at your cursor. Highlight text anywhere and Murmur reads it aloud.

## Keys

- Tap Ctrl+I: start dictating; tap again to insert. Holding works as push-to-talk. Esc discards.
- Ctrl+O (hold, with text selected): speak an instruction; the selection is rewritten in place.
- Esc: stop an active reading.
- Ctrl+Esc: toggle speak-on-highlight mode (same as clicking the bottom pill).
- Option+Esc: read the current selection (or clipboard where selections are invisible, like Warp) aloud.

Keys are configurable in Settings. The bottom-center pill is the app's one widget: toggle, level meter, status, and the reader bar with play/pause, sentence skips, and 0.75x-3x speed.

## Requirements

- Apple Silicon Mac, macOS 26+
- Xcode 26
- XcodeGen: `brew install xcodegen`

## Build and run

    make install

This builds the app, copies it to /Applications, and launches it. Grant permissions to the /Applications copy so System Settings can always find it. `make run` launches straight from the build folder (fine for quick iteration after permissions are granted).

## Voices

Dictation transcribes with Parakeet (FluidAudio, Neural Engine) and cleans up with the Apple on-device model or Ollama. Read-aloud uses Kokoro: the built-in Heart voice needs nothing, and the full 28-voice list runs behind a local server:

    make tts-serve

The server is also installed as a login item (`com.elliot.murmur-tts`), so it normally just runs. See `tts-server/README.md`.

## Permissions

Murmur needs three permissions. The onboarding window guides you through them:

1. Microphone: records your voice while dictating.
2. Accessibility: pastes text and reads selections.
3. Input Monitoring: detects the hotkeys in any app.

If Murmur does not appear in a permission list: click the + button, press Cmd+Shift+G in the file picker, type `/Applications`, and select Murmur.app.

If permissions break after a rebuild, reset them and grant again:

    tccutil reset Accessibility com.elliot.Murmur
    tccutil reset ListenEvent com.elliot.Murmur
    tccutil reset Microphone com.elliot.Murmur

## Status

- M0-M3 (done): menu bar shell, permissions onboarding, core dictation loop (Parakeet STT, on-device cleanup, paste at cursor), personal dictionary, history with per-stage timings, per-app profiles, live preview, Ollama cleanup backend, sound cues, launch at login, command mode, destination-aware cleanup, learned dictionary suggestions, `make bench` accuracy harness (see `bench/README.md`)
- Post-M3 (done): speak-on-highlight with a Speechify-style reader bar, clipboard reading for AX-blind apps, tap-toggle dictation keys, single-widget UI

`docs/spec.md` holds the original design; where they differ, the code and this README are current.
