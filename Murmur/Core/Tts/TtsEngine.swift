import Foundation

/// Read-back voice engines, from zero-setup to server-backed expressive ones.
enum TtsEngineChoice: String, CaseIterable, Identifiable {
    /// AVSpeechSynthesizer; uses a trained Personal Voice when authorized.
    case system
    /// FluidAudio Kokoro-82M on the Neural Engine; models auto-download.
    case kokoro
    /// Chatterbox via the local mlx-audio server.
    case chatterbox
    /// Qwen3-TTS via the local mlx-audio server.
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System voice (Personal Voice if trained)"
        case .kokoro: "Kokoro (on-device, Neural Engine)"
        case .chatterbox: "Chatterbox (local server, expressive)"
        case .qwen: "Qwen3-TTS (local server, expressive)"
        }
    }

    /// HuggingFace model id the local mlx-audio server should load,
    /// nil for engines that run inside the app.
    var serverModel: String? {
        switch self {
        case .system, .kokoro: nil
        case .chatterbox: "mlx-community/chatterbox-turbo-8bit"
        case .qwen: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
        }
    }
}
