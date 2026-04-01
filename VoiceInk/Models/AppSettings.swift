import Foundation
import Observation

struct LLMConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let reasoningEffort: String

    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var locale: String {
        didSet { defaults.set(locale, forKey: "locale") }
    }

    // MARK: - Short Sentence Mode

    var useWhisper: Bool {
        didSet { defaults.set(useWhisper, forKey: "useWhisper") }
    }

    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: "whisperModel") }
    }

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

    // MARK: - Long Text (Composing) Mode

    var composingUseWhisper: Bool {
        didSet { defaults.set(composingUseWhisper, forKey: "composingUseWhisper") }
    }

    var composingWhisperModel: String {
        didSet { defaults.set(composingWhisperModel, forKey: "composingWhisperModel") }
    }

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

    var shortSentenceConfig: LLMConfig {
        LLMConfig(baseURL: llmBaseURL, apiKey: llmAPIKey, model: llmModel, reasoningEffort: reasoningEffort)
    }

    var composingConfig: LLMConfig {
        LLMConfig(baseURL: composingLLMBaseURL, apiKey: composingLLMAPIKey, model: composingModel, reasoningEffort: composingReasoningEffort)
    }

    init() {
        let d = defaults

        self.locale = d.string(forKey: "locale") ?? "zh-CN"

        // Short sentence mode — read into locals first
        let sUseWhisper = d.object(forKey: "useWhisper") as? Bool ?? false
        let sWhisperModel = d.string(forKey: "whisperModel") ?? "base"
        let sLLMEnabled = d.object(forKey: "llmEnabled") as? Bool ?? false
        let sBaseURL = d.string(forKey: "llmBaseURL") ?? "https://api.openai.com/v1"
        let sAPIKey = d.string(forKey: "llmAPIKey") ?? ""
        let sModel = d.string(forKey: "llmModel") ?? "gpt-4o-mini"
        let sReasoning = d.string(forKey: "reasoningEffort") ?? "low"

        self.useWhisper = sUseWhisper
        self.whisperModel = sWhisperModel
        self.llmEnabled = sLLMEnabled
        self.llmBaseURL = sBaseURL
        self.llmAPIKey = sAPIKey
        self.llmModel = sModel
        self.reasoningEffort = sReasoning

        // Composing mode — migrate from shared settings on first launch
        let needsMigration = d.object(forKey: "composingLLMBaseURL") == nil

        self.composingUseWhisper = d.object(forKey: "composingUseWhisper") as? Bool
            ?? (needsMigration ? sUseWhisper : false)
        self.composingWhisperModel = d.string(forKey: "composingWhisperModel")
            ?? (needsMigration ? sWhisperModel : "base")
        self.composingLLMEnabled = d.object(forKey: "composingLLMEnabled") as? Bool
            ?? (needsMigration ? sLLMEnabled : false)
        self.composingLLMBaseURL = d.string(forKey: "composingLLMBaseURL")
            ?? (needsMigration ? sBaseURL : "https://api.openai.com/v1")
        self.composingLLMAPIKey = d.string(forKey: "composingLLMAPIKey")
            ?? (needsMigration ? sAPIKey : "")
        self.composingReasoningEffort = d.string(forKey: "composingReasoningEffort") ?? "medium"

        let rawComposingModel = d.string(forKey: "composingModel") ?? ""
        self.composingModel = rawComposingModel.isEmpty ? sModel : rawComposingModel

        // Persist migration values
        if needsMigration {
            d.set(composingUseWhisper, forKey: "composingUseWhisper")
            d.set(composingWhisperModel, forKey: "composingWhisperModel")
            d.set(composingLLMEnabled, forKey: "composingLLMEnabled")
            d.set(composingLLMBaseURL, forKey: "composingLLMBaseURL")
            d.set(composingLLMAPIKey, forKey: "composingLLMAPIKey")
            if rawComposingModel.isEmpty {
                d.set(composingModel, forKey: "composingModel")
            }
        }
    }
}
