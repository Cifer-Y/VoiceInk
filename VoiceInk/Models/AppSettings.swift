import Foundation
import Observation

/// Speech-to-text engine. Apple Speech is local/real-time/free; OpenAI is remote/more accurate/paid.
enum TranscriptionEngine: String {
    case apple
    case openai
}

struct LLMConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let reasoningEffort: String

    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}

struct TranscriptionConfig {
    let baseURL: String
    let apiKey: String
    let model: String

    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    static let defaultTranscriptionModel = "gpt-4o-mini-transcribe"

    var locale: String {
        didSet { defaults.set(locale, forKey: "locale") }
    }

    // MARK: - Short Sentence Mode — Transcription

    var transcriptionEngine: String {
        didSet { defaults.set(transcriptionEngine, forKey: "transcriptionEngine") }
    }

    var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: "transcriptionModel") }
    }

    var transcriptionBaseURL: String {
        didSet { defaults.set(transcriptionBaseURL, forKey: "transcriptionBaseURL") }
    }

    var transcriptionAPIKey: String {
        didSet { defaults.set(transcriptionAPIKey, forKey: "transcriptionAPIKey") }
    }

    // MARK: - Short Sentence Mode — LLM

    var llmEnabled: Bool {
        didSet { defaults.set(llmEnabled, forKey: "llmEnabled") }
    }

    var llmBaseURL: String {
        didSet { defaults.set(llmBaseURL, forKey: "llmBaseURL") }
    }

    var llmAPIKey: String {
        didSet { defaults.set(llmAPIKey, forKey: "llmAPIKey") }
    }

    var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "llmModel") }
    }

    var reasoningEffort: String {
        didSet { defaults.set(reasoningEffort, forKey: "reasoningEffort") }
    }

    // MARK: - Long Text (Composing) Mode — Transcription

    var composingTranscriptionEngine: String {
        didSet { defaults.set(composingTranscriptionEngine, forKey: "composingTranscriptionEngine") }
    }

    var composingTranscriptionModel: String {
        didSet { defaults.set(composingTranscriptionModel, forKey: "composingTranscriptionModel") }
    }

    var composingTranscriptionBaseURL: String {
        didSet { defaults.set(composingTranscriptionBaseURL, forKey: "composingTranscriptionBaseURL") }
    }

    var composingTranscriptionAPIKey: String {
        didSet { defaults.set(composingTranscriptionAPIKey, forKey: "composingTranscriptionAPIKey") }
    }

    // MARK: - Long Text (Composing) Mode — LLM

    var composingLLMEnabled: Bool {
        didSet { defaults.set(composingLLMEnabled, forKey: "composingLLMEnabled") }
    }

    var composingLLMBaseURL: String {
        didSet { defaults.set(composingLLMBaseURL, forKey: "composingLLMBaseURL") }
    }

    var composingLLMAPIKey: String {
        didSet { defaults.set(composingLLMAPIKey, forKey: "composingLLMAPIKey") }
    }

    var composingModel: String {
        didSet { defaults.set(composingModel, forKey: "composingModel") }
    }

    var composingReasoningEffort: String {
        didSet { defaults.set(composingReasoningEffort, forKey: "composingReasoningEffort") }
    }

    // MARK: - Config Helpers

    var shortEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngine) ?? .apple
    }

    var composingEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: composingTranscriptionEngine) ?? .apple
    }

    var transcriptionConfig: TranscriptionConfig {
        TranscriptionConfig(baseURL: transcriptionBaseURL, apiKey: transcriptionAPIKey, model: transcriptionModel)
    }

    var composingTranscriptionConfig: TranscriptionConfig {
        TranscriptionConfig(baseURL: composingTranscriptionBaseURL, apiKey: composingTranscriptionAPIKey, model: composingTranscriptionModel)
    }

    var shortSentenceConfig: LLMConfig {
        LLMConfig(baseURL: llmBaseURL, apiKey: llmAPIKey, model: llmModel, reasoningEffort: reasoningEffort)
    }

    var composingConfig: LLMConfig {
        LLMConfig(baseURL: composingLLMBaseURL, apiKey: composingLLMAPIKey, model: composingModel, reasoningEffort: composingReasoningEffort)
    }

    init() {
        let d = defaults
        let defaultBaseURL = "https://api.openai.com/v1"

        self.locale = d.string(forKey: "locale") ?? "zh-CN"

        // Short sentence LLM — read into locals first (reused as transcription defaults)
        let sLLMEnabled = d.object(forKey: "llmEnabled") as? Bool ?? false
        let sBaseURL = d.string(forKey: "llmBaseURL") ?? defaultBaseURL
        let sAPIKey = d.string(forKey: "llmAPIKey") ?? ""
        let sModel = d.string(forKey: "llmModel") ?? "gpt-4o-mini"
        let sReasoning = d.string(forKey: "reasoningEffort") ?? "low"

        self.llmEnabled = sLLMEnabled
        self.llmBaseURL = sBaseURL
        self.llmAPIKey = sAPIKey
        self.llmModel = sModel
        self.reasoningEffort = sReasoning

        // Short sentence transcription — migrate engine from legacy `useWhisper`,
        // reuse LLM credentials as defaults (same OpenAI account in practice).
        let legacyUseWhisper = d.object(forKey: "useWhisper") as? Bool ?? false
        self.transcriptionEngine = d.string(forKey: "transcriptionEngine")
            ?? (legacyUseWhisper ? TranscriptionEngine.openai.rawValue : TranscriptionEngine.apple.rawValue)
        self.transcriptionModel = d.string(forKey: "transcriptionModel") ?? Self.defaultTranscriptionModel
        self.transcriptionBaseURL = d.string(forKey: "transcriptionBaseURL") ?? sBaseURL
        self.transcriptionAPIKey = d.string(forKey: "transcriptionAPIKey") ?? sAPIKey

        // Composing LLM — migrate from shared short-sentence settings on first launch
        let needsMigration = d.object(forKey: "composingLLMBaseURL") == nil

        self.composingLLMEnabled = d.object(forKey: "composingLLMEnabled") as? Bool
            ?? (needsMigration ? sLLMEnabled : false)
        let cBaseURL = d.string(forKey: "composingLLMBaseURL")
            ?? (needsMigration ? sBaseURL : defaultBaseURL)
        self.composingLLMBaseURL = cBaseURL
        let cAPIKey = d.string(forKey: "composingLLMAPIKey")
            ?? (needsMigration ? sAPIKey : "")
        self.composingLLMAPIKey = cAPIKey
        self.composingReasoningEffort = d.string(forKey: "composingReasoningEffort") ?? "medium"

        let rawComposingModel = d.string(forKey: "composingModel") ?? ""
        self.composingModel = rawComposingModel.isEmpty ? sModel : rawComposingModel

        // Composing transcription — migrate engine from legacy `composingUseWhisper`
        let legacyComposingUseWhisper = d.object(forKey: "composingUseWhisper") as? Bool ?? false
        self.composingTranscriptionEngine = d.string(forKey: "composingTranscriptionEngine")
            ?? (legacyComposingUseWhisper ? TranscriptionEngine.openai.rawValue : TranscriptionEngine.apple.rawValue)
        self.composingTranscriptionModel = d.string(forKey: "composingTranscriptionModel") ?? Self.defaultTranscriptionModel
        self.composingTranscriptionBaseURL = d.string(forKey: "composingTranscriptionBaseURL") ?? cBaseURL
        self.composingTranscriptionAPIKey = d.string(forKey: "composingTranscriptionAPIKey") ?? cAPIKey

        // Persist migration values
        if needsMigration {
            d.set(composingLLMEnabled, forKey: "composingLLMEnabled")
            d.set(composingLLMBaseURL, forKey: "composingLLMBaseURL")
            d.set(composingLLMAPIKey, forKey: "composingLLMAPIKey")
            if rawComposingModel.isEmpty {
                d.set(composingModel, forKey: "composingModel")
            }
        }
    }
}
