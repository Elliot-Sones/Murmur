import AppKit
import Carbon
import Observation
import os

/// Orchestrates one dictation: record → transcribe → clean → insert.
@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case preparing(String)
        case recording
        case transcribing
        case inserting
        case notice(String)
    }

    static let shared = DictationController()

    @ObservationIgnored private let log = Logger(subsystem: "com.elliot.Murmur", category: "dictation")

    private(set) var state: State = .idle {
        didSet {
            log.notice("state -> \(String(describing: self.state), privacy: .public)")
            HUDPanelController.shared.stateChanged(state)
        }
    }
    var audioLevel: Float = 0
    private(set) var previewText = ""
    private(set) var lastLatencyMs: Int?
    private(set) var lastRun: DictationRunStats?
    private(set) var engineStatus = "Speech model not loaded"

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let transcriber: any TranscriptionService = FluidAudioTranscriber()
    @ObservationIgnored private let cleanup = FoundationModelsCleanup()
    @ObservationIgnored private let ollamaCleanup = OllamaCleanup()
    @ObservationIgnored private let rawCleanup = RawPassthroughCleanup()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private let signposter = OSSignposter(
        subsystem: "com.elliot.Murmur", category: "dictation"
    )

    private var recordingStartedAt: ContinuousClock.Instant?
    private var targetApp: (bundleId: String?, name: String?) = (nil, nil)
    private let minimumUtterance: Duration = .milliseconds(300)
    private let maximumUtterance: Duration = .seconds(300)
    private var maxDurationTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    func prepareEngines() {
        Task {
            do {
                try await transcriber.prepare { message in
                    Task { @MainActor in
                        DictationController.shared.engineStatus = message
                        if case .preparing = DictationController.shared.state {
                            DictationController.shared.state = message == "Ready" ? .idle : .preparing(message)
                        } else if message != "Ready" {
                            DictationController.shared.state = .preparing(message)
                        }
                    }
                }
            } catch {
                engineStatus = "Speech model failed to load"
                state = .notice("Speech model failed to load. Check network and relaunch.")
            }
        }
        log.notice("Apple cleanup available: \(FoundationModelsCleanup.isAvailable)")
        cleanup.prewarm(context: CleanupContext(dictionary: DictionaryStore.shared.words))
    }

    func beginDictation() {
        switch state {
        case .idle, .notice, .preparing: break
        default: return
        }
        guard !IsSecureEventInputEnabled() else {
            state = .notice("A password field is active. Dictation is off.")
            autoDismissNotice()
            return
        }
        let permissions = PermissionsService.shared
        permissions.refresh()
        switch permissions.snapshot.microphone {
        case .notDetermined:
            permissions.requestMicrophone()
            state = .notice("Allow microphone access, then dictate again.")
            autoDismissNotice()
            return
        case .denied:
            state = .notice("Microphone permission is off. Opening System Settings.")
            autoDismissNotice()
            SystemSettingsPane.microphone.open()
            return
        case .granted:
            break
        }
        recorder.onLevel = { level in
            Task { @MainActor in DictationController.shared.audioLevel = level }
        }
        do {
            try recorder.start(voiceProcessing: SettingsStore.shared.voiceProcessingEnabled)
        } catch {
            state = .notice("Microphone unavailable. Check permissions.")
            autoDismissNotice()
            return
        }
        targetApp = ContextProvider.frontmostApp()
        recordingStartedAt = ContinuousClock.now
        previewText = ""
        state = .recording
        if SettingsStore.shared.streamingPreviewEnabled {
            startPreviewLoop()
        }
        maxDurationTask = Task { [maximumUtterance] in
            try? await Task.sleep(for: maximumUtterance)
            guard !Task.isCancelled else { return }
            // Never auto-paste a runaway recording; discard it instead.
            DictationController.shared.cancelDictation()
            DictationController.shared.state = .notice("Dictation stopped after 5 minutes and was discarded.")
            DictationController.shared.autoDismissNotice()
        }
    }

    func finishDictation() {
        guard state == .recording else { return }
        maxDurationTask?.cancel()
        previewTask?.cancel()
        let samples = recorder.stop()
        let startedAt = recordingStartedAt
        recordingStartedAt = nil

        var peak: Float = 0
        for sample in samples where abs(sample) > peak { peak = abs(sample) }
        log.info("captured \(samples.count) samples, peak \(peak, format: .fixed(precision: 3))")

        guard let startedAt, ContinuousClock.now - startedAt >= minimumUtterance else {
            state = .idle
            return
        }
        state = .transcribing
        let releasedAt = ContinuousClock.now

        Task {
            await runPipeline(samples: samples, releasedAt: releasedAt)
        }
    }

    func cancelDictation() {
        guard state == .recording else { return }
        maxDurationTask?.cancel()
        previewTask?.cancel()
        _ = recorder.stop()
        recordingStartedAt = nil
        state = .idle
    }

    /// Re-runs the batch engine over the growing buffer for a live HUD preview.
    /// Cheap on Apple Silicon (~100 ms per tick at 110x realtime) and reuses
    /// the exact engine that produces the final transcript.
    private func startPreviewLoop() {
        previewTask?.cancel()
        previewTask = Task {
            let minimumSamples = 16_000
            let previewWindow = 16_000 * 60
            while !Task.isCancelled, state == .recording {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, state == .recording else { return }
                guard await transcriber.isReady else { continue }
                var samples = recorder.snapshotSamples()
                guard samples.count >= minimumSamples else { continue }
                if samples.count > previewWindow {
                    samples = Array(samples.suffix(previewWindow))
                }
                guard let text = try? await transcriber.transcribe(samples) else { continue }
                if state == .recording, !text.isEmpty {
                    previewText = text
                }
            }
        }
    }

    private func runPipeline(samples: [Float], releasedAt: ContinuousClock.Instant) async {
        let overall = signposter.beginInterval("pipeline")
        defer { signposter.endInterval("pipeline", overall) }

        let transcribeInterval = signposter.beginInterval("transcribe")
        let raw: String
        do {
            raw = try await transcriber.transcribe(samples)
        } catch is TranscriberError {
            signposter.endInterval("transcribe", transcribeInterval)
            state = .notice("Speech model is still loading. Try again in a moment.")
            autoDismissNotice()
            return
        } catch {
            signposter.endInterval("transcribe", transcribeInterval)
            state = .notice("Transcription failed.")
            autoDismissNotice()
            return
        }
        signposter.endInterval("transcribe", transcribeInterval)

        guard !raw.isEmpty else {
            log.notice("empty transcript, nothing to insert")
            state = .notice("Heard nothing. Check the mic and try again.")
            autoDismissNotice()
            return
        }
        log.info("transcribed \(raw.count) chars")

        let transcribedAt = ContinuousClock.now

        let profile = ProfileStore.shared.resolve(bundleId: targetApp.bundleId)
        var context = CleanupContext(
            dictionary: DictionaryStore.shared.words,
            toneHint: profile?.toneHint
        )
        if let vocab = profile?.vocab, !vocab.isEmpty {
            context.dictionary += vocab
        }
        let profileForcesRaw = profile?.rawMode ?? false
        let cleanupEnabled = SettingsStore.shared.cleanupEnabled && !profileForcesRaw

        let cleanupInterval = signposter.beginInterval("cleanup")
        let service: any CleanupService
        if !cleanupEnabled {
            service = rawCleanup
        } else if SettingsStore.shared.cleanupEngine == .ollama {
            service = ollamaCleanup
        } else {
            service = cleanup
        }
        let cleaned = await service.cleanup(raw, context: context)
        signposter.endInterval("cleanup", cleanupInterval)
        let cleanedAt = ContinuousClock.now

        state = .inserting
        let insertInterval = signposter.beginInterval("insert")
        await inserter.insert(cleaned, restoreDelayMs: SettingsStore.shared.restoreDelayMs)
        signposter.endInterval("insert", insertInterval)
        let pastedAt = ContinuousClock.now

        let engine: String
        if cleanupEnabled {
            engine = service.lastOutcome
        } else if profileForcesRaw {
            engine = "raw (app profile)"
        } else {
            engine = "raw (cleanup off)"
        }
        let stats = DictationRunStats(
            audioMs: samples.count * 1000 / 16_000,
            transcribeMs: Self.milliseconds(transcribedAt - releasedAt),
            cleanupMs: Self.milliseconds(cleanedAt - transcribedAt),
            pasteMs: Self.milliseconds(pastedAt - cleanedAt),
            characters: cleaned.count,
            engine: engine
        )
        lastRun = stats
        lastLatencyMs = stats.totalMs
        log.notice("run: \(stats.audioSummary, privacy: .public) [\(stats.stageSummary, privacy: .public)] engine: \(engine, privacy: .public)")
        HistoryStore.shared.add(
            DictationRecord(
                date: Date(),
                appBundleId: targetApp.bundleId,
                appName: targetApp.name,
                rawTranscript: raw,
                cleanedText: cleaned,
                audioMs: stats.audioMs,
                totalMs: stats.totalMs,
                engine: engine
            )
        )
        state = .idle
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    func autoDismissNotice() {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .notice = state { state = .idle }
        }
    }
}
