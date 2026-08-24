import AVFoundation
import ScreenCaptureKit
import os

/// Captures all system output audio (the other side of a call) via
/// ScreenCaptureKit and delivers 16 kHz mono Float32 chunks. Works with any
/// output route including headphones: SCK taps the OS mixing layer, not the
/// physical output. Requires the Screen Recording permission.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting-audio")
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.elliot.Murmur.system-audio")
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    /// Called off the main thread with each converted 16 kHz mono chunk.
    var onSamples: (@Sendable ([Float]) -> Void)?
    /// Called once if the stream dies mid-meeting (device sleep, TCC revoked).
    var onFailure: (@Sendable (String) -> Void)?

    /// True when the Screen Recording permission has been granted.
    static func permissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt (or opens System Settings when
    /// previously denied). Returns whether access is currently granted.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw NSError(
                domain: "Murmur.meeting", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display available for audio capture"]
            )
        }
        // Audio-only: exclude our own process so Murmur's cues don't loop in.
        let excluded = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display, excludingApplications: excluded, exceptingWindows: []
        )
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Video is mandatory in the API; keep it as cheap as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        log.notice("system audio capture started")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        log.notice("system audio capture stopped")
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        guard let chunk = convert(pcm) else { return }
        if !chunk.isEmpty { onSamples?(chunk) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("system audio stream stopped: \(error, privacy: .public)")
        onFailure?(error.localizedDescription)
    }

    // MARK: - Conversion

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        if converter == nil || converterFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converterFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return nil }
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
        guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return nil }
        let count = Int(converted.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }

    /// SCK hands audio as CMSampleBuffer; rewrap as AVAudioPCMBuffer.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
            let streamDescription = formatDescription.audioStreamBasicDescription
        else { return nil }
        var asbd = streamDescription
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0,
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcm
    }
}
