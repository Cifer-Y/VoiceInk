import Foundation

struct CorrectionEntry: Codable, Identifiable {
    var id: UUID
    let timestamp: Date
    let asrText: String
    let llmText: String?
    let correctedText: String
    let language: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        asrText: String,
        llmText: String?,
        correctedText: String,
        language: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.asrText = asrText
        self.llmText = llmText
        self.correctedText = correctedText
        self.language = language
    }
}
