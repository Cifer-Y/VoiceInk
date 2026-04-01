import SwiftUI
import AppKit

// MARK: - Reusable Mode Section

/// A settings section for one mode (short sentence or long text).
/// Owns its own transient state (downloading, testing) while parent owns setting values.
struct ModeSettingsSection: View {
    @Binding var useWhisper: Bool
    @Binding var whisperModel: String
    @Binding var llmEnabled: Bool
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var reasoningEffort: String
    @Binding var isModelDownloaded: Bool

    let whisperService: WhisperService
    let llmService: LLMService

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Speech Engine
            Text("Speech Engine")
                .font(.headline)

            Picker("Engine", selection: $useWhisper) {
                Text("Apple Speech").tag(false)
                Text("Whisper (local)").tag(true)
            }
            .pickerStyle(.segmented)

            if useWhisper {
                HStack {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $whisperModel) {
                        Text("Tiny (~75 MB)").tag("tiny")
                        Text("Base (~142 MB)").tag("base")
                        Text("Small (~466 MB)").tag("small")
                        Text("Medium (~1.5 GB)").tag("medium")
                        Text("Large v3 Turbo (~1.6 GB)").tag("large-v3-turbo")
                        Text("Large v3 (~2.9 GB)").tag("large-v3")
                    }
                    .frame(width: 230)
                    .onChange(of: whisperModel) { _, newValue in
                        isModelDownloaded = WhisperService.isModelDownloaded(newValue)
                    }
                }

                HStack {
                    if isModelDownloaded {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Spacer()
                        Button(role: .destructive) {
                            deleteWhisperModel()
                        } label: {
                            Label("Delete Model", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    } else if isDownloading {
                        ProgressView(value: downloadProgress)
                            .frame(width: 120)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Button("Download") {
                            downloadWhisperModel()
                        }
                        Spacer()
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
                }
            }
        }
    }

    // MARK: - Actions

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

    private func downloadWhisperModel() {
        isDownloading = true
        downloadProgress = 0
        WhisperService.downloadModel(
            size: whisperModel,
            onProgress: { progress in
                self.downloadProgress = progress
            },
            onComplete: { result in
                DispatchQueue.main.async {
                    self.isDownloading = false
                    switch result {
                    case .success:
                        self.downloadProgress = 1.0
                        self.isModelDownloaded = true
                    case .failure(let error):
                        print("[Settings] Model download failed: \(error)")
                    }
                }
            }
        )
    }

    private func deleteWhisperModel() {
        WhisperService.deleteModel(whisperModel)
        whisperService.unloadModel()
        isModelDownloaded = false
    }
}

// MARK: - Settings View

struct SettingsView: View {
    // Short sentence mode
    @State var useWhisper: Bool
    @State var whisperModel: String
    @State var llmEnabled: Bool
    @State var baseURL: String
    @State var apiKey: String
    @State var model: String
    @State var reasoningEffort: String
    @State var isShortModelDownloaded: Bool

    // Composing mode
    @State var composingUseWhisper: Bool
    @State var composingWhisperModel: String
    @State var composingLLMEnabled: Bool
    @State var composingBaseURL: String
    @State var composingAPIKey: String
    @State var composingModel: String
    @State var composingReasoningEffort: String
    @State var isComposingModelDownloaded: Bool

    let settings: AppSettings
    let llmService: LLMService
    let whisperService: WhisperService
    let onSave: () -> Void
    let onCancel: () -> Void

    init(settings: AppSettings, llmService: LLMService, whisperService: WhisperService, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.llmService = llmService
        self.whisperService = whisperService
        self.onSave = onSave
        self.onCancel = onCancel

        // Short sentence
        self._useWhisper = State(initialValue: settings.useWhisper)
        self._whisperModel = State(initialValue: settings.whisperModel)
        self._llmEnabled = State(initialValue: settings.llmEnabled)
        self._baseURL = State(initialValue: settings.llmBaseURL)
        self._apiKey = State(initialValue: settings.llmAPIKey)
        self._model = State(initialValue: settings.llmModel)
        self._reasoningEffort = State(initialValue: settings.reasoningEffort)
        self._isShortModelDownloaded = State(initialValue: WhisperService.isModelDownloaded(settings.whisperModel))

        // Composing
        self._composingUseWhisper = State(initialValue: settings.composingUseWhisper)
        self._composingWhisperModel = State(initialValue: settings.composingWhisperModel)
        self._composingLLMEnabled = State(initialValue: settings.composingLLMEnabled)
        self._composingBaseURL = State(initialValue: settings.composingLLMBaseURL)
        self._composingAPIKey = State(initialValue: settings.composingLLMAPIKey)
        self._composingModel = State(initialValue: settings.composingModel)
        self._composingReasoningEffort = State(initialValue: settings.composingReasoningEffort)
        self._isComposingModelDownloaded = State(initialValue: WhisperService.isModelDownloaded(settings.composingWhisperModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ScrollView {
                    ModeSettingsSection(
                        useWhisper: $useWhisper,
                        whisperModel: $whisperModel,
                        llmEnabled: $llmEnabled,
                        baseURL: $baseURL,
                        apiKey: $apiKey,
                        model: $model,
                        reasoningEffort: $reasoningEffort,
                        isModelDownloaded: $isShortModelDownloaded,
                        whisperService: whisperService,
                        llmService: llmService
                    )
                    .padding(16)
                    .frame(width: 440)
                }
                .tabItem { Label("Short Sentence", systemImage: "text.bubble") }

                ScrollView {
                    ModeSettingsSection(
                        useWhisper: $composingUseWhisper,
                        whisperModel: $composingWhisperModel,
                        llmEnabled: $composingLLMEnabled,
                        baseURL: $composingBaseURL,
                        apiKey: $composingAPIKey,
                        model: $composingModel,
                        reasoningEffort: $composingReasoningEffort,
                        isModelDownloaded: $isComposingModelDownloaded,
                        whisperService: whisperService,
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
        settings.useWhisper = useWhisper
        settings.whisperModel = whisperModel
        settings.llmEnabled = llmEnabled
        settings.llmBaseURL = baseURL
        settings.llmAPIKey = apiKey
        settings.llmModel = model
        settings.reasoningEffort = reasoningEffort

        // Composing
        settings.composingUseWhisper = composingUseWhisper
        settings.composingWhisperModel = composingWhisperModel
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

    func show(settings: AppSettings, llmService: LLMService, whisperService: WhisperService) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settings: settings,
            llmService: llmService,
            whisperService: whisperService,
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
