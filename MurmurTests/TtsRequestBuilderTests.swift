import XCTest
@testable import Murmur

final class TtsRequestBuilderTests: XCTestCase {
    private func body(of request: URLRequest) throws -> [String: String] {
        guard let data = request.httpBody else {
            XCTFail("expected a request body")
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    func testBuildsSpeechRequestAgainstLocalServer() throws {
        let request = try XCTUnwrap(
            TtsRequestBuilder.speechRequest(engine: .kokoroServer, text: "Hello there", voice: "bm_fable")
        )
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/v1/audio/speech")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try body(of: request)
        XCTAssertEqual(json["model"], "mlx-community/Kokoro-82M-bf16")
        XCTAssertEqual(json["input"], "Hello there")
        XCTAssertEqual(json["voice"], "bm_fable")
        XCTAssertEqual(
            json["response_format"], "wav",
            "mp3 needs ffmpeg, which launchd's PATH does not have; wav needs nothing"
        )
    }

    func testOmitsEmptyVoice() throws {
        let request = try XCTUnwrap(
            TtsRequestBuilder.speechRequest(engine: .kokoroServer, text: "Hi", voice: "")
        )
        let json = try body(of: request)
        XCTAssertNil(json["voice"], "an empty voice must be left to the server default")
    }

    func testNativeEngineProducesNoServerRequest() {
        XCTAssertNil(TtsRequestBuilder.speechRequest(engine: .kokoro, text: "Hi", voice: ""))
    }
}
