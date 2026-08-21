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

    private(set) var state: State = .idle {
        didSet { HUDPanelController.shared.stateChanged(state) }
    }
    var audioLevel: Float = 0
    private(set) var lastLatencyMs: Int?
    private(set) var engineStatus = "Speech model not loaded"

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let transcriber: any TranscriptionService = FluidAudioTranscriber()
    @ObservationIgnored private let cleanup = FoundationModelsCleanup()
    @ObservationIgnored private let rawCleanup = RawPassthroughCleanup()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private let signposter = OSSignposter(
        subsystem: "com.elliot.Murmur", category: "dictation"
    )

    private var recordingStartedAt: ContinuousClock.Instant?
    private let minimumUtterance: Duration = .milliseconds(300)
    private let maximumUtterance: Duration = .seconds(300)
    private var maxDurationTask: Task<Void, Never>?

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
        cleanup.prewarm()
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
        recordingStartedAt = ContinuousClock.now
        state = .recording
        maxDurationTask = Task { [maximumUtterance] in
            try? await Task.sleep(for: maximumUtterance)
            guard !Task.isCancelled else { return }
            DictationController.shared.finishDictation()
        }
    }

    func finishDictation() {
        guard state == .recording else { return }
        maxDurationTask?.cancel()
        let samples = recorder.stop()
        let startedAt = recordingStartedAt
        recordingStartedAt = nil

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
        _ = recorder.stop()
        recordingStartedAt = nil
        state = .idle
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
            state = .idle
            return
        }

        let cleanupInterval = signposter.beginInterval("cleanup")
        let service: any CleanupService = SettingsStore.shared.cleanupEnabled ? cleanup : rawCleanup
        let cleaned = await service.cleanup(raw)
        signposter.endInterval("cleanup", cleanupInterval)

        state = .inserting
        let insertInterval = signposter.beginInterval("insert")
        await inserter.insert(cleaned, restoreDelayMs: SettingsStore.shared.restoreDelayMs)
        signposter.endInterval("insert", insertInterval)

        let elapsed = ContinuousClock.now - releasedAt
        lastLatencyMs = Int(elapsed.components.seconds * 1000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        state = .idle
    }

    private func autoDismissNotice() {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .notice = state { state = .idle }
        }
    }
}
