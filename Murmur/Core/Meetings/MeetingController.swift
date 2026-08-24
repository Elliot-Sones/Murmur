import AppKit
import FluidAudio
import Observation
import os

/// Orchestrates one meeting: system + mic capture → MeetingEngine →
/// MeetingStore, with observable state for the menu bar and Meetings tab.
@MainActor
@Observable
final class MeetingController {
    static let shared = MeetingController()

    enum State: Equatable {
        case idle
        case recording(meetingId: String)
        case failed(String)
    }

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting")

    private(set) var state: State = .idle
    private(set) var startedAt: Date?

    @ObservationIgnored private var engine: MeetingEngine?
    @ObservationIgnored private let systemCapture = SystemAudioCapture()
    @ObservationIgnored private let micCapture = MeetingMicCapture()

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var liveMeetingId: String? {
        if case .recording(let id) = state { return id }
        return nil
    }

    func startMeeting() {
        guard case .idle = state else { return }
        guard SystemAudioCapture.permissionGranted() else {
            // First run: this triggers the system prompt. The user grants in
            // System Settings and starts again (macOS requires app restart
            // only for some TCC changes; retry is cheap either way).
            SystemAudioCapture.requestPermission()
            state = .failed("Allow Screen Recording for Murmur in System Settings, then start again.")
            autoClearFailure()
            return
        }
        Task { await begin() }
    }

    func endMeeting() {
        guard case .recording(let id) = state else { return }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state = .idle
        startedAt = nil
        micCapture.stop()
        let engine = engine
        self.engine = nil
        Task {
            await systemCapture.stop()
            await engine?.finish()
            MeetingStore.shared.finish(id, duration: duration)
            self.log.notice("meeting ended after \(Int(duration)) s")
        }
    }

    private func begin() async {
        guard let models = await (DictationController.shared.transcriberService as? FluidAudioTranscriber)?
            .loadedModels()
        else {
            state = .failed("The speech model is still loading. Try again in a moment.")
            autoClearFailure()
            return
        }
        let record = MeetingStore.shared.create(title: Self.defaultTitle())
        let engine = MeetingEngine { segment in
            Task { @MainActor in
                MeetingStore.shared.append(segment, to: record.id)
            }
        }
        do {
            try await engine.start(
                models: models, spillDirectory: MeetingStore.shared.spillDirectory(for: record.id)
            )
            systemCapture.onSamples = { samples in
                Task { await engine.append(samples, stream: "them") }
            }
            systemCapture.onFailure = { message in
                Task { @MainActor in
                    MeetingController.shared.captureFailed(message)
                }
            }
            micCapture.onSamples = { samples in
                Task { await engine.append(samples, stream: "me") }
            }
            try await systemCapture.start()
            try micCapture.start()
            self.engine = engine
            startedAt = Date()
            state = .recording(meetingId: record.id)
            SoundCue.recordingStarted()
            log.notice("meeting started: \(record.id, privacy: .public)")
        } catch {
            log.error("meeting start failed: \(error, privacy: .public)")
            await engine.abort()
            micCapture.stop()
            await systemCapture.stop()
            MeetingStore.shared.delete(record.id)
            state = .failed("Could not start meeting capture: \(error.localizedDescription)")
            autoClearFailure()
        }
    }

    private func captureFailed(_ message: String) {
        guard isRecording else { return }
        log.error("system capture died mid-meeting: \(message, privacy: .public)")
        endMeeting()
        state = .failed("Meeting audio capture stopped: \(message)")
        autoClearFailure()
    }

    private func autoClearFailure() {
        Task {
            try? await Task.sleep(for: .seconds(6))
            if case .failed = state { state = .idle }
        }
    }

    private static func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Meeting \(formatter.string(from: Date()))"
    }
}
