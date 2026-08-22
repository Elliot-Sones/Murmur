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
            TtsRequestBuilder.speechRequest(engine: .qwen, text: "Hello there", voice: "Vivian")
        )
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/v1/audio/speech")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try body(of: request)
        XCTAssertEqual(json["model"], "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit")
        XCTAssertEqual(json["input"], "Hello there")
        XCTAssertEqual(json["voice"], "Vivian")
    }

    func testOmitsEmptyVoice() throws {
        let request = try XCTUnwrap(
            TtsRequestBuilder.speechRequest(engine: .chatterbox, text: "Hi", voice: "")
        )
        let json = try body(of: request)
        XCTAssertEqual(json["model"], "mlx-community/chatterbox-turbo-8bit")
        XCTAssertNil(json["voice"], "an empty voice must be left to the server default")
    }

    func testNativeEnginesProduceNoServerRequest() {
        XCTAssertNil(TtsRequestBuilder.speechRequest(engine: .system, text: "Hi", voice: ""))
        XCTAssertNil(TtsRequestBuilder.speechRequest(engine: .kokoro, text: "Hi", voice: ""))
    }
}
