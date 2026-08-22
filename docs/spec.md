# Murmur: Local Wispr Flow Replica for macOS

System-wide AI dictation that runs entirely on local models. Hold a key anywhere in macOS, speak, release: speech becomes clean, formatted text in the focused app. No cloud, no subscription.

> Historical design document (2026-08-21). The app has since evolved past it:
> tap-toggle hotkeys, a single bottom widget, and a text-to-speech reader were
> added after M3. The README describes current behavior; this file records the
> original plan and its milestone-era deviations.

Decisions from design review (2026-08-21):
- Scope: full replica, built in phased milestones so core dictation works early.
- Languages: English only. This unlocks Parakeet, the fastest local STT.
- Distribution: personal use on this Mac only. No notarization work.
- Approach: single native Swift/SwiftUI menu bar app (chosen over a Python sidecar and a VoiceInk fork).
- Audio reality: dictation happens at a quiet desk, via AirPods, and sometimes (10-30%) in noisy places. Voice-processed capture ships in M1; bench fixtures cover all three conditions.

Machine: M5 Pro, 64 GB RAM, macOS 26.5.2, Xcode 26 (Swift 6.2), Ollama installed. Apple Intelligence capable, so the FoundationModels framework is available.

## Tech choices (verified 2026-08-21)

| Concern | Choice | Why |
|---|---|---|
| STT | [FluidAudio](https://github.com/FluidInference/FluidAudio) Swift package, Parakeet TDT 0.6B v2 (English) on CoreML/ANE | Apache 2.0. ~110x realtime on ANE. Transducer architecture: silence produces no text, unlike Whisper, which hallucinates during pauses. Native punctuation and caps. Batch (`AsrManager`) and streaming (`SlidingWindowAsrManager`) APIs. Proven by push-to-talk apps (Hex, Parakey). Model auto-downloads on first run (~1 GB). Not the absolute WER leader; see rationale below. |
| Cleanup LLM | Apple FoundationModels (`LanguageModelSession`), on-device 3B | Zero download, private, fast for short text. Availability checked via `SystemLanguageModel.default.availability`. |
| Cleanup fallback / command mode | Ollama HTTP (localhost:11434) behind the same protocol | Already installed. Heavier rewrites and a fallback if Apple Intelligence is off. |
| Hotkey capture | CGEventTap (listen-only, `flagsChanged` + `keyDown`) | Only reliable way to see the Fn key globally. Needs Input Monitoring + Accessibility permissions. |
| Text insertion | Pasteboard write + synthetic Cmd+V + pasteboard restore | What VoiceInk/Hex do. Works in nearly every app. |
| History | SwiftData | Native, zero dependency, fine for personal scale. |
| Project generation | XcodeGen (`project.yml`) + `xcodebuild` CLI | Declarative project file, agent-friendly builds. |
| Reference app (behavior only, no code reuse) | [VoiceInk](https://github.com/beingpax/VoiceInk) (GPL-3.0) | Feature and UX reference for per-app modes, onboarding. |

### STT choice, stress-tested 2026-08-21

- Open ASR Leaderboard accuracy leaders (Granite Speech 4.1 2B: 5.33 WER, Cohere Transcribe 2B: 5.42, Canary-Qwen 2.5B: 5.63) beat Parakeet v2 (~6.05) on benchmark average. None ship a mature CoreML/Swift runtime; they are server-first. RAM is not the blocker, runtime maturity is.
- Whisper large-v3 on M5-class MLX: 12-18x realtime, ~7.4 avg WER (more robust on noisy or accented audio, slightly worse on clean English). Its decoder hallucinates text during silence, a known dictation failure mode; in noise it hallucinates more, not less. A transducer emits nothing during pauses.
- About 1 point of benchmark WER is not perceptible in everyday dictation. The errors that matter (names, jargon) are addressed by the dictionary and cleanup stage.
- Decision: Parakeet v2 primary. Verify empirically in M2 with the engine bench harness. WhisperKit large-v3-turbo (Swift/CoreML, 20-30x realtime) available as an alternate robustness engine behind `TranscriptionService`, switchable globally or per input device. Watch item: Qwen3-ASR MLX (0.6B/1.7B, strong accuracy, Python runtime only today, would need a sidecar).

## Architecture

Single process, protocol-first so every engine is swappable:

```
HotkeyService (CGEventTap)
   └─ DictationController (state machine: idle → recording → transcribing → inserting)
        ├─ AudioRecorder (AVAudioEngine, 16 kHz mono Float32, voice-processed capture)
        ├─ TranscriptionService (protocol) ← FluidAudioTranscriber (Parakeet v2)
        ├─ CleanupService (protocol)      ← FoundationModelsCleanup | OllamaCleanup | RawPassthrough
        ├─ TextInserter (pasteboard + CGEvent Cmd+V, restore after)
        ├─ ContextProvider (frontmost app bundle id + AX window title → AppProfile)
        └─ HistoryStore (SwiftData), DictionaryStore (JSON)
UI: MenuBarExtra (status + toggles) · HUD (non-activating NSPanel: level meter, state, live text later) · Settings window · Onboarding window (permission checklist)
```

State machine rules: min utterance 0.3 s (else discard), max 5 min cap, cancel with Esc while recording. Secure input active (`IsSecureEventInputEnabled()`): refuse to record, show HUD notice.

Cleanup prompt (FoundationModels instructions): fix punctuation and capitalization, remove fillers (um, uh, like), apply self-corrections ("Tuesday, no wait, Wednesday" becomes "Wednesday"), format lists when dictated, prefer dictionary spellings, apply the app profile tone hint. Output text only, no commentary. Raw mode toggle skips cleanup entirely.

## One dictation, end to end

1. You hold Fn. The event tap fires, the HUD fades in with a live level meter, and AVAudioEngine starts capturing the mic.
2. You speak. Audio accumulates in memory, converted to 16 kHz mono Float32.
3. You release Fn. Recording stops and the buffer goes to Parakeet on the Neural Engine (about 0.1 s for a 10 s utterance).
4. The raw transcript goes to the cleanup engine together with your dictionary and the frontmost app's profile. FoundationModels rewrites it: punctuation, capitalization, filler removal, self-corrections, tone. Hard 3 s timeout: on timeout, refusal, or unavailability the raw transcript is used instead, so your words are never lost.
5. TextInserter saves whatever is on your clipboard, places the final text on it, sends a synthetic Cmd+V to the focused app, then restores your original clipboard about 250 ms later.
6. The HUD briefly shows the result and fades. HistoryStore records text and metadata (from M2 on). Total time from key release: under 1 s.

## Milestones

### M0: Scaffold + permissions (done)
- Repo, `project.yml` (XcodeGen), bundle id `com.elliot.Murmur`, Makefile (`make build/run/test`), Apple Development signing (team UT78GDF44Z) so TCC grants survive rebuilds.
- MenuBarExtra shell, onboarding window with live permission status (mic, accessibility, input monitoring) and "Open System Settings" buttons, plus the Globe-key setting instruction.

### M1: Core dictation loop (daily-usable)
- HotkeyService: Fn hold = push-to-talk (flagsChanged, `.maskSecondaryFn`), Fn double-tap = hands-free toggle. Extracted pure `HotkeyStateMachine` for unit tests. Right Command alternative for users who keep Globe features.
- AudioRecorder: AVAudioEngine tap, 16 kHz mono Float32, audio in memory only. Voice-processed capture (`setVoiceProcessingEnabled(true)`: Apple noise suppression + echo cancellation) on by default with a Settings toggle.
- FluidAudioTranscriber: batch `AsrManager.transcribe()` on release. First-run model download UI with progress.
- FoundationModelsCleanup with availability check; RawPassthrough fallback and menu toggle.
- TextInserter: save pasteboard items, write cleaned text, synthetic Cmd+V, restore after ~250 ms (configurable).
- HUD panel: recording level meter + state. Esc cancels.
- Acceptance: p50 key-release to text under 1 s for utterances under 15 s; works in Slack, Mail, VS Code, Safari text fields; clipboard restored intact.

### M2: Daily-driver polish (done 2026-08-21; deviations noted inline)
- Personal dictionary: manual add/edit list, injected into cleanup prompt. JSON in Application Support.
- History window: SwiftData records (date, app, raw transcript, cleaned text, duration, mode), search, copy, delete. No audio retained.
- Per-app profiles: match by bundle id; fields: tone hint, raw mode, custom vocab. Editor in Settings.
- Streaming preview: implemented as incremental batch re-transcription of the growing buffer every 0.9 s (reuses the loaded v2 engine, no second model download, coherent text every tick). FluidAudio's true streaming managers (EOU/Nemotron variants) need separate models; revisit only if the preview cadence feels slow.
- Launch at login (SMAppService), sound cues, Ollama backend option in Settings (model picker from `/api/tags`).
- STT engine bench harness: ~20 fixture recordings across real conditions (quiet desk Mac mic, AirPods, noisy cafe) with hand-corrected references. CLI target runs every `TranscriptionService` engine and reports WER and latency. The harness compares Parakeet v2 and v3 (`make bench BENCH_FLAGS=--v3`). WhisperKit large-v3-turbo deferred: add it behind `TranscriptionService` only if the personal-fixture numbers show Parakeet struggling.

### M3: Full replica features (done 2026-08-21)
- Command mode: hold Right Option with text selected, speak an instruction, selection is rewritten in place. Selection capture via AX `selectedText`, fallback Cmd+C with restore. Rewrites default to Ollama (bigger model), FoundationModels fallback.
- Context awareness: frontmost app + AX window title fed to cleanup prompt. No screenshots in v1. Field-tested correction: the Apple 3B model echoes the destination line into output and invents headers to match the app, so destination context is fed to the Ollama engine only. App tone for the Apple engine comes from per-app profile instructions.
- Auto-learn dictionary: track repeated out-of-vocabulary proper nouns from history, surface "add to dictionary?" suggestions in Settings.

## Key implementation notes

- Event tap: `CGEvent.tapCreate` at `.cgSessionEventTap`, `.listenOnly`, mask `flagsChanged | keyDown`. Fn state = `.maskSecondaryFn` flag transitions. Listen-only cannot swallow the Globe key, hence the system setting change in onboarding. Re-enable tap on `kCGEventTapDisabledByTimeout`.
- Parakeet expects 16 kHz mono Float32; use AVAudioConverter from the input node format.
- FoundationModels: guard on `.available`; handle guardrail refusals by falling back to raw transcript (never lose the user's words). Keep one warm `LanguageModelSession`; new session if context grows past ~3k tokens.
- Latency instrumentation: os_signpost intervals (record, transcribe, cleanup, insert) + debug overlay in HUD.
- TCC gotcha: permissions bind to bundle id + code signature. Bundle id and signing are stable from M0. Reset commands are in the README.
- Threading: audio + tap callbacks off-main, UI on MainActor, Swift 6 strict concurrency on.

## Testing and verification

- Unit (XCTest via `make test`): HotkeyStateMachine transitions (hold, double-tap, esc-cancel), cleanup prompt builder (dictionary + profile injection), pasteboard save/restore round-trip, ProfileResolver matching, DictionaryStore CRUD.
- Integration (slow, manual trigger): bundled fixture WAV through FluidAudioTranscriber, assert expected phrase; FoundationModels cleanup golden tests on sample raw transcripts.
- Manual QA checklist: permissions onboarding on fresh grant, dictation into Slack/Mail/VS Code/Safari/Terminal, clipboard with image survives restore, secure input field behavior, Fn vs Right Command modes, hands-free toggle, Esc cancel.
- E2E latency check: dictate a 10 s utterance, HUD debug shows each stage, total under 1 s after release.

## Risks and mitigations

- Fn conflicts with system Globe actions: onboarding instructs the settings change; Right Command alternative.
- Apple Intelligence disabled: availability check falls back to Ollama (once added in M2), then RawPassthrough. Cleanup never blocks insertion (3 s timeout, insert raw).
- Paste blocked in odd apps: per-app profile can switch to "type characters" insertion (CGEvent keyboard events) later; not in M1.
- FluidAudio API drift: pin package version in project.yml.

## Out of scope

Distribution/notarization, Windows/Linux, non-English languages, screenshot-based context, audio retention, custom fine-tuned models.
