# Murmur

System-wide AI dictation for macOS. All models run on this Mac.

Hold Fn in any app. Speak. Release. Clean text appears at your cursor.

## Requirements

- Apple Silicon Mac, macOS 26+
- Xcode 26
- XcodeGen: `brew install xcodegen`

## Build and run

    make install

This builds the app, copies it to /Applications, and launches it. Grant permissions to the /Applications copy so System Settings can always find it. `make run` launches straight from the build folder (fine for quick iteration after permissions are granted).

## Permissions

Murmur needs three permissions. The onboarding window guides you through them:

1. Microphone: records your voice while you hold the key.
2. Accessibility: pastes text into the focused app.
3. Input Monitoring: detects the Fn key in any app.

Also set System Settings > Keyboard > "Press 🌐 key" to "Do Nothing". This frees the Fn key for Murmur.

If Murmur does not appear in a permission list: click the + button, press Cmd+Shift+G in the file picker, type `/Applications`, and select Murmur.app.

If permissions break after a rebuild, reset them and grant again:

    tccutil reset Accessibility com.elliot.Murmur
    tccutil reset ListenEvent com.elliot.Murmur
    tccutil reset Microphone com.elliot.Murmur

## Status

- M0 (current): menu bar shell, permissions onboarding
- M1: core dictation loop (Parakeet STT, on-device cleanup, paste at cursor)
- M2: dictionary, history, per-app profiles, streaming preview, engine bench
- M3: command mode, context awareness, auto-learn dictionary

See `docs/spec.md` for the full design.
