import Foundation

enum TranscriptionState: Equatable {
    case idle
    case recording
    case refining
    case injecting
    case correctionReady // waiting for possible correction tap
    case composing       // long-text mode: accumulating multiple recordings
    case composingRecording // recording within composing mode
    case composingRefining  // waiting for ASR result within composing mode
    case error(String)

    static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.refining, .refining),
             (.injecting, .injecting), (.correctionReady, .correctionReady),
             (.composing, .composing), (.composingRecording, .composingRecording),
             (.composingRefining, .composingRefining):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Holds the result of a transcription session for potential correction
struct TranscriptionResult {
    let asrText: String
    let llmText: String?
    let finalText: String
    let language: String
    let timestamp: Date
}
