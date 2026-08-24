import AVFoundation
import FluidAudio
import Foundation
import os

/// One transcribed line of a meeting.
struct MeetingSegment: Codable, Equatable, Sendable {
    /// "me" (mic) or "them" (system audio).
    let source: String
    /// Seconds from meeting start where this segment's window began.
    let offset: Double
    let text: String
}

/// Live transcription for one meeting: two FluidAudio sliding-window
/// sessions (mic and system audio) whose window processing is serialized
/// through the app-wide InferenceGate.
///
/// SlidingWindowAsrManager processes a window on its own actor the moment
/// enough samples are fed, outside any external lock. The gate discipline
/// here exploits that determinism instead of fighting it: audio is fed
/// freely while it stays below the next window threshold, and the feed that
/// crosses a threshold happens while holding the gate, waiting for the
/// resulting window's transcription update before releasing. One inference
/// at a time, app-wide, without forking FluidAudio.
actor MeetingEngine {
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting-engine")
    private let signposter = OSSignposter(subsystem: "com.elliot.Murmur", category: "meeting")

    // Mirrors SlidingWindowAsrConfig.default (11 + 2 + 2 layout).
    private static let sampleRate = 16_000
    private static let chunkSamples = 11 * sampleRate
    private static let rightSamples = 2 * sampleRate

    private final class StreamState {
        let session: SlidingWindowAsrManager
        let spill: FileHandle?
        var pending: [Float] = []
        var fedSamples = 0
        var nextWindowCenter = 0
        /// Updates land here from the consumer task; pump pops them. A
        /// buffered queue rather than a handoff continuation: an update that
        /// arrives just after a timeout stays queued for the next window
        /// instead of being lost or stranding a waiter.
        var updateQueue: [SlidingWindowTranscriptionUpdate] = []
        var updateSignal: CheckedContinuation<Void, Never>?
        var consumerTask: Task<Void, Never>?
        var pumping = false

        init(session: SlidingWindowAsrManager, spill: FileHandle?) {
            self.session = session
            self.spill = spill
        }
    }

    private var streams: [String: StreamState] = [:]
    private var finished = false
    /// Delivered for every confirmed window, in order per stream.
    private let onSegment: @Sendable (MeetingSegment) -> Void

    init(onSegment: @escaping @Sendable (MeetingSegment) -> Void) {
        self.onSegment = onSegment
    }

    /// Creates both sessions from the already-loaded dictation models.
    /// Throws if the speech model is not ready yet.
    func start(models: AsrModels, spillDirectory: URL) async throws {
        for name in ["me", "them"] {
            let session = SlidingWindowAsrManager()
            try await session.loadModels(models)
            try await session.startStreaming(source: .microphone)
            let spillURL = spillDirectory.appendingPathComponent("\(name).pcm16")
            FileManager.default.createFile(atPath: spillURL.path, contents: nil)
            let spill = try? FileHandle(forWritingTo: spillURL)
            let state = StreamState(session: session, spill: spill)
            streams[name] = state
            state.consumerTask = Task { [weak self] in
                let updates = await session.transcriptionUpdates
                for await update in updates {
                    await self?.received(update, stream: name)
                }
            }
        }
        log.notice("meeting engine started")
    }

    /// Called from capture callbacks with each new chunk.
    func append(_ samples: [Float], stream name: String) {
        guard !finished, let state = streams[name], !samples.isEmpty else { return }
        state.pending.append(contentsOf: samples)
        state.spill?.write(Self.pcm16Data(samples))
        pumpIfNeeded(state, name: name)
    }

    /// Flushes both sessions (final partial windows) and tears down.
    /// Segments for the tail arrive through the usual update path.
    func finish() async {
        guard !finished else { return }
        finished = true
        for (name, state) in streams {
            await InferenceGate.shared.run { [session = state.session] in
                do {
                    _ = try await session.finish()
                } catch {
                    self.log.error("meeting \(name, privacy: .public) finish failed: \(error, privacy: .public)")
                }
            }
        }
        // Let trailing updates drain into segments before tearing down.
        try? await Task.sleep(for: .milliseconds(300))
        for (name, state) in streams {
            drainQueuedSegments(state, name: name)
            state.consumerTask?.cancel()
            state.updateSignal?.resume()
            state.updateSignal = nil
            try? state.spill?.close()
        }
        streams = [:]
        log.notice("meeting engine finished")
    }

    func abort() async {
        guard !finished else { return }
        finished = true
        for state in streams.values {
            await state.session.cancel()
            state.consumerTask?.cancel()
            state.updateSignal?.resume()
            state.updateSignal = nil
            try? state.spill?.close()
        }
        streams = [:]
    }

    /// Emits any updates still queued after finish() flushed the sessions
    /// (finish-time windows land in the queue because `finished` is set).
    private func drainQueuedSegments(_ state: StreamState, name: String) {
        while !state.updateQueue.isEmpty {
            let update = state.updateQueue.removeFirst()
            guard !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let offset = Double(state.nextWindowCenter) / Double(Self.sampleRate)
            state.nextWindowCenter += Self.chunkSamples
            onSegment(MeetingSegment(source: name, offset: offset, text: update.text))
        }
    }

    // MARK: - Feeding

    private func pumpIfNeeded(_ state: StreamState, name: String) {
        guard !state.pumping else { return }
        state.pumping = true
        Task { [weak self] in
            await self?.pump(name: name)
        }
    }

    private func pump(name: String) async {
        defer { streams[name]?.pumping = false }
        while !finished, let state = streams[name] {
            let threshold = state.nextWindowCenter + Self.chunkSamples + Self.rightSamples
            let untilThreshold = threshold - state.fedSamples
            if state.pending.count < untilThreshold {
                // Entirely below the next window boundary: feed freely.
                guard !state.pending.isEmpty else { return }
                let chunk = state.pending
                state.pending.removeAll(keepingCapacity: true)
                state.fedSamples += chunk.count
                await feed(chunk, to: state.session)
                return
            }
            // The next feed crosses a window boundary: do it under the gate
            // and hold until that window's text lands.
            let crossing = Array(state.pending.prefix(untilThreshold))
            state.pending.removeFirst(untilThreshold)
            state.fedSamples += crossing.count
            let windowCenter = state.nextWindowCenter
            state.nextWindowCenter += Self.chunkSamples
            let session = state.session
            let interval = signposter.beginInterval("meeting-window")
            let update = await InferenceGate.shared.run { [weak self] in
                await self?.feed(crossing, to: session)
                return await self?.nextUpdate(name: name, timeout: .seconds(5)) ?? nil
            }
            signposter.endInterval("meeting-window", interval)
            if let update, !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSegment(
                    MeetingSegment(
                        source: name,
                        offset: Double(windowCenter) / Double(Self.sampleRate),
                        text: update.text
                    )
                )
            } else if update == nil {
                log.error("meeting \(name, privacy: .public) window timed out; marked as gap")
            }
        }
    }

    private nonisolated func feed(_ samples: [Float], to session: SlidingWindowAsrManager) async {
        guard let buffer = Self.pcmBuffer(from: samples) else { return }
        await session.streamAudio(buffer)
    }

    // MARK: - Update plumbing

    private func received(_ update: SlidingWindowTranscriptionUpdate, stream name: String) {
        guard let state = streams[name] else { return }
        if state.pumping || finished {
            // Pump is mid-window (or finish is flushing): queue for pickup.
            state.updateQueue.append(update)
            if let signal = state.updateSignal {
                state.updateSignal = nil
                signal.resume()
            }
            return
        }
        // No pump in flight: a flush-time window from finish(). Emit with
        // the engine's best-known offset.
        if !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let offset = Double(state.nextWindowCenter) / Double(Self.sampleRate)
            state.nextWindowCenter += Self.chunkSamples
            onSegment(MeetingSegment(source: name, offset: offset, text: update.text))
        }
    }

    private func nextUpdate(
        name: String, timeout: Duration
    ) async -> SlidingWindowTranscriptionUpdate? {
        guard let state = streams[name] else { return nil }
        if !state.updateQueue.isEmpty {
            return state.updateQueue.removeFirst()
        }
        // Wait for the consumer's signal, bounded by the timeout. The signal
        // continuation is always resumed by whichever side fires first;
        // both paths run on this actor, so the handoff cannot race.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.awaitSignal(name: name)
            }
            group.addTask { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.fireSignal(name: name)
            }
            await group.next()
            group.cancelAll()
            await group.waitForAll()
        }
        guard let state = streams[name], !state.updateQueue.isEmpty else { return nil }
        return state.updateQueue.removeFirst()
    }

    private func awaitSignal(name: String) async {
        await withCheckedContinuation { continuation in
            guard let state = streams[name], state.updateSignal == nil,
                state.updateQueue.isEmpty
            else {
                continuation.resume()
                return
            }
            state.updateSignal = continuation
        }
    }

    /// Resumes a pending signal waiter (used by the timeout path so the
    /// task group can always drain).
    private func fireSignal(name: String) {
        guard let state = streams[name], let signal = state.updateSignal else { return }
        state.updateSignal = nil
        signal.resume()
    }

    // MARK: - Sample plumbing

    private static func pcmBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                channels: 1, interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
            )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress, let channel = buffer.floatChannelData else { return }
            channel[0].update(from: base, count: samples.count)
        }
        return buffer
    }

    private static func pcm16Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * 32767)
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
