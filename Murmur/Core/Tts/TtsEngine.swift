import Foundation

/// Read-back voice engines, from zero-setup to server-backed expressive ones.
enum TtsEngineChoice: String, CaseIterable, Identifiable {
    /// AVSpeechSynthesizer; uses a trained Personal Voice when authorized.
    case system
    /// FluidAudio Kokoro-82M on the Neural Engine; models auto-download.
    case kokoro
    /// The same Kokoro family via the local mlx-audio server, which has
    /// all 28 English voices instead of the one CoreML pack.
    case kokoroServer
    /// Chatterbox via the local mlx-audio server.
    case chatterbox
    /// Qwen3-TTS via the local mlx-audio server.
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System voice (Personal Voice if trained)"
        case .kokoro: "Kokoro af_heart (built in, no server)"
        case .kokoroServer: "Kokoro, all voices (local server)"
        case .chatterbox: "Chatterbox (local server, expressive)"
        case .qwen: "Qwen3-TTS (local server, expressive)"
        }
    }

    /// Preset speakers of the Qwen3-TTS CustomVoice model. Ryan and Aiden
    /// are the English-tuned ones; the rest carry their own accents.
    static let qwenVoices = [
        "Ryan", "Aiden", "Vivian", "Serena", "Dylan", "Eric", "Uncle_Fu", "Ono_Anna", "Sohee",
    ]

    /// English voices of the full Kokoro model (a=American, b=British;
    /// f/m = female/male), best-graded first within each group.
    static let kokoroVoices = [
        "af_heart", "af_bella", "af_nicole", "af_aoede", "af_kore", "af_sarah",
        "af_alloy", "af_nova", "af_sky", "af_jessica", "af_river",
        "am_michael", "am_puck", "am_fenrir", "am_eric", "am_echo", "am_onyx",
        "am_liam", "am_adam", "am_santa",
        "bf_emma", "bf_isabella", "bf_alice", "bf_lily",
        "bm_george", "bm_fable", "bm_daniel", "bm_lewis",
    ]

    /// HuggingFace model id the local mlx-audio server should load,
    /// nil for engines that run inside the app.
    var serverModel: String? {
        switch self {
        case .system, .kokoro: nil
        case .kokoroServer: "mlx-community/Kokoro-82M-bf16"
        case .chatterbox: "mlx-community/chatterbox-turbo-8bit"
        case .qwen: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
        }
    }
}
