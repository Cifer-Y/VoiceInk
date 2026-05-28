import Foundation
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "UserDictionary")

/// Manages user-defined vocabulary for improving transcription accuracy.
/// Two integration points: Whisper initial_prompt and LLM prompt injection.
final class UserDictionaryManager {
    private(set) var entries: [UserDictionaryEntry] = []
    private let filePath: URL

    init() {
        self.filePath = Constants.userDictionaryFilePath
        load()
    }

    // MARK: - CRUD

    func add(entry: UserDictionaryEntry) {
        entries.append(entry)
        save()
    }

    func update(entry: UserDictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    // MARK: - Whisper Initial Prompt

    /// Builds a prompt string containing all dictionary terms for Whisper's initial_prompt.
    /// Whisper uses this to bias its decoder toward these words.
    /// Max entries for whisper initial_prompt (~224 token limit, avoid dilution).
    private static let whisperMaxTerms = 50

    func whisperPrompt() -> String {
        let terms = entries.prefix(Self.whisperMaxTerms).map(\.term)
        guard !terms.isEmpty else { return "" }
        return terms.joined(separator: ", ")
    }

    // MARK: - LLM Prompt Snippet

    /// Builds a snippet to inject into the LLM system prompt.
    func llmPromptSnippet() -> String {
        guard !entries.isEmpty else { return "" }

        let terms = entries.map { "- \($0.term)" }
        return "\nUser's custom vocabulary (always prefer these terms):\n" + terms.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        do {
            let data = try Data(contentsOf: filePath)
            entries = try JSONDecoder().decode([UserDictionaryEntry].self, from: data)
        } catch {
            logger.error("Failed to load: \(error)")
            entries = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: filePath, options: .atomic)
        } catch {
            logger.error("Failed to save: \(error)")
        }
    }
}
