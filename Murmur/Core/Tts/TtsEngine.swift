import Foundation

/// The two Kokoro providers: the built-in af_heart voice on the Neural
/// Engine, and the full-voice-list copy behind the local mlx-audio server.
enum TtsEngineChoice: String, CaseIterable, Identifiable {
    /// FluidAudio Kokoro-82M on the Neural Engine; af_heart only, no server.
    case kokoro
    /// The same Kokoro family via the local mlx-audio server, which has
    /// all 28 English voices instead of the one CoreML pack.
    case kokoroServer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kokoro: "Heart (built in, no server)"
        case .kokoroServer: "Any Kokoro voice (local server)"
        }
    }

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
    /// nil for the in-app engine.
    var serverModel: String? {
        switch self {
        case .kokoro: nil
        case .kokoroServer: "mlx-community/Kokoro-82M-bf16"
        }
    }
}
