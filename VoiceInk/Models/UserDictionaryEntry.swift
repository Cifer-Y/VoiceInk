import Foundation

/// A user-defined vocabulary entry for improving transcription accuracy.
struct UserDictionaryEntry: Codable, Identifiable {
    var id: UUID
    var term: String

    init(id: UUID = UUID(), term: String) {
        self.id = id
        self.term = term
    }
}
