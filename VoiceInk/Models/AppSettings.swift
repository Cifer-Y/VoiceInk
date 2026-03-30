import Foundation
import Observation

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var locale: String {
        didSet { defaults.set(locale, forKey: "locale") }
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

    var composingModel: String {
        didSet { defaults.set(composingModel, forKey: "composingModel") }
    }

    var reasoningEffort: String {
        didSet { defaults.set(reasoningEffort, forKey: "reasoningEffort") }
    }

    var composingReasoningEffort: String {
        didSet { defaults.set(composingReasoningEffort, forKey: "composingReasoningEffort") }
    }

    var useWhisper: Bool {
        didSet { defaults.set(useWhisper, forKey: "useWhisper") }
    }

    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: "whisperModel") }
    }

    var isLLMConfigured: Bool {
        !llmBaseURL.isEmpty && !llmAPIKey.isEmpty && !llmModel.isEmpty
    }

    init() {
        self.locale = defaults.string(forKey: "locale") ?? "zh-CN"
        self.llmEnabled = defaults.object(forKey: "llmEnabled") as? Bool ?? false
        self.llmBaseURL = defaults.string(forKey: "llmBaseURL") ?? "https://api.openai.com/v1"
        self.llmAPIKey = defaults.string(forKey: "llmAPIKey") ?? ""
        self.llmModel = defaults.string(forKey: "llmModel") ?? "gpt-4o-mini"
        self.composingModel = defaults.string(forKey: "composingModel") ?? ""
        self.useWhisper = defaults.object(forKey: "useWhisper") as? Bool ?? false
        self.whisperModel = defaults.string(forKey: "whisperModel") ?? "base"
        self.reasoningEffort = defaults.string(forKey: "reasoningEffort") ?? "low"
        self.composingReasoningEffort = defaults.string(forKey: "composingReasoningEffort") ?? "medium"
    }
}
