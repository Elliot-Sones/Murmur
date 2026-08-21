import XCTest
@testable import Murmur

final class OllamaAPITests: XCTestCase {
    func testChatRequestBodyEncodesModelMessagesAndNoStreaming() throws {
        let body = OllamaAPI.chatRequestBody(
            model: "gemma4:latest",
            instructions: "clean transcripts",
            prompt: "Transcript:\nhello world"
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "gemma4:latest")
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "clean transcripts")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "Transcript:\nhello world")
    }

    func testParseChatResponseExtractsAssistantContent() {
        let data = Data(
            #"{"model":"gemma4","message":{"role":"assistant","content":"Hello there."},"done":true}"#.utf8
        )
        XCTAssertEqual(OllamaAPI.parseChatResponse(data), "Hello there.")
    }

    func testParseChatResponseReturnsNilOnGarbage() {
        XCTAssertNil(OllamaAPI.parseChatResponse(Data("not json".utf8)))
        XCTAssertNil(OllamaAPI.parseChatResponse(Data(#"{"message":{}}"#.utf8)))
    }

    func testParseTagsExtractsModelNames() {
        let data = Data(
            #"{"models":[{"name":"qwen3.6:35b-a3b-q8_0","size":1},{"name":"gemma4:latest","size":2}]}"#.utf8
        )
        XCTAssertEqual(OllamaAPI.parseTags(data), ["qwen3.6:35b-a3b-q8_0", "gemma4:latest"])
    }

    func testParseTagsReturnsEmptyOnGarbage() {
        XCTAssertEqual(OllamaAPI.parseTags(Data("nope".utf8)), [])
    }
}
