import Foundation

/// Shared transport for the OpenAI-compatible text endpoint used by cleanup
/// and translation. Feature services own their prompts; this type owns HTTP,
/// encoding, response validation and provider errors.
struct ChatCompletionClient {
    struct Configuration {
        var baseURL: String
        var model: String
        var apiKey: String
        var timeout: TimeInterval
    }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case badURL
        case http(status: Int, body: String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "The API key is missing."
            case .badURL:
                return "The API address is invalid."
            case .http(let status, let body):
                return "The API returned error \(status): \(body.prefix(200))"
            case .emptyResponse:
                return "The API returned an empty response."
            }
        }
    }

    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    let configuration: Configuration
    private let dataLoader: DataLoader

    init(
        configuration: Configuration,
        dataLoader: @escaping DataLoader = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.dataLoader = dataLoader
    }

    func complete(
        systemPrompt: String,
        userContent: String,
        temperature: Double
    ) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw ClientError.missingAPIKey }
        guard let url = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespaces))?
            .appendingPathComponent("chat/completions")
        else { throw ClientError.badURL }

        let payload = ChatRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent),
            ],
            temperature: temperature,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await dataLoader(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw ClientError.emptyResponse }
        return content
    }
}
