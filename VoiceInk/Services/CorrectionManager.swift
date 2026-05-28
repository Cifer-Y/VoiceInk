import Foundation
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "Corrections")

/// Manages user correction history for LLM few-shot learning.
/// Stored as JSON at ~/Library/Application Support/VoiceInk/corrections.json.
final class CorrectionManager {
    private(set) var entries: [CorrectionEntry] = []
    private let filePath: URL

    init() {
        self.filePath = Constants.correctionsFilePath
        load()
    }

    // MARK: - CRUD

    func add(entry: CorrectionEntry) {
        entries.append(entry)

        // FIFO: keep only the most recent entries
        if entries.count > Constants.maxCorrectionEntries {
            entries = Array(entries.suffix(Constants.maxCorrectionEntries))
        }

        save()
    }

    func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        save()
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Few-Shot Selection

    /// Selects the most relevant correction examples for LLM few-shot prompting.
    /// Uses bigram similarity to find examples closest to the input text.
    func selectExamples(for text: String, maxCount: Int = 8) -> [CorrectionEntry] {
        guard !entries.isEmpty else { return [] }

        let inputBigrams = bigrams(text)
        guard !inputBigrams.isEmpty else { return Array(entries.suffix(maxCount)) }

        // Score each entry by bigram similarity
        var scored: [(entry: CorrectionEntry, score: Double)] = entries.map { entry in
            let entryBigrams = bigrams(entry.asrText)
            let score = bigramSimilarity(inputBigrams, entryBigrams)
            return (entry, score)
        }

        // Sort by similarity (highest first), then take top entries
        scored.sort { $0.score > $1.score }
        let selected = scored.prefix(maxCount).map(\.entry)
        return Array(selected)
    }

    // MARK: - Whisper Prompt Terms

    /// Extracts words that Whisper frequently gets wrong, returning the correct versions.
    /// Diffs ASR vs corrected text character-by-character to find the specific changed words,
    /// not entire sentences. These bias Whisper's decoder toward the right vocabulary.
    func whisperPromptTerms(maxCount: Int = 30) -> [String] {
        var freq: [String: Int] = [:]
        for entry in entries {
            let asrChars = Array(entry.asrText)
            let corrChars = Array(entry.correctedText)
            // Extract changed segments from the corrected text
            for word in extractChangedWords(from: asrChars, to: corrChars) {
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                guard trimmed.count >= 2, trimmed.count <= 20 else { continue }
                freq[trimmed, default: 0] += 1
            }
        }
        return freq.sorted { $0.value > $1.value }.prefix(maxCount).map(\.key)
    }

    /// Simple character-level diff: finds contiguous runs of characters in `to` that differ from `from`.
    private func extractChangedWords(from src: [Character], to dst: [Character]) -> [String] {
        // Build longest common subsequence table
        let m = src.count, n = dst.count
        guard m > 0 && n > 0 else { return [] }

        // Space-optimized LCS: only need previous and current row
        var prev = [Int](repeating: 0, count: n + 1)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            for j in 1...n {
                if src[i - 1] == dst[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j - 1])
                }
            }
            prev = curr
            curr = [Int](repeating: 0, count: n + 1)
        }

        // Backtrack to find which dst characters are NOT in LCS (i.e., changed/added)
        var inLCS = [Bool](repeating: false, count: n)
        var i = m, j = n
        // Rebuild full table for backtracking (use prev rows array)
        var table = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if src[i - 1] == dst[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        i = m; j = n
        while i > 0 && j > 0 {
            if src[i - 1] == dst[j - 1] {
                inLCS[j - 1] = true
                i -= 1; j -= 1
            } else if table[i - 1][j] > table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        // Collect contiguous runs of non-LCS characters as "changed words"
        var results: [String] = []
        var current = ""
        for k in 0..<n {
            if !inLCS[k] {
                current.append(dst[k])
            } else if !current.isEmpty {
                results.append(current)
                current = ""
            }
        }
        if !current.isEmpty { results.append(current) }
        return results
    }

    // MARK: - Bigram Similarity

    private func bigrams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 2 else { return Set() }
        var result = Set<String>()
        for i in 0..<(chars.count - 1) {
            result.insert(String(chars[i]) + String(chars[i + 1]))
        }
        return result
    }

    private func bigramSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([CorrectionEntry].self, from: data)
        } catch {
            logger.error("Failed to load: \(error)")
            entries = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: filePath, options: .atomic)
        } catch {
            logger.error("Failed to save: \(error)")
        }
    }
}
