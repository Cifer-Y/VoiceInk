import Foundation
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "Transcription")

/// OpenAI-compatible speech-to-text client (`/audio/transcriptions`).
/// Uploads a 16kHz mono WAV and returns plain text. The OpenAI audio API does not
/// expose per-token confidence, so results carry no annotations (probability 1.0).
final class OpenAITranscriptionService {

    enum TranscriptionError: LocalizedError {
        case invalidURL
        case audioReadFailed
        case apiError(statusCode: Int)
        case rateLimited
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid transcription API base URL."
            case .audioReadFailed: return "Failed to read recorded audio."
            case .apiError(let code): return "Transcription API error (HTTP \(code))."
            case .rateLimited: return "Transcription API quota exceeded."
            case .invalidResponse: return "Invalid response from transcription API."
            }
        }
    }

    /// Transcribes a WAV file via the OpenAI audio API.
    /// - Parameters:
    ///   - audioURL: 16kHz mono WAV file.
    ///   - language: Locale string (e.g. "zh-CN"); mapped to ISO-639-1.
    ///   - prompt: Optional vocabulary-biasing prompt (OpenAI `prompt` parameter).
    ///   - config: API endpoint, key, and transcription model.
    func transcribe(audioURL: URL, language: String, prompt: String = "", config: TranscriptionConfig) async throws -> AnnotatedTranscription {
        let baseURL = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else {
            throw TranscriptionError.invalidURL
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError.audioReadFailed
        }

        var fields: [String: String] = [
            "model": config.model,
            "response_format": "json",
        ]
        let lang = String(language.prefix(2))
        if !lang.isEmpty { fields["language"] = lang }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty { fields["prompt"] = trimmedPrompt }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: fields,
            fileField: "file",
            fileName: "audio.wav",
            fileMimeType: "audio/wav",
            fileData: audioData
        )

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard http.statusCode == 200 else {
            logger.error("Transcription failed: HTTP \(http.statusCode)")
            if http.statusCode == 429 || http.statusCode == 403 { throw TranscriptionError.rateLimited }
            throw TranscriptionError.apiError(statusCode: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TranscriptionError.invalidResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Transcribed (\(config.model, privacy: .public)) in \(String(format: "%.0f", elapsed * 1000))ms: \(trimmed, privacy: .public)")
        return .plain(trimmed)
    }

    /// Verifies API credentials by listing models.
    func testConnection(config: TranscriptionConfig) async throws -> Bool {
        let baseURL = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/models") else { throw TranscriptionError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Multipart

    private static func multipartBody(boundary: String, fields: [String: String], fileField: String, fileName: String, fileMimeType: String, fileData: Data) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for (key, value) in fields {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(fileMimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
