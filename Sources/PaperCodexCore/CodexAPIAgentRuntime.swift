import Foundation

public enum CodexAPIEndpoint: String, Codable, Equatable, Sendable {
    case chatCompletions = "chat_completions"
    case responses
}

public struct CodexAPIConfiguration: Equatable, Sendable {
    public static let baseURLEnvironmentKey = "PAPER_CODEX_CODEX_API_BASE_URL"
    public static let apiKeyEnvironmentKey = "PAPER_CODEX_CODEX_API_KEY"
    public static let modelEnvironmentKey = "PAPER_CODEX_CODEX_API_MODEL"
    public static let endpointEnvironmentKey = "PAPER_CODEX_CODEX_API_ENDPOINT"

    public var baseURL: URL
    public var apiKey: String?
    public var model: String
    public var endpoint: CodexAPIEndpoint

    public init(baseURL: URL, apiKey: String?, model: String, endpoint: CodexAPIEndpoint = .chatCompletions) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> CodexAPIConfiguration? {
        guard let rawBaseURL = environment[baseURLEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawBaseURL.isEmpty,
              let baseURL = URL(string: rawBaseURL) else {
            return nil
        }
        let apiKey = environment[apiKeyEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = environment[modelEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointRawValue = environment[endpointEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexAPIConfiguration(
            baseURL: baseURL,
            apiKey: apiKey?.isEmpty == true ? nil : apiKey,
            model: model?.isEmpty == false ? model! : "gpt-5.5",
            endpoint: endpointRawValue.flatMap(CodexAPIEndpoint.init(rawValue:)) ?? .chatCompletions
        )
    }
}

public enum CodexAPIError: Error, CustomStringConvertible, Equatable {
    case invalidRequest
    case invalidResponse(String)
    case httpFailure(status: Int, body: String)

    public var description: String {
        switch self {
        case .invalidRequest:
            "Could not build Codex API request"
        case let .invalidResponse(message):
            "Could not parse Codex API response: \(message)"
        case let .httpFailure(status, body):
            "Codex API request failed with status \(status): \(body)"
        }
    }
}

public struct CodexAPIAgentRuntime: AgentRuntime {
    private let configuration: CodexAPIConfiguration
    private let urlSession: URLSession

    public init(configuration: CodexAPIConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func runCodexTurn(
        _ request: AgentRuntimeRequest,
        runHandle: CodexRunHandle,
        onEvent: @escaping @Sendable (CodexRunEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        onEvent(CodexRunEvent(kind: .status, title: "Codex API", detail: "Sending request to \(configuration.baseURL.absoluteString)"))
        let body: Data
        let url: URL
        switch configuration.endpoint {
        case .chatCompletions:
            body = try makeChatCompletionsRequestBody(
                prompt: request.prompt,
                imageAttachments: request.imageAttachments,
                modelOverride: request.modelOverride
            )
            url = endpointURL(path: "chat/completions")
        case .responses:
            body = try makeResponsesRequestBody(
                prompt: request.prompt,
                imageAttachments: request.imageAttachments,
                modelOverride: request.modelOverride
            )
            url = endpointURL(path: "responses")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: urlRequest)
        try Task.checkCancellation()
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CodexAPIError.httpFailure(
                status: httpResponse.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        let result = try parseResponse(data: data)
        if let tokenUsage = result.tokenUsage {
            onEvent(CodexRunEvent(kind: .usage, title: "Token usage", detail: tokenUsage.compactSummary, tokenUsage: tokenUsage))
        }
        onEvent(CodexRunEvent(kind: .answer, title: "Answer", detail: result.lastMessage))
        return result
    }

    public func makeChatCompletionsRequestBody(
        prompt: String,
        imageAttachments: [PromptImageAttachment] = [],
        modelOverride: String? = nil
    ) throws -> Data {
        let model = normalizedModelOverride(modelOverride) ?? configuration.model
        let content: Any
        if imageAttachments.isEmpty {
            content = prompt
        } else {
            content = try chatCompletionsContent(prompt: prompt, imageAttachments: imageAttachments)
        }
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CodexAPIError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public func makeResponsesRequestBody(
        prompt: String,
        imageAttachments: [PromptImageAttachment] = [],
        modelOverride: String? = nil
    ) throws -> Data {
        let model = normalizedModelOverride(modelOverride) ?? configuration.model
        let input: Any
        if imageAttachments.isEmpty {
            input = prompt
        } else {
            input = try responsesInput(prompt: prompt, imageAttachments: imageAttachments)
        }
        let payload: [String: Any] = [
            "model": model,
            "input": input
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw CodexAPIError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public func parseResponse(data: Data) throws -> AgentRuntimeResult {
        let stdout = String(decoding: data, as: UTF8.self)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAPIError.invalidResponse("top-level response was not an object")
        }
        if let error = json["error"] {
            throw CodexAPIError.invalidResponse(Self.compactJSONString(error) ?? String(describing: error))
        }
        let lastMessage = Self.chatCompletionsMessage(in: json)
            ?? Self.responsesMessage(in: json)
        guard let lastMessage, !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexAPIError.invalidResponse("missing assistant message")
        }
        return AgentRuntimeResult(
            stdout: stdout,
            lastMessage: lastMessage,
            threadID: json["id"] as? String,
            generatedImages: [],
            tokenUsage: Self.tokenUsage(in: json)
        )
    }

    private func endpointURL(path: String) -> URL {
        configuration.baseURL.appendingPathComponent(path)
    }

    private func normalizedModelOverride(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func chatCompletionsContent(
        prompt: String,
        imageAttachments: [PromptImageAttachment]
    ) throws -> [[String: Any]] {
        var content: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt
            ]
        ]
        for attachment in imageAttachments {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": try dataURL(for: attachment)
                ]
            ])
        }
        return content
    }

    private func responsesInput(
        prompt: String,
        imageAttachments: [PromptImageAttachment]
    ) throws -> [[String: Any]] {
        var content: [[String: Any]] = [
            [
                "type": "input_text",
                "text": prompt
            ]
        ]
        for attachment in imageAttachments {
            content.append([
                "type": "input_image",
                "image_url": try dataURL(for: attachment)
            ])
        }
        return [
            [
                "role": "user",
                "content": content
            ]
        ]
    }

    private func dataURL(for attachment: PromptImageAttachment) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: attachment.path))
        let mimeType = attachment.mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.mimeType(forPathExtension: URL(fileURLWithPath: attachment.path).pathExtension)
            : attachment.mimeType
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func mimeType(forPathExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }

    private static func chatCompletionsMessage(in json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]] else {
            return nil
        }
        for choice in choices {
            if let message = choice["message"] as? [String: Any],
               let content = stringContent(message["content"]) {
                return content
            }
            if let text = choice["text"] as? String {
                return text
            }
        }
        return nil
    }

    private static func responsesMessage(in json: [String: Any]) -> String? {
        if let outputText = json["output_text"] as? String {
            return outputText
        }
        guard let output = json["output"] as? [[String: Any]] else {
            return nil
        }
        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }
            for contentItem in content {
                if let text = contentItem["text"] as? String {
                    parts.append(text)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func stringContent(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let parts = value as? [[String: Any]] {
            return parts.compactMap { part in
                part["text"] as? String
            }.joined(separator: "\n")
        }
        return nil
    }

    private static func tokenUsage(in json: [String: Any]) -> CodexTokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else {
            return nil
        }
        let tokenUsage = CodexTokenUsage(
            inputTokens: integerValue(named: "input_tokens", in: usage)
                + integerValue(named: "prompt_tokens", in: usage),
            cachedInputTokens: integerValue(named: "cached_input_tokens", in: usage),
            outputTokens: integerValue(named: "output_tokens", in: usage)
                + integerValue(named: "completion_tokens", in: usage),
            reasoningOutputTokens: integerValue(named: "reasoning_output_tokens", in: usage)
        )
        return tokenUsage.isEmpty ? nil : tokenUsage
    }

    private static func integerValue(named key: String, in value: [String: Any]) -> Int {
        if let int = value[key] as? Int {
            return int
        }
        if let double = value[key] as? Double {
            return Int(double)
        }
        if let string = value[key] as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    private static func compactJSONString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum AgentRuntimeFactory {
    public static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> any AgentRuntime {
        if let configuration = CodexAPIConfiguration.fromEnvironment(environment) {
            return CodexAPIAgentRuntime(configuration: configuration)
        }
        return CodexAgentRuntime()
    }
}
