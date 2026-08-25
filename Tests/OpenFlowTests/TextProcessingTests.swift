import Foundation
import Testing
@testable import OpenFlow

@Suite("Text processing")
struct TextProcessingTests {
    private struct CapturedPayload: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    @Test("it(\"should drop the period at the end of every loose-style line\")")
    func looseStripsPeriods() {
        #expect(TextStyle.loose.finish("zrobiłem PR.\nczy to ok?\nmerge jutro. ") == "zrobiłem PR\nczy to ok?\nmerge jutro")
    }

    @Test("it(\"should keep an ellipsis in loose style\")")
    func looseKeepsEllipsis() {
        #expect(TextStyle.loose.finish("no nie wiem...") == "no nie wiem...")
    }

    @Test("it(\"should leave normal-style text untouched\")")
    func normalKeepsPeriods() {
        #expect(TextStyle.normal.finish("Done.\nNext.") == "Done.\nNext.")
    }

    @Test("it(\"should send a compatible chat request and trim its response\")")
    func chatCompletionRequest() async throws {
        var capturedRequest: URLRequest?
        let client = makeClient { request in
            capturedRequest = request
            let response = try makeHTTPResponse(for: request, statusCode: 200)
            let data = Data(#"{"choices":[{"message":{"content":"  cleaned text  "}}]}"#.utf8)
            return (data, response)
        }

        let result = try await client.complete(
            systemPrompt: "system rules",
            userContent: "raw text",
            temperature: 0.4
        )
        let payload = try JSONDecoder().decode(
            CapturedPayload.self,
            from: capturedRequest?.httpBody ?? Data()
        )

        #expect(
            result == "cleaned text"
                && capturedRequest?.url?.absoluteString == "https://example.com/v1/chat/completions"
                && capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
                && capturedRequest?.timeoutInterval == 7
                && payload.model == "test-model"
                && payload.messages.map(\.role) == ["system", "user"]
                && payload.messages.map(\.content) == ["system rules", "raw text"]
                && payload.temperature == 0.4
                && payload.stream == false
        )
    }

    @Test("it(\"should expose the provider status and body for HTTP failures\")")
    func chatCompletionHTTPError() async {
        let client = makeClient { request in
            let response = try makeHTTPResponse(for: request, statusCode: 429)
            return (Data("slow down".utf8), response)
        }

        let message: String
        do {
            _ = try await client.complete(systemPrompt: "system", userContent: "text", temperature: 0)
            message = "request unexpectedly succeeded"
        } catch {
            message = error.localizedDescription
        }
        #expect(message == "The API returned error 429: slow down")
    }

    @Test("it(\"should reject a successful response without message content\")")
    func chatCompletionEmptyResponse() async {
        let client = makeClient { request in
            let response = try makeHTTPResponse(for: request, statusCode: 200)
            return (Data(#"{"choices":[]}"#.utf8), response)
        }

        let message: String
        do {
            _ = try await client.complete(systemPrompt: "system", userContent: "text", temperature: 0)
            message = "request unexpectedly succeeded"
        } catch {
            message = error.localizedDescription
        }
        #expect(message == "The API returned an empty response.")
    }

    private func makeClient(
        dataLoader: @escaping ChatCompletionClient.DataLoader
    ) -> ChatCompletionClient {
        ChatCompletionClient(
            configuration: .init(
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "secret",
                timeout: 7
            ),
            dataLoader: dataLoader
        )
    }
}
