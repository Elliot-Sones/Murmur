import AVFoundation
import os

/// The user's side of a meeting: a minimal mic tap on its own AVAudioEngine,
/// independent of the dictation AudioRecorder so dictating mid-meeting never
/// resets meeting capture. Delivers 16 kHz mono Float32 chunks.
final class MeetingMicCapture: @unchecked Sendable {
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting-audio")
    private var engine: AVAudioEngine?
    private var configChangeObserver: (any NSObjectProtocol)?
    private var rebuildTask: Task<Void, Never>?
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    /// Called on the audio thread with each converted 16 kHz mono chunk.
    var onSamples: (@Sendable ([Float]) -> Void)?

    @MainActor
    func start() throws {
        tearDown()
        try startEngine()
    }

    @MainActor
    func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        tearDown()
    }

    @MainActor
    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.noInputDevice
        }
        lock.withLock { converter = newConverter }

        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tapBlock)
        engine.prepare()
        try engine.start()
        self.engine = engine
        log.notice("meeting mic started: \(inputFormat.sampleRate, format: .fixed(precision: 0)) Hz")

        // Dictation's Bluetooth steering flips the default input mid-meeting;
        // rebuild against the new device and keep going.
        let engineID = ObjectIdentifier(engine)
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let engine = self.engine,
                    ObjectIdentifier(engine) == engineID else { return }
                self.rebuild(attempt: 1)
            }
        }
    }

    @MainActor
    private func rebuild(attempt: Int) {
        tearDown()
        do {
            try startEngine()
            log.notice("meeting mic rebuilt after input change")
        } catch {
            guard attempt < 5 else {
                log.error("meeting mic rebuild failed; user audio lost until restart")
                return
            }
            rebuildTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.rebuild(attempt: attempt + 1)
            }
        }
    }

    @MainActor
    private func tearDown() {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter = lock.withLock({ converter }) else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }
        var fed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        onSamples?(Array(UnsafeBufferPointer(start: channel, count: count)))
    }
}
