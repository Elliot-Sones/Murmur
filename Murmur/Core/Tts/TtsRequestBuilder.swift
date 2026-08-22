import Foundation

/// Builds requests for the local mlx-audio server (OpenAI speech API shape).
enum TtsRequestBuilder {
    static let serverURL = URL(string: "http://localhost:8000/v1/audio/speech")!

    /// nil for engines that synthesize inside the app.
    static func speechRequest(
        engine: TtsEngineChoice, text: String, voice: String
    ) -> URLRequest? {
        guard let model = engine.serverModel else { return nil }
        // wav: mp3 encoding needs ffmpeg, which the LaunchAgent's PATH lacks.
        var body: [String: String] = ["model": model, "input": text, "response_format": "wav"]
        if !voice.isEmpty {
            body["voice"] = voice
        }
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        return request
    }
}
