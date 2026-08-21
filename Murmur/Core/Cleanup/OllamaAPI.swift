import Foundation

/// Request and response shapes for a local Ollama server. Pure functions,
/// no networking here.
enum OllamaAPI {
    static let baseURL = URL(string: "http://localhost:11434")!

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]
    }

    static func chatRequestBody(model: String, instructions: String, prompt: String) -> Data {
        let request = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: prompt),
            ],
            stream: false,
            options: .init(temperature: 0.2)
        )
        return (try? JSONEncoder().encode(request)) ?? Data()
    }

    static func parseChatResponse(_ data: Data) -> String? {
        try? JSONDecoder().decode(ChatResponse.self, from: data).message.content
    }

    static func parseTags(_ data: Data) -> [String] {
        ((try? JSONDecoder().decode(TagsResponse.self, from: data))?.models.map(\.name)) ?? []
    }
}
