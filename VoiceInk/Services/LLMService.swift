import Foundation

/// OpenAI-compatible API client for speech recognition error correction.
final class LLMService {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isEnabled: Bool {
        settings.llmEnabled && settings.isLLMConfigured
    }

    /// Refines transcription text using LLM.
    func refine(text: String, examples: [CorrectionEntry]) async throws -> String {
        guard isEnabled else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let systemPrompt = buildSystemPrompt(examples: examples)
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text],
        ]

        var body: [String: Any] = [
            "model": settings.llmModel,
            "messages": messages,
            "temperature": 0.3,
        ]
        if !settings.reasoningEffort.isEmpty {
            body["reasoning_effort"] = settings.reasoningEffort
        }

        let content = try await sendRequest(body: body, timeout: 15)

        let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Safety: reject outputs that are too long (likely hallucination)
        if refined.count > text.count * 3 {
            return text
        }
        return refined
    }

    /// Refines long-text composing mode output.
    func refineComposing(text: String) async throws -> String {
        guard isEnabled else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let model = settings.composingModel.isEmpty ? settings.llmModel : settings.composingModel

        let messages: [[String: String]] = [
            ["role": "system", "content": Constants.llmComposingPrompt],
            ["role": "user", "content": text],
        ]

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3,
        ]
        if !settings.composingReasoningEffort.isEmpty {
            body["reasoning_effort"] = settings.composingReasoningEffort
        }

        return try await sendRequest(body: body, timeout: 30)
    }

    /// Tests API connectivity with a simple request.
    func testConnection() async throws -> Bool {
        let body: [String: Any] = [
            "model": settings.llmModel,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        do {
            _ = try await sendRequest(body: body, timeout: 15)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Network

    /// Sends a request to the OpenAI-compatible API. Retries once on 503.
    private func sendRequest(body: [String: Any], timeout: TimeInterval, retryCount: Int = 1) async throws -> String {
        let baseURL = settings.llmBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        // Retry on 503 (server overloaded)
        if httpResponse.statusCode == 503 && retryCount > 0 {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            return try await sendRequest(body: body, timeout: timeout, retryCount: retryCount - 1)
        }

        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode
            if statusCode == 429 || statusCode == 403 {
                throw LLMError.rateLimited
            }
            throw LLMError.apiError(statusCode: statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(examples: [CorrectionEntry]) -> String {
        var prompt = Constants.llmSystemPrompt

        if !examples.isEmpty {
            prompt += "\n\nHere are examples of past corrections to guide your refinement:\n"
            for example in examples {
                let asrPart = example.asrText
                let correctedPart = example.correctedText
                if let llmText = example.llmText, !llmText.isEmpty {
                    prompt += "- ASR: \"\(asrPart)\" → LLM: \"\(llmText)\" → Correct: \"\(correctedPart)\"\n"
                } else {
                    prompt += "- ASR: \"\(asrPart)\" → Correct: \"\(correctedPart)\"\n"
                }
            }
        }

        return prompt
    }
}

enum LLMError: LocalizedError, Equatable {
    case invalidURL
    case apiError(statusCode: Int)
    case rateLimited
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API base URL."
        case .apiError(let code):
            return "API error (HTTP \(code))."
        case .rateLimited:
            return "API quota exceeded. Free tier limit reached."
        case .invalidResponse:
            return "Invalid response from API."
        }
    }
}
