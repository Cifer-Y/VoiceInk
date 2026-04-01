import AppKit
import Observation

/// Main orchestrator: wires KeyMonitor, AudioEngine, HUD, TextInjector, LLMService, and CorrectionManager.
/// Implements the state machine: idle → recording → refining → injecting → correctionReady → idle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Services
    private let settings = AppSettings()
    private let usageStats = UsageStats()
    private lazy var keyMonitor = KeyMonitor()
    private let audioEngine = AudioEngine()
    private lazy var llmService = LLMService(settings: settings)
    private let whisperService = WhisperService()
    private let correctionManager = CorrectionManager()
    private let userDictionary = UserDictionaryManager()

    // UI
    private lazy var menuBarManager = MenuBarManager(settings: settings, correctionManager: correctionManager)
    private let hudPanel = HUDPanel()
    private let composingPanel = ComposingPanel()
    private let settingsWindowController = SettingsWindowController()
    private let correctionWindowController = CorrectionWindowController()
    private let correctionHistoryWindowController = CorrectionHistoryWindowController()
    private let userDictionaryWindowController = UserDictionaryWindowController()
    private let statsWindowController = StatsWindowController()

    // State
    private var state: TranscriptionState = .idle {
        didSet {
            menuBarManager.updateIcon(for: state)
        }
    }
    private var lastResult: TranscriptionResult?
    private var composingBuffer: String = ""
    private var recordingStartTime: Date?
    private var whisperRecordingURL: URL?
    private var currentLoadedWhisperModel: String?
    private var rmsObservation: Any?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.requestAll()
        setupMenuBar()
        setupKeyMonitor()
        startRMSObservation()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        menuBarManager.setup()

        menuBarManager.onLanguageChanged = { _ in }
        menuBarManager.onLLMToggled = { _ in }

        menuBarManager.onLLMSettingsRequested = { [weak self] in
            guard let self else { return }
            self.settingsWindowController.show(settings: self.settings, llmService: self.llmService, whisperService: self.whisperService)
        }

        menuBarManager.onCorrectionHistoryRequested = { [weak self] in
            guard let self else { return }
            self.correctionHistoryWindowController.show(correctionManager: self.correctionManager)
        }

        menuBarManager.onUserDictionaryRequested = { [weak self] in
            guard let self else { return }
            self.userDictionaryWindowController.show(dictionaryManager: self.userDictionary)
        }

        menuBarManager.onStatsRequested = { [weak self] in
            guard let self else { return }
            self.statsWindowController.show(stats: self.usageStats)
        }

        menuBarManager.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor.onRightControlDown = { [weak self] in
            self?.handleRecordingStart()
        }

        keyMonitor.onRightControlUp = { [weak self] in
            self?.handleRecordingStop()
        }

        keyMonitor.onShortTap = { [weak self] in
            self?.handleShortTap()
        }

        keyMonitor.onDoubleTap = { [weak self] in
            self?.handleDoubleTap()
        }

        keyMonitor.start()
    }

    // MARK: - Recording Flow

    private func handleRecordingStart() {
        // Composing mode: start recording a new segment
        if state == .composing {
            state = .composingRecording
            do {
                if settings.composingUseWhisper {
                    whisperRecordingURL = try audioEngine.startRecordingToFile()
                } else {
                    try audioEngine.startRecording(locale: settings.locale)
                }
            } catch {
                print("[AppDelegate] Composing recording failed: \(error)")
                state = .composing
            }
            composingPanel.setRecording(true)
            return
        }

        guard state == .idle || state == .correctionReady else { return }
        startRecording()
    }

    private func startRecording() {
        state = .recording
        recordingStartTime = Date()

        do {
            if settings.useWhisper {
                // Whisper mode: record to WAV file, no real-time ASR
                whisperRecordingURL = try audioEngine.startRecordingToFile()
            } else {
                try audioEngine.startRecording(locale: settings.locale)
            }
        } catch {
            state = .error(error.localizedDescription)
            print("Failed to start recording: \(error)")
            return
        }

        // Show HUD
        hudPanel.setCompactMode(settings.useWhisper)
        hudPanel.show()
        hudPanel.setStatus(.recording)
        hudPanel.updateText("")
    }

    private func handleRecordingStop() {
        // Composing mode: stop recording and append result to panel
        if state == .composingRecording {
            state = .composingRefining
            composingPanel.setRecording(false)

            if settings.composingUseWhisper {
                let fileURL = audioEngine.stopRecordingToFile()
                Task {
                    let text = await transcribeWithWhisper(fileURL: fileURL, modelSize: settings.composingWhisperModel)
                    await MainActor.run {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if !self.composingBuffer.isEmpty { self.composingBuffer += "\n" }
                            self.composingBuffer += trimmed
                            self.composingPanel.updateText(self.composingBuffer)
                        }
                        self.state = .composing
                    }
                }
            } else {
                audioEngine.stopAndFinalize { [weak self] asrText in
                    guard let self else { return }
                    let trimmed = asrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if !self.composingBuffer.isEmpty { self.composingBuffer += "\n" }
                        self.composingBuffer += trimmed
                        self.composingPanel.updateText(self.composingBuffer)
                    }
                    self.state = .composing
                }
            }
            return
        }

        guard state == .recording else { return }

        // Show processing state
        state = .refining
        hudPanel.setCompactMode(false)
        hudPanel.setStatus(.refining)

        if settings.useWhisper {
            let fileURL = audioEngine.stopRecordingToFile()
            hudPanel.updateText("Transcribing...")

            Task {
                let asrText = await transcribeWithWhisper(fileURL: fileURL, modelSize: settings.whisperModel)
                await MainActor.run {
                    self.processASRResult(asrText)
                }
            }
        } else {
            audioEngine.stopAndFinalize { [weak self] asrText in
                guard let self else { return }
                self.processASRResult(asrText)
            }
        }
    }

    /// Runs Whisper transcription on a background thread.
    private func transcribeWithWhisper(fileURL: URL?, modelSize: String) async -> String {
        guard let fileURL else { return "" }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            if !whisperService.isModelLoaded || currentLoadedWhisperModel != modelSize {
                whisperService.unloadModel()
                print("[Whisper] Loading model: \(modelSize)")
                try whisperService.loadModel(size: modelSize)
                currentLoadedWhisperModel = modelSize
            }
            let start = Date()
            let result = try whisperService.transcribe(
                audioURL: fileURL,
                language: settings.locale,
                initialPrompt: userDictionary.whisperPrompt()
            )
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            print("[Whisper] Transcribed (\(elapsed)): \"\(result)\"")
            return result
        } catch {
            print("[Whisper] Transcription error: \(error)")
            return ""
        }
    }

    /// Common path for processing ASR text (from either Apple Speech or Whisper).
    private func processASRResult(_ asrText: String) {
        guard !asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            hudPanel.dismiss()
            return
        }

        if llmService.isShortSentenceEnabled {
            hudPanel.updateText(asrText)
            let examples = correctionManager.selectExamples(for: asrText)
            let dictSnippet = userDictionary.llmPromptSnippet()

            Task {
                do {
                    let refined = try await self.llmService.refine(text: asrText, examples: examples, dictionarySnippet: dictSnippet)
                    await MainActor.run {
                        self.finishWithText(asrText: asrText, llmText: refined, finalText: refined)
                    }
                } catch {
                    let isRateLimited = (error as? LLMError) == .rateLimited
                    await MainActor.run {
                        self.finishWithText(asrText: asrText, llmText: nil, finalText: asrText)
                        if isRateLimited {
                            self.showQuotaWarning()
                        }
                    }
                }
            }
        } else {
            finishWithText(asrText: asrText, llmText: nil, finalText: asrText)
        }
    }

    private func finishWithText(asrText: String, llmText: String?, finalText: String) {
        state = .injecting

        // Track stats
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        usageStats.recordSession(duration: duration)
        recordingStartTime = nil

        // Store result for potential correction
        lastResult = TranscriptionResult(
            asrText: asrText,
            llmText: llmText,
            finalText: finalText,
            language: settings.locale,
            timestamp: Date()
        )

        // Inject text
        TextInjector.inject(finalText)

        // Dismiss HUD
        hudPanel.dismiss()

        // Enter correction-ready state — stays until next recording starts
        state = .correctionReady
    }

    // MARK: - Short Tap (Correction Trigger)

    private func handleShortTap() {
        if state == .correctionReady, let result = lastResult {
            state = .idle
            showCorrectionWindow(for: result)
        }
    }

    private func showCorrectionWindow(for result: TranscriptionResult) {
        // Save the app the user was typing in, so we can restore focus after correction
        let previousApp = NSWorkspace.shared.frontmostApplication

        correctionWindowController.show(result: result) { [weak self] correctedText in
            guard let self else { return }

            // Save correction entry
            let entry = CorrectionEntry(
                asrText: result.asrText,
                llmText: result.llmText,
                correctedText: correctedText,
                language: result.language
            )
            self.correctionManager.add(entry: entry)

            // Copy corrected text to clipboard for user to paste manually
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(correctedText, forType: .string)
            self.usageStats.recordManualCorrection()

            if let previousApp {
                previousApp.activate()
            }

            // Show brief HUD notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.hudPanel.show()
                self.hudPanel.setStatus(.recording)
                self.hudPanel.updateText("Copied to clipboard. Cmd+V to paste.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.hudPanel.dismiss()
                }
            }

            self.menuBarManager.rebuildMenu()
        }
    }

    // MARK: - Double Tap (Composing Mode Toggle)

    private func handleDoubleTap() {
        if state == .idle || state == .correctionReady {
            // Enter composing mode
            lastResult = nil
            composingBuffer = ""
            state = .composing
            composingPanel.updateText("")
            composingPanel.onConfirm = { [weak self] text in
                self?.confirmComposing(text: text)
            }
            composingPanel.onCancel = { [weak self] in
                self?.cancelComposing()
            }
            composingPanel.show()
        } else if state == .composing {
            // Confirm composing
            confirmComposing(text: composingBuffer)
        }
    }

    private func confirmComposing(text: String) {
        let rawText = text
        composingPanel.dismiss()
        usageStats.recordComposing()

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }

        // Send to LLM for long-text refinement
        if llmService.isComposingEnabled {
            state = .refining
            hudPanel.show()
            hudPanel.setStatus(.refining)
            hudPanel.updateText("Organizing text...")

            Task {
                do {
                    let refined = try await llmService.refineComposing(text: rawText)
                    await MainActor.run {
                        self.hudPanel.dismiss()
                        TextInjector.inject(refined)
                        self.state = .idle
                    }
                } catch {
                    let isRateLimited = (error as? LLMError) == .rateLimited
                    await MainActor.run {
                        self.hudPanel.dismiss()
                        TextInjector.inject(rawText)
                        self.state = .idle
                        if isRateLimited {
                            self.showQuotaWarning()
                        }
                    }
                }
            }
        } else {
            TextInjector.inject(rawText)
            state = .idle
        }
    }

    private func cancelComposing() {
        composingPanel.dismiss()
        composingBuffer = ""
        state = .idle
    }

    // MARK: - Quota Warning

    private func showQuotaWarning() {
        hudPanel.show()
        hudPanel.setStatus(.recording)
        hudPanel.updateText("API quota exceeded. Free tier limit reached.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hudPanel.dismiss()
        }
    }

    // MARK: - RMS Observation

    private func startRMSObservation() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.state == .recording {
                self.hudPanel.updateRMS(self.audioEngine.rmsLevel)
                if self.settings.useWhisper {
                    // Whisper mode: show recording duration
                    if let start = self.recordingStartTime {
                        let elapsed = Int(Date().timeIntervalSince(start))
                        let m = elapsed / 60
                        let s = elapsed % 60
                        self.hudPanel.updateText(String(format: "%d:%02d", m, s))
                    }
                } else {
                    self.hudPanel.updateText(self.audioEngine.partialText)
                }
            } else if self.state == .composingRecording {
                self.composingPanel.updateRMS(self.audioEngine.rmsLevel)
            }
        }
    }
}
