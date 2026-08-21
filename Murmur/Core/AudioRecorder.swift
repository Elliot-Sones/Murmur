import AVFoundation

enum RecorderError: Error {
    case noInputDevice
}

/// Captures microphone audio and accumulates 16 kHz mono Float32 samples in memory.
/// The tap callback runs on a CoreAudio queue; shared state is lock-guarded.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    /// Called on the audio thread with an RMS level in 0...1 for the HUD meter.
    var onLevel: (@Sendable (Float) -> Void)?

    @MainActor
    func start(voiceProcessing: Bool) throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(voiceProcessing)

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.noInputDevice
        }
        lock.withLock { converter = newConverter }

        // The explicit @Sendable type keeps this closure from inheriting MainActor
        // isolation; the tap fires on a CoreAudio queue and the runtime isolation
        // assert crashes the app (SIGTRAP) if the closure is actor-isolated.
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tapBlock)
        engine.prepare()
        try engine.start()
    }

    @MainActor
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            let frames = Int(buffer.frameLength)
            for index in 0..<frames {
                let sample = channel[index]
                sum += sample * sample
            }
            let rms = (sum / Float(frames)).squareRoot()
            onLevel?(min(rms * 8, 1))
        }

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
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
