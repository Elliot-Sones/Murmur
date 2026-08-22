import AVFoundation
import Observation
import os

/// Speechify-style reader: splits text into sentences, synthesizes them
/// ahead of playback, and exposes play/pause, sentence skips, speed, and
/// progress for the reader bar.
@MainActor
@Observable
final class ReaderController: NSObject, AVAudioPlayerDelegate {
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
            player?.rate = Float(speed)
        }
    }
    /// Set when synthesis fails; the bar shows it instead of controls.
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
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
            player?.pause()
            isPlaying = false
        } else {
            isPlaying = true
            if let player, player.currentTime > 0 {
                player.play()
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
        player?.stop()
        player = nil
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
        player?.stop()
        player = nil
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
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(speed)
            self.player = player
            player.play()
        } catch {
            log.error("playback failed: \(error, privacy: .public)")
            errorMessage = "Could not play the synthesized audio."
            isPlaying = false
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard isActive, isPlaying else { return }
            if index + 1 < sentences.count {
                index += 1
                playCurrent()
            } else {
                stop()
            }
        }
    }
}
