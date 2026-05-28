import Foundation

/// A single Whisper token with its recognition confidence.
struct AnnotatedToken {
    let text: String
    let probability: Float
}

/// Whisper transcription result with per-token confidence scores.
/// Used to tell the LLM which words Whisper was uncertain about.
struct AnnotatedTranscription {
    let tokens: [AnnotatedToken]

    /// Plain text for display (no annotations).
    var text: String {
        tokens.map(\.text).joined()
    }

    /// Text with low-confidence tokens annotated for LLM consumption.
    /// Format: "正确词{可疑词|0.3}正确词"
    /// Tokens above the threshold are left as-is.
    func annotatedText(threshold: Float = 0.5) -> String {
        guard hasLowConfidenceTokens(threshold: threshold) else { return text }

        return tokens.map { token in
            let trimmed = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return token.text }
            if token.probability < threshold {
                return "{\(token.text)|\(String(format: "%.1f", token.probability))}"
            }
            return token.text
        }.joined()
    }

    /// Average confidence across all non-whitespace tokens.
    var averageConfidence: Float {
        let meaningful = tokens.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !meaningful.isEmpty else { return 1.0 }
        return meaningful.map(\.probability).reduce(0, +) / Float(meaningful.count)
    }

    func hasLowConfidenceTokens(threshold: Float = 0.5) -> Bool {
        tokens.contains { $0.probability < threshold }
    }

    /// Trims trailing hallucinated tokens. Whisper often appends garbage (e.g. video
    /// watermarks) when audio trails off into silence — these have near-zero probability.
    /// Strips from the end while probability < threshold, then trims trailing whitespace.
    func trimmingTrailingHallucinations(threshold: Float = 0.1) -> AnnotatedTranscription {
        var trimmed = tokens
        while let last = trimmed.last {
            let t = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { trimmed.removeLast(); continue }
            if last.probability < threshold { trimmed.removeLast() } else { break }
        }
        // Also trim trailing whitespace tokens
        while let last = trimmed.last,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            trimmed.removeLast()
        }
        return AnnotatedTranscription(tokens: trimmed)
    }

    /// Creates a plain transcription with no confidence data (e.g. from Apple Speech).
    static func plain(_ text: String) -> AnnotatedTranscription {
        AnnotatedTranscription(tokens: [AnnotatedToken(text: text, probability: 1.0)])
    }
}
