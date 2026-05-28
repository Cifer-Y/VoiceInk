import Foundation
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "LLM")

/// OpenAI-compatible API client for speech recognition error correction.
final class LLMService {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isShortSentenceEnabled: Bool {
        settings.llmEnabled && settings.shortSentenceConfig.isConfigured
    }

    var isComposingEnabled: Bool {
        settings.composingLLMEnabled && settings.composingConfig.isConfigured
    }

    /// Refines transcription text using LLM (short sentence mode).
    /// When `annotatedText` is provided (from Whisper confidence data), it is sent to the LLM
    /// so low-confidence words are highlighted for targeted correction.
    func refine(text: String, annotatedText: String? = nil, examples: [CorrectionEntry], dictionarySnippet: String = "", previousContext: String = "", activeApp: String? = nil) async throws -> String {
        let config = settings.shortSentenceConfig
        guard isShortSentenceEnabled else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let systemPrompt = buildSystemPrompt(examples: examples, dictionarySnippet: dictionarySnippet, previousContext: previousContext, activeApp: activeApp)
        let userContent = annotatedText ?? text
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent],
        ]

        // Reasoning models (o-series / GPT-5) reject custom temperature; non-reasoning
        // models (e.g. gpt-4o) reject reasoning_effort. Send exactly one.
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
        ]
        if config.reasoningEffort.isEmpty {
            body["temperature"] = 0.3
        } else {
            body["reasoning_effort"] = config.reasoningEffort
        }

        logger.info("[short] ASR input: \(text, privacy: .public)")
        let content = try await sendRequest(body: body, config: config, timeout: 15)

        let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Safety: reject outputs that are too long (likely hallucination)
        if refined.count > text.count * 3 {
            logger.warning("[short] LLM output rejected (too long): \(refined, privacy: .public)")
            return text
        }
        logger.info("[short] LLM output: \(refined, privacy: .public)")
        return refined
    }

    /// Refines long-text composing mode output.
    /// When `annotatedText` is provided, low-confidence words are highlighted for the LLM.
    func refineComposing(text: String, annotatedText: String? = nil) async throws -> String {
        let config = settings.composingConfig
        guard isComposingEnabled else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let userContent = annotatedText ?? text
        let messages: [[String: String]] = [
            ["role": "system", "content": Constants.llmComposingPrompt],
            ["role": "user", "content": userContent],
        ]

        // Reasoning models (o-series / GPT-5) reject custom temperature; non-reasoning
        // models (e.g. gpt-4o) reject reasoning_effort. Send exactly one.
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
        ]
        if config.reasoningEffort.isEmpty {
            body["temperature"] = 0.3
        } else {
            body["reasoning_effort"] = config.reasoningEffort
        }

        logger.info("[composing] ASR input: \(text, privacy: .public)")
        let result = try await sendRequest(body: body, config: config, timeout: 30)
        logger.info("[composing] LLM output: \(result, privacy: .public)")
        return result
    }

    /// Tests API connectivity with a simple request.
    func testConnection(config: LLMConfig) async throws -> Bool {
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        do {
            _ = try await sendRequest(body: body, config: config, timeout: 15)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Network

    /// Sends a request to the OpenAI-compatible API. Retries once on 503.
    private func sendRequest(body: [String: Any], config: LLMConfig, timeout: TimeInterval, retryCount: Int = 1) async throws -> String {
        let baseURL = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        // Disable thinking for local Ollama models (e.g. Gemma 4)
        var body = body
        if config.baseURL.contains("localhost") || config.baseURL.contains("127.0.0.1") {
            body["think"] = false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        // Retry on 503 (server overloaded)
        if httpResponse.statusCode == 503 && retryCount > 0 {
            logger.warning("503 from LLM, retrying in 1s")
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            return try await sendRequest(body: body, config: config, timeout: timeout, retryCount: retryCount - 1)
        }

        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode
            logger.error("LLM request failed: HTTP \(statusCode)")
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

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("LLM \(config.model, privacy: .public) done in \(String(format: "%.1f", elapsed * 1000), privacy: .public)ms — \(result, privacy: .public)")
        return result
    }

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(examples: [CorrectionEntry], dictionarySnippet: String = "", previousContext: String = "", activeApp: String? = nil) -> String {
        var prompt = Constants.llmSystemPrompt

        if let app = activeApp, !app.isEmpty {
            prompt += "\n\nUser is currently in: \(app). Use this to disambiguate domain-specific terms."
        }

        if !dictionarySnippet.isEmpty {
            prompt += dictionarySnippet
        }

        if !previousContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nRecent context (previously dictated text, use for disambiguation):\n\(previousContext)"
        }

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
