import SwiftUI
import AppKit

/// Settings window for configuring Speech Engine (Whisper) and LLM Refinement.
struct SettingsView: View {
    @State var baseURL: String
    @State var apiKey: String
    @State var model: String
    @State var composingModel: String
    @State var reasoningEffort: String
    @State var composingReasoningEffort: String
    @State var useWhisper: Bool
    @State var whisperModel: String
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0

    let settings: AppSettings
    let llmService: LLMService
    let onSave: () -> Void
    let onCancel: () -> Void

    enum TestResult {
        case success
        case failure(String)
    }

    init(settings: AppSettings, llmService: LLMService, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.settings = settings
        self.llmService = llmService
        self.onSave = onSave
        self.onCancel = onCancel
        self._baseURL = State(initialValue: settings.llmBaseURL)
        self._apiKey = State(initialValue: settings.llmAPIKey)
        self._model = State(initialValue: settings.llmModel)
        self._composingModel = State(initialValue: settings.composingModel)
        self._reasoningEffort = State(initialValue: settings.reasoningEffort)
        self._composingReasoningEffort = State(initialValue: settings.composingReasoningEffort)
        self._useWhisper = State(initialValue: settings.useWhisper)
        self._whisperModel = State(initialValue: settings.whisperModel)
    }

    private let whisperModels = ["tiny", "base", "small", "medium"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Speech Engine
                Text("Speech Engine")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
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
                                ForEach(whisperModels, id: \.self) { size in
                                    Text(size).tag(size)
                                }
                            }
                            .frame(width: 120)

                            Spacer()

                            if WhisperService.isModelDownloaded(whisperModel) {
                                Label("Ready", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else if isDownloading {
                                ProgressView(value: downloadProgress)
                                    .frame(width: 80)
                            } else {
                                Button("Download") {
                                    downloadWhisperModel()
                                }
                            }
                        }
                    }
                }

                Divider()

                // MARK: - LLM Refinement
                Text("LLM Refinement")
                    .font(.headline)

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model (short sentence)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("gemini-2.5-flash", text: $model)
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $reasoningEffort) {
                            Text("none").tag("")
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .frame(width: 100)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model (long text) — optional, defaults to above")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("gemini-3-flash-preview", text: $composingModel)
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $composingReasoningEffort) {
                            Text("none").tag("")
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .frame(width: 100)
                    }
                }

                // Test result
                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                // MARK: - Actions
                HStack {
                    Button("Test LLM") {
                        testConnection()
                    }
                    .disabled(isTesting || baseURL.isEmpty || apiKey.isEmpty || model.isEmpty)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

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
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func testConnection() {
        let originalURL = settings.llmBaseURL
        let originalKey = settings.llmAPIKey
        let originalModel = settings.llmModel

        settings.llmBaseURL = baseURL
        settings.llmAPIKey = apiKey
        settings.llmModel = model

        isTesting = true
        testResult = nil

        Task {
            do {
                let success = try await llmService.testConnection()
                await MainActor.run {
                    isTesting = false
                    testResult = success ? .success : .failure("Connection failed.")
                    settings.llmBaseURL = originalURL
                    settings.llmAPIKey = originalKey
                    settings.llmModel = originalModel
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                    settings.llmBaseURL = originalURL
                    settings.llmAPIKey = originalKey
                    settings.llmModel = originalModel
                }
            }
        }
    }

    private func saveSettings() {
        settings.useWhisper = useWhisper
        settings.whisperModel = whisperModel
        settings.llmBaseURL = baseURL
        settings.llmAPIKey = apiKey
        settings.llmModel = model
        settings.composingModel = composingModel
        settings.reasoningEffort = reasoningEffort
        settings.composingReasoningEffort = composingReasoningEffort
        onSave()
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
                    case .failure(let error):
                        print("[Settings] Model download failed: \(error)")
                    }
                }
            }
        )
    }
}

/// Helper to present the settings window as an NSPanel.
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, llmService: LLMService) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settings: settings,
            llmService: llmService,
            onSave: { [weak self] in
                self?.window?.close()
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
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
