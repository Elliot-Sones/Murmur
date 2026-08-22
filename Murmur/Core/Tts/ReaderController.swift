import AVFoundation
import Observation
import os

/// Speechify-style reader: splits text into sentences, synthesizes them
/// ahead of playback, and exposes play/pause, sentence skips, speed, and
/// progress for the reader bar. Playback runs through a time-pitch unit so
/// speeds beyond AVAudioPlayer's 2x cap stay natural-pitched.
@MainActor
@Observable
final class ReaderController {
    static let shared = ReaderController()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "reader")

    private(set) var sentences: [String] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    /// True between start() and stop(); the bar stays up while paused.
    private(set) var isActive = false
    var speed: Double = SettingsStore.shared.readerSpeed {
        didSet {
            SettingsStore.shared.readerSpeed = speed
            timePitch.rate = Float(speed)
        }
    }
    /// Set when synthesis fails; the bar shows it instead of controls.
    private(set) var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private var engineWired = false
    @ObservationIgnored private var pausedMidSentence = false
    /// Bumped whenever the player node stops; pending buffer-completion
    /// callbacks compare it so a skip cannot double-advance the index.
    @ObservationIgnored private var playToken = 0
    @ObservationIgnored private var cache: [Int: Data] = [:]
    @ObservationIgnored private var fetchTasks: [Int: Task<Void, Never>] = [:]
    /// Bumped on every start/stop; stale synthesis tasks check it and bail.
    @ObservationIgnored private var generation = 0
    /// How many sentences to synthesize ahead of the one playing.
    @ObservationIgnored private let prefetchDepth = 2

    var progress: Double {
        sentences.isEmpty ? 0 : Double(index) / Double(sentences.count)
    }

    var currentSentence: String? {
        sentences.indices.contains(index) ? sentences[index] : nil
    }

    // MARK: - Transport

    func start(_ text: String) {
        stop()
        let parts = SentenceSplitter.split(text)
        guard !parts.isEmpty else { return }
        generation += 1
        sentences = parts
        index = 0
        isActive = true
        isPlaying = true
        errorMessage = nil
        PillPanelController.shared.layout()
        playCurrent()
    }

    func playPause() {
        guard isActive else { return }
        if isPlaying {
            playerNode.pause()
            pausedMidSentence = true
            isPlaying = false
        } else {
            isPlaying = true
            if pausedMidSentence {
                pausedMidSentence = false
                playerNode.play()
            } else {
                playCurrent()
            }
        }
    }

    func skipForward() { jump(to: index + 1) }
    func skipBack() { jump(to: index - 1) }

    func cycleSpeed() {
        speed = ReaderSpeed.next(after: speed)
    }

    func stop() {
        generation += 1
        // Cancel in-flight synthesis; stale requests otherwise keep the
        // single-worker server busy and starve the next reading.
        for task in fetchTasks.values { task.cancel() }
        fetchTasks = [:]
        stopPlayback()
        sentences = []
        index = 0
        isPlaying = false
        isActive = false
        errorMessage = nil
        cache = [:]
        PillPanelController.shared.layout()
    }

    // MARK: - Pipeline

    private func jump(to newIndex: Int) {
        guard isActive else { return }
        guard sentences.indices.contains(newIndex) else {
            if newIndex >= sentences.count { stop() }
            return
        }
        stopPlayback()
        index = newIndex
        if isPlaying { playCurrent() }
    }

    private func playCurrent() {
        guard isActive, sentences.indices.contains(index) else {
            stop()
            return
        }
        let wanted = index
        prefetch(from: wanted)
        if let data = cache[wanted] {
            play(data)
            return
        }
        // Not synthesized yet; playCurrent re-runs when the fetch lands.
        let gen = generation
        Task { @MainActor in
            while generation == gen, cache[wanted] == nil, fetchTasks[wanted] != nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard generation == gen, isPlaying, index == wanted else { return }
            if cache[wanted] != nil {
                playCurrent()
            }
        }
    }

    private func prefetch(from start: Int) {
        for i in start...min(start + prefetchDepth, sentences.count - 1) {
            let target = i
            guard cache[target] == nil, fetchTasks[target] == nil else { continue }
            let gen = generation
            let text = sentences[target]
            fetchTasks[target] = Task { @MainActor in
                let result = await TtsService.shared.synthesize(text)
                guard generation == gen, !Task.isCancelled else { return }
                fetchTasks[target] = nil
                switch result {
                case .audio(let data):
                    cache[target] = data
                case .failure(let message):
                    log.error("synthesis failed at \(target, privacy: .public): \(message, privacy: .public)")
                    errorMessage = message
                    isPlaying = false
                }
            }
        }
    }

    private func play(_ data: Data) {
        do {
            // AVAudioFile needs a URL; the wav bytes take a brief trip to /tmp.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("murmur-sentence.wav")
            try data.write(to: url)
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw NSError(
                    domain: "Murmur.reader", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "could not allocate audio buffer"]
                )
            }
            try file.read(into: buffer)

            wireEngineIfNeeded(format: file.processingFormat)
            timePitch.rate = Float(speed)
            if !engine.isRunning { try engine.start() }

            pausedMidSentence = false
            let token = playToken
            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                Task { @MainActor in self.sentenceFinished(token: token) }
            }
            playerNode.play()
        } catch {
            log.error("playback failed: \(error, privacy: .public)")
            errorMessage = "Could not play the synthesized audio."
            isPlaying = false
        }
    }

    /// Connect (or reconnect on format change) player → time-pitch → output.
    private func wireEngineIfNeeded(format: AVAudioFormat) {
        if !engineWired {
            engine.attach(playerNode)
            engine.attach(timePitch)
            engineWired = true
        }
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    private func stopPlayback() {
        // Bump first: node.stop() fires pending completion callbacks, and a
        // stale token keeps them from advancing the sentence index.
        playToken += 1
        playerNode.stop()
        pausedMidSentence = false
        if engine.isRunning { engine.stop() }
    }

    private func sentenceFinished(token: Int) {
        guard token == playToken, isActive, isPlaying else { return }
        if index + 1 < sentences.count {
            index += 1
            playCurrent()
        } else {
            stop()
        }
    }
}
