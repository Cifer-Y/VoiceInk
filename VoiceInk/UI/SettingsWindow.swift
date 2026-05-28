import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "Settings")

// MARK: - Reusable Mode Section

/// A settings section for one mode (short sentence or long text).
/// Owns its own transient state (testing) while parent owns setting values.
struct ModeSettingsSection: View {
    @Binding var engine: String
    @Binding var transcriptionModel: String
    @Binding var transcriptionBaseURL: String
    @Binding var transcriptionAPIKey: String
    @Binding var llmEnabled: Bool
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var reasoningEffort: String

    let transcriptionService: OpenAITranscriptionService
    let llmService: LLMService

    @State private var isTestingTranscription = false
    @State private var transcriptionTestResult: TestResult?
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    private var useOpenAITranscription: Bool {
        engine == TranscriptionEngine.openai.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Speech Engine
            Text("Speech Engine")
                .font(.headline)

            Picker("Engine", selection: $engine) {
                Text("Apple Speech").tag(TranscriptionEngine.apple.rawValue)
                Text("OpenAI").tag(TranscriptionEngine.openai.rawValue)
            }
            .pickerStyle(.segmented)

            if useOpenAITranscription {
                HStack {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $transcriptionModel) {
                        Text("gpt-4o-mini-transcribe").tag("gpt-4o-mini-transcribe")
                        Text("gpt-4o-transcribe").tag("gpt-4o-transcribe")
                        Text("whisper-1").tag("whisper-1")
                    }
                    .frame(width: 230)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("https://api.openai.com/v1", text: $transcriptionBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("sk-...", text: $transcriptionAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("Test Transcription") {
                        testTranscription()
                    }
                    .disabled(isTestingTranscription || transcriptionBaseURL.isEmpty || transcriptionAPIKey.isEmpty)

                    if isTestingTranscription {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let result = transcriptionTestResult {
                        resultLabel(result)
                    }
                }
            }

            Divider()

            // MARK: LLM Refinement
            Text("LLM Refinement")
                .font(.headline)

            Toggle("Enable LLM", isOn: $llmEnabled)

            if llmEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("https://api.openai.com/v1", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("gpt-4o-mini", text: $model)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reasoning")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $reasoningEffort) {
                            Text("auto").tag("")
                            Text("none").tag("none")
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .frame(width: 100)
                    }
                }

                HStack {
                    Button("Test LLM") {
                        testConnection()
                    }
                    .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty || model.isEmpty)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let result = testResult {
                        resultLabel(result)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultLabel(_ result: TestResult) -> some View {
        switch result {
        case .success:
            Label("OK", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - Actions

    private func testTranscription() {
        let config = TranscriptionConfig(baseURL: transcriptionBaseURL, apiKey: transcriptionAPIKey, model: transcriptionModel)
        isTestingTranscription = true
        transcriptionTestResult = nil

        Task {
            do {
                let success = try await transcriptionService.testConnection(config: config)
                await MainActor.run {
                    isTestingTranscription = false
                    transcriptionTestResult = success ? .success : .failure("Connection failed.")
                }
            } catch {
                await MainActor.run {
                    isTestingTranscription = false
                    transcriptionTestResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func testConnection() {
        let config = LLMConfig(baseURL: baseURL, apiKey: apiKey, model: model, reasoningEffort: reasoningEffort)
        isTesting = true
        testResult = nil

        Task {
            do {
                let success = try await llmService.testConnection(config: config)
                await MainActor.run {
                    isTesting = false
                    testResult = success ? .success : .failure("Connection failed.")
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    // Short sentence mode
    @State var engine: String
    @State var transcriptionModel: String
    @State var transcriptionBaseURL: String
    @State var transcriptionAPIKey: String
    @State var llmEnabled: Bool
    @State var baseURL: String
    @State var apiKey: String
    @State var model: String
    @State var reasoningEffort: String

    // Composing mode
    @State var composingEngine: String
    @State var composingTranscriptionModel: String
    @State var composingTranscriptionBaseURL: String
    @State var composingTranscriptionAPIKey: String
    @State var composingLLMEnabled: Bool
    @State var composingBaseURL: String
    @State var composingAPIKey: String
    @State var composingModel: String
    @State var composingReasoningEffort: String

    let settings: AppSettings
    let llmService: LLMService
    let transcriptionService: OpenAITranscriptionService
    let onSave: () -> Void
    let onCancel: () -> Void

    init(settings: AppSettings, llmService: LLMService, transcriptionService: OpenAITranscriptionService, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.llmService = llmService
        self.transcriptionService = transcriptionService
        self.onSave = onSave
        self.onCancel = onCancel

        // Short sentence
        self._engine = State(initialValue: settings.transcriptionEngine)
        self._transcriptionModel = State(initialValue: settings.transcriptionModel)
        self._transcriptionBaseURL = State(initialValue: settings.transcriptionBaseURL)
        self._transcriptionAPIKey = State(initialValue: settings.transcriptionAPIKey)
        self._llmEnabled = State(initialValue: settings.llmEnabled)
        self._baseURL = State(initialValue: settings.llmBaseURL)
        self._apiKey = State(initialValue: settings.llmAPIKey)
        self._model = State(initialValue: settings.llmModel)
        self._reasoningEffort = State(initialValue: settings.reasoningEffort)

        // Composing
        self._composingEngine = State(initialValue: settings.composingTranscriptionEngine)
        self._composingTranscriptionModel = State(initialValue: settings.composingTranscriptionModel)
        self._composingTranscriptionBaseURL = State(initialValue: settings.composingTranscriptionBaseURL)
        self._composingTranscriptionAPIKey = State(initialValue: settings.composingTranscriptionAPIKey)
        self._composingLLMEnabled = State(initialValue: settings.composingLLMEnabled)
        self._composingBaseURL = State(initialValue: settings.composingLLMBaseURL)
        self._composingAPIKey = State(initialValue: settings.composingLLMAPIKey)
        self._composingModel = State(initialValue: settings.composingModel)
        self._composingReasoningEffort = State(initialValue: settings.composingReasoningEffort)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ScrollView {
                    ModeSettingsSection(
                        engine: $engine,
                        transcriptionModel: $transcriptionModel,
                        transcriptionBaseURL: $transcriptionBaseURL,
                        transcriptionAPIKey: $transcriptionAPIKey,
                        llmEnabled: $llmEnabled,
                        baseURL: $baseURL,
                        apiKey: $apiKey,
                        model: $model,
                        reasoningEffort: $reasoningEffort,
                        transcriptionService: transcriptionService,
                        llmService: llmService
                    )
                    .padding(16)
                    .frame(width: 440)
                }
                .tabItem { Label("Short Sentence", systemImage: "text.bubble") }

                ScrollView {
                    ModeSettingsSection(
                        engine: $composingEngine,
                        transcriptionModel: $composingTranscriptionModel,
                        transcriptionBaseURL: $composingTranscriptionBaseURL,
                        transcriptionAPIKey: $composingTranscriptionAPIKey,
                        llmEnabled: $composingLLMEnabled,
                        baseURL: $composingBaseURL,
                        apiKey: $composingAPIKey,
                        model: $composingModel,
                        reasoningEffort: $composingReasoningEffort,
                        transcriptionService: transcriptionService,
                        llmService: llmService
                    )
                    .padding(16)
                    .frame(width: 440)
                }
                .tabItem { Label("Long Text", systemImage: "doc.text") }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private func saveSettings() {
        // Short sentence
        settings.transcriptionEngine = engine
        settings.transcriptionModel = transcriptionModel
        settings.transcriptionBaseURL = transcriptionBaseURL
        settings.transcriptionAPIKey = transcriptionAPIKey
        settings.llmEnabled = llmEnabled
        settings.llmBaseURL = baseURL
        settings.llmAPIKey = apiKey
        settings.llmModel = model
        settings.reasoningEffort = reasoningEffort

        // Composing
        settings.composingTranscriptionEngine = composingEngine
        settings.composingTranscriptionModel = composingTranscriptionModel
        settings.composingTranscriptionBaseURL = composingTranscriptionBaseURL
        settings.composingTranscriptionAPIKey = composingTranscriptionAPIKey
        settings.composingLLMEnabled = composingLLMEnabled
        settings.composingLLMBaseURL = composingBaseURL
        settings.composingLLMAPIKey = composingAPIKey
        settings.composingModel = composingModel
        settings.composingReasoningEffort = composingReasoningEffort

        onSave()
    }
}

// MARK: - Window Controller

final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, llmService: LLMService, transcriptionService: OpenAITranscriptionService) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settings,
            llmService: llmService,
            transcriptionService: transcriptionService,
            onSave: { [weak self] in
                self?.window?.close()
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 460, height: 540)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInk — Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
