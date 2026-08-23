import AVFoundation
import os

enum RecorderError: Error {
    case noInputDevice
}

/// Captures microphone audio and accumulates 16 kHz mono Float32 samples in memory.
/// The tap callback runs on a CoreAudio queue; shared state is lock-guarded.
final class AudioRecorder: @unchecked Sendable {
    /// Fresh per recording. A reused engine keeps the input format of
    /// whatever device was live before; after the default input changes
    /// (AirPods ↔ Mac mic) the tap then fails with a format mismatch and
    /// captures nothing. Only touched from MainActor.
    private var engine: AVAudioEngine?
    private var configChangeObserver: (any NSObjectProtocol)?
    private var rebuildTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var voiceProcessing = false
    private var previousDefaultInput: AudioDeviceID?
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "audio")
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
        rebuildTask?.cancel()
        rebuildTask = nil
        restoreTask?.cancel()
        restoreTask = nil
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        tearDownEngine()
        self.voiceProcessing = voiceProcessing
        do {
            try startEngine()
        } catch {
            scheduleRestore()
            throw error
        }
        startWatchdog()
    }

    /// Opening a Bluetooth mic drags the headphones from A2DP into HFP, so
    /// music drops to telephone quality for the whole recording. Overriding
    /// the device on the engine's input unit does not work: the input node
    /// never refreshes its cached format. Instead, make the built-in mic the
    /// system default input while recording and put the old device back after.
    @MainActor
    private func steerAwayFromBluetoothInput() {
        guard let defaultInput = InputDeviceQuery.defaultID(),
            InputDeviceQuery.isBluetooth(defaultInput),
            let builtIn = InputDeviceQuery.builtInID(),
            InputDeviceQuery.setDefaultInput(builtIn)
        else { return }
        if previousDefaultInput == nil { previousDefaultInput = defaultInput }
        log.notice("switched default input from bluetooth to built-in mic")
    }

    /// Every default-input flip gives CoreAudio a fresh chance to hand the
    /// next engine a dead or transitional device, and rapid dictations were
    /// hitting exactly that. Hold the built-in mic between dictations and
    /// put the Bluetooth device back only after things go quiet.
    @MainActor
    private func scheduleRestore() {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.restoreDefaultInput()
        }
    }

    /// The HAL can wedge during device churn: the engine starts cleanly but
    /// the tap never fires, with no error and no notification. Any healthy
    /// recording appends samples continuously (silence still converts), so a
    /// flat sample count across a tick means the capture path is dead.
    @MainActor
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            var lastCount = 0
            var stalls = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled, self.engine != nil else { return }
                let count = self.lock.withLock { self.samples.count }
                if count > lastCount {
                    lastCount = count
                    stalls = 0
                    continue
                }
                stalls += 1
                guard stalls <= 3 else {
                    self.log.error("capture still stalled after 3 rebuilds; giving up")
                    return
                }
                self.log.notice("no audio for 800 ms; rebuilding engine (stall \(stalls))")
                self.rebuild(attempt: 1)
            }
        }
    }

    @MainActor
    private func restoreDefaultInput() {
        guard let previous = previousDefaultInput else { return }
        previousDefaultInput = nil
        // The headphones may have dropped off mid-recording; only restore a
        // device that still exists.
        guard InputDeviceQuery.exists(previous) else { return }
        if InputDeviceQuery.setDefaultInput(previous) {
            log.notice("restored bluetooth default input")
        }
    }

    @MainActor
    private func startEngine() throws {
        steerAwayFromBluetoothInput()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(voiceProcessing)

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        if voiceProcessing {
            // The echo canceller needs a live full-duplex render path or it
            // produces all-zero input. A muted mixer connection provides one
            // without feeding the mic to the speakers.
            engine.connect(input, to: engine.mainMixerNode, format: inputFormat)
            engine.mainMixerNode.outputVolume = 0
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
        self.engine = engine
        log.notice("engine started: \(inputFormat.sampleRate, format: .fixed(precision: 0)) Hz, \(inputFormat.channelCount) ch, voiceProcessing \(self.voiceProcessing)")

        // The engine stops itself and posts this notification when the input
        // device changes under it (headphones connecting mid-recording switch
        // the default input). Rebuild against the new device so the rest of
        // the utterance is captured; already-accumulated samples are kept.
        let engineID = ObjectIdentifier(engine)
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange(engineID: engineID)
            }
        }
    }

    @MainActor
    private func handleConfigurationChange(engineID: ObjectIdentifier) {
        guard let engine, ObjectIdentifier(engine) == engineID else { return }
        log.notice("input configuration changed; rebuilding audio engine")
        rebuild(attempt: 1)
    }

    /// A newly connected device can report a dead format (sample rate 0) while
    /// the route transition is still in flight, so retry briefly.
    @MainActor
    private func rebuild(attempt: Int) {
        tearDownEngine()
        do {
            try startEngine()
            log.notice("audio engine rebuilt after input change")
        } catch {
            guard attempt < 5 else {
                log.error("audio engine rebuild failed after input change; giving up")
                return
            }
            rebuildTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.rebuild(attempt: attempt + 1)
            }
        }
    }

    @MainActor
    func stop() -> [Float] {
        rebuildTask?.cancel()
        rebuildTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        tearDownEngine()
        scheduleRestore()
        return lock.withLock { samples }
    }

    @MainActor
    private func tearDownEngine() {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Copy of the samples accumulated so far; safe to call while recording.
    func snapshotSamples() -> [Float] {
        lock.withLock { samples }
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

/// CoreAudio lookups for steering capture away from Bluetooth mics.
enum InputDeviceQuery {
    static func defaultID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    static func isBluetooth(_ deviceID: AudioDeviceID) -> Bool {
        guard let transport = transportType(of: deviceID) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// First built-in device with input streams, or nil on Macs without one.
    static func builtInID() -> AudioDeviceID? {
        allDevices().first { device in
            transportType(of: device) == kAudioDeviceTransportTypeBuiltIn && hasInput(device)
        }
    }

    static func setDefaultInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        ) == noErr
    }

    static func exists(_ deviceID: AudioDeviceID) -> Bool {
        allDevices().contains(deviceID)
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        var devices = [AudioDeviceID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices
    }

    private static func transportType(of deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr
        else { return nil }
        return transport
    }

    private static func hasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
        else { return false }
        return size > 0
    }
}
