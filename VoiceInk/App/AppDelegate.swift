import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.cifer.VoiceInk", category: "AppDelegate")

/// Main orchestrator: wires KeyMonitor, AudioEngine, HUD, TextInjector, LLMService, and CorrectionManager.
/// Implements the state machine: idle → recording → refining → injecting → correctionReady → idle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Services
    private let settings = AppSettings()
    private let usageStats = UsageStats()
    private lazy var keyMonitor = KeyMonitor()
    private let audioEngine = AudioEngine()
    private lazy var llmService = LLMService(settings: settings)
    private let transcriptionService = OpenAITranscriptionService()
    private let correctionManager = CorrectionManager()
    private let userDictionary = UserDictionaryManager()

    // UI
    private lazy var menuBarManager = MenuBarManager(settings: settings, correctionManager: correctionManager)
    private let hudPanel = HUDPanel()
    private let speedToast = SpeedToast()
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
            // ESC only intercepts when VoiceInk is actively recording or processing
            keyMonitor.isActive = (state == .recording || state == .refining
                || state == .composingRecording || state == .composingRefining)
        }
    }
    private var requestId: UInt64 = 0  // Incremented on cancel to discard stale async results
    private var lastResult: TranscriptionResult?
    private var composingBuffer: String = ""
    private var composingSegments: [AnnotatedTranscription] = []
    private var recentOutputs: [String] = []
    private var recordingStartTime: Date?
    private var processingStartTime: Date?  // Measures latency from recording stop to injection
    private var whisperRecordingURL: URL?
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
            self.settingsWindowController.show(settings: self.settings, llmService: self.llmService, transcriptionService: self.transcriptionService)
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
        keyMonitor.onRightOptionDown = { [weak self] in
            self?.handleRecordingStart()
        }

        keyMonitor.onRightOptionUp = { [weak self] in
            self?.handleRecordingStop()
        }

        keyMonitor.onShortTap = { [weak self] in
            self?.handleShortTap()
        }

        keyMonitor.onDoubleTap = { [weak self] in
            self?.handleDoubleTap()
        }

        keyMonitor.onEscape = { [weak self] in
            self?.handleEscapeCancel()
        }

        keyMonitor.start()
    }

    // MARK: - Cancel

    private func handleEscapeCancel() {
        switch state {
        case .recording, .composingRecording:
            logger.info("ESC: cancelling recording")
            requestId &+= 1
            audioEngine.stopRecording()
            if let url = whisperRecordingURL {
                try? FileManager.default.removeItem(at: url)
                whisperRecordingURL = nil
            }
            hudPanel.dismiss()
            state = (state == .composingRecording) ? .composing : .idle
        case .refining, .composingRefining:
            logger.info("ESC: cancelling refinement")
            requestId &+= 1
            hudPanel.dismiss()
            state = (state == .composingRefining) ? .composing : .idle
        default:
            break  // ESC does nothing in other states — let it pass through
        }
    }

    // MARK: - Recording Flow

    private func handleRecordingStart() {
        // Composing mode: start recording a new segment
        if state == .composing {
            state = .composingRecording
            do {
                if settings.composingEngine == .openai {
                    whisperRecordingURL = try audioEngine.startRecordingToFile()
                } else {
                    try audioEngine.startRecording(locale: settings.locale)
                }
            } catch {
                logger.error("Composing recording failed: \(error)")
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
            if settings.shortEngine == .openai {
                // OpenAI mode: record to WAV file, no real-time ASR
                whisperRecordingURL = try audioEngine.startRecordingToFile()
            } else {
                try audioEngine.startRecording(locale: settings.locale)
            }
        } catch {
            state = .error(error.localizedDescription)
            logger.error("Failed to start recording: \(error)")
            return
        }

        // Show HUD
        hudPanel.setCompactMode(settings.shortEngine == .openai)
        hudPanel.show()
        hudPanel.setStatus(.recording)
        hudPanel.updateText("")
    }

    private func handleRecordingStop() {
        // Composing mode: stop recording and append result to panel
        if state == .composingRecording {
            state = .composingRefining
            composingPanel.setRecording(false)

            if settings.composingEngine == .openai {
                let fileURL = audioEngine.stopRecordingToFile()
                let rid = requestId
                Task {
                    let transcription = await transcribeWithOpenAI(fileURL: fileURL, config: settings.composingTranscriptionConfig)
                    await MainActor.run {
                        guard self.requestId == rid else { return }
                        let trimmed = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if !self.composingBuffer.isEmpty { self.composingBuffer += "\n" }
                            self.composingBuffer += trimmed
                            self.composingSegments.append(transcription)
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
        processingStartTime = Date()
        hudPanel.setCompactMode(false)
        hudPanel.setStatus(.refining)

        if settings.shortEngine == .openai {
            let fileURL = audioEngine.stopRecordingToFile()
            hudPanel.updateText("Transcribing...")

            let rid = requestId
            Task {
                let transcription = await transcribeWithOpenAI(fileURL: fileURL, config: settings.transcriptionConfig)
                await MainActor.run {
                    guard self.requestId == rid else { return }
                    self.processASRResult(transcription.text, annotatedText: transcription.annotatedText())
                }
            }
        } else {
            let rid = requestId
            audioEngine.stopAndFinalize { [weak self] asrText in
                guard let self, self.requestId == rid else { return }
                self.processASRResult(asrText)
            }
        }
    }

    /// Runs OpenAI transcription on a background task.
    private func transcribeWithOpenAI(fileURL: URL?, config: TranscriptionConfig) async -> AnnotatedTranscription {
        guard let fileURL else { return .plain("") }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            return try await transcriptionService.transcribe(
                audioURL: fileURL,
                language: settings.locale,
                prompt: buildTranscriptionPrompt(),
                config: config
            )
        } catch {
            logger.error("Transcription error: \(error)")
            return .plain("")
        }
    }

    /// Common path for processing ASR text (from either Apple Speech or OpenAI).
    /// `annotatedText` carries confidence annotations only when the source provides them
    /// (currently neither Apple Speech nor the OpenAI API does).
    private func processASRResult(_ asrText: String, annotatedText: String? = nil) {
        guard !asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            hudPanel.dismiss()
            return
        }

        if llmService.isShortSentenceEnabled {
            hudPanel.updateText(asrText)
            let examples = correctionManager.selectExamples(for: asrText)
            let dictSnippet = userDictionary.llmPromptSnippet()
            let context = recentOutputs.joined(separator: "\n")
            let activeApp = NSWorkspace.shared.frontmostApplication?.localizedName

            Task {
                do {
                    let refined = try await self.llmService.refine(text: asrText, annotatedText: annotatedText, examples: examples, dictionarySnippet: dictSnippet, previousContext: context, activeApp: activeApp)
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
        usageStats.recordCharacters(finalText.count)
        if llmText != nil { usageStats.recordLLMRefinement() }
        if let start = processingStartTime {
            usageStats.recordLatency(Date().timeIntervalSince(start) * 1000)
            processingStartTime = nil
        }
        recordingStartTime = nil

        // Store result for potential correction
        lastResult = TranscriptionResult(
            asrText: asrText,
            llmText: llmText,
            finalText: finalText,
            language: settings.locale,
            timestamp: Date()
        )

        // Append to context buffer (may be replaced by manual correction later)
        recentOutputs.append(finalText)
        if recentOutputs.count > 5 {
            recentOutputs.removeFirst()
        }
        logger.info("Context buffer [\(self.recentOutputs.count)]: \(self.recentOutputs.joined(separator: " | "), privacy: .public)")

        // Inject text
        TextInjector.inject(finalText)

        // Dismiss HUD
        hudPanel.dismiss()

        // Show speed toast
        if duration > 0 {
            let cpm = Int(Double(finalText.count) / duration * 60)
            speedToast.show(charCount: finalText.count, cpm: cpm)
        }

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

            // Replace last context entry with the manual correction
            if !self.recentOutputs.isEmpty {
                self.recentOutputs[self.recentOutputs.count - 1] = correctedText
                logger.info("Context corrected [\(self.recentOutputs.count)]: \(self.recentOutputs.joined(separator: " | "), privacy: .public)")
            }

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
            composingSegments = []
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
        let segments = composingSegments
        composingSegments = []
        composingPanel.dismiss()
        usageStats.recordComposing()

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }

        // Build annotated text from accumulated Whisper segments
        let annotated: String? = segments.isEmpty ? nil : segments.map { $0.annotatedText() }.joined(separator: "\n")

        // Send to LLM for long-text refinement
        if llmService.isComposingEnabled {
            state = .refining
            hudPanel.show()
            hudPanel.setStatus(.refining)
            hudPanel.updateText("Organizing text...")

            Task {
                do {
                    let refined = try await llmService.refineComposing(text: rawText, annotatedText: annotated)
                    await MainActor.run {
                        self.hudPanel.dismiss()
                        self.usageStats.recordCharacters(refined.count)
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
        composingSegments = []
        state = .idle
    }

    // MARK: - Transcription Prompt

    /// Combines user dictionary terms and frequently corrected words into a single
    /// transcription prompt (OpenAI `prompt` parameter), used to bias the decoder toward
    /// specific vocabulary. User dictionary terms take priority; correction-derived terms
    /// fill the remaining budget.
    private static let transcriptionPromptMaxChars = 400  // ~200 tokens for CJK

    private func buildTranscriptionPrompt() -> String {
        let dictPrompt = userDictionary.whisperPrompt()
        let remaining = Self.transcriptionPromptMaxChars - dictPrompt.count
        guard remaining > 10 else { return dictPrompt }

        let correctionTerms = correctionManager.whisperPromptTerms()
        var correctionPart = ""
        for term in correctionTerms {
            let addition = correctionPart.isEmpty ? term : ", \(term)"
            if correctionPart.count + addition.count > remaining { break }
            correctionPart += addition
        }

        let parts = [dictPrompt, correctionPart].filter { !$0.isEmpty }
        let result = parts.joined(separator: ", ")
        logger.debug("Whisper prompt (\(result.count) chars): \(result, privacy: .public)")
        return result
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
                if self.settings.shortEngine == .openai {
                    // OpenAI mode: no real-time text, show recording duration
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
