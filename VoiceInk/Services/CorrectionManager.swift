import Foundation

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
            print("Failed to load corrections: \(error)")
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
            print("Failed to save corrections: \(error)")
        }
    }
}
