import AVFoundation
import Speech
import Observation

/// Manages AVAudioEngine for microphone input and SFSpeechRecognizer for streaming transcription.
/// Publishes RMS levels for waveform visualization and partial transcription text.
///
/// Known limitation: on-device SFSpeechRecognizer resets its context after a pause,
/// discarding earlier text. Workaround: stop and restart recording between pauses.
@Observable
final class AudioEngine {
    var rmsLevel: Float = 0.0
    var partialText: String = ""
    var finalText: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    // WAV file recording (for Whisper mode)
    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var recordingURL: URL?

    // Smoothing envelope
    private var smoothedRMS: Float = 0.0
    private let attackRate: Float = 0.4
    private let releaseRate: Float = 0.15

    // Generation counter to ignore callbacks from cancelled/stale recognition tasks
    private var recognitionGeneration: Int = 0

    // Finalization callback (used by stopAndFinalize)
    private var stopCompletion: ((String) -> Void)?
    private var stopTimeoutItem: DispatchWorkItem?

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }

    func startRecording(locale: String) throws {
        // Clean up any previous session
        stopRecording()

        let speechLocale = Locale(identifier: locale)
        speechRecognizer = SFSpeechRecognizer(locale: speechLocale)

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw AudioEngineError.speechRecognizerUnavailable
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw AudioEngineError.noMicrophoneInput
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if #available(macOS 15.0, *) {
            if speechRecognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        // Install audio tap for RMS metering + speech recognition
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            self.recognitionRequest?.append(buffer)

            let rms = self.computeRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.updateRMS(rms)
            }
        }

        partialText = ""
        finalText = ""

        self.recognitionRequest = request
        self.audioEngine = engine

        startRecognitionTask()

        engine.prepare()
        try engine.start()
    }

    // MARK: - WAV File Recording (for Whisper)

    /// Records audio to a 16kHz mono WAV file for Whisper transcription.
    /// No speech recognition is started — only RMS metering for waveform HUD.
    func startRecordingToFile() throws -> URL {
        stopRecording()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw AudioEngineError.noMicrophoneInput
        }

        // Target: 16kHz mono float32 WAV
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw AudioEngineError.noMicrophoneInput
        }

        // Create converter from mic format to 16kHz mono
        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            throw AudioEngineError.noMicrophoneInput
        }
        self.audioConverter = converter

        // Create temp WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voiceink_\(Int(Date().timeIntervalSince1970)).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        let file = try AVAudioFile(forWriting: fileURL, settings: targetFormat.settings)
        self.audioFile = file
        self.recordingURL = fileURL

        // Install tap: convert to 16kHz, write to file, compute RMS
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.audioConverter, let file = self.audioFile else { return }

            // Convert buffer to 16kHz mono
            let ratio = 16000.0 / recordingFormat.sampleRate
            let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 128
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else { return }

            var isDone = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if isDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDone = true
                outStatus.pointee = .haveData
                return buffer
            }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            if error == nil && convertedBuffer.frameLength > 0 {
                try? file.write(from: convertedBuffer)
            }

            // Compute RMS from original buffer for waveform
            let rms = self.computeRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.updateRMS(rms)
            }
        }

        partialText = ""
        finalText = ""
        self.audioEngine = engine

        engine.prepare()
        try engine.start()

        return fileURL
    }

    /// Stops WAV file recording and returns the file URL.
    func stopRecordingToFile() -> URL? {
        // Stop engine first — this flushes remaining buffers through the tap
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        // Small delay to ensure the last tap callback finishes writing
        // Then close file handles
        audioFile = nil
        audioConverter = nil
        rmsLevel = 0.0
        smoothedRMS = 0.0

        let url = recordingURL
        recordingURL = nil
        return url
    }

    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        // Cancel any pending finalization
        stopTimeoutItem?.cancel()
        stopTimeoutItem = nil
        stopCompletion = nil

        rmsLevel = 0.0
        smoothedRMS = 0.0
    }

    /// Stops audio capture and waits for the speech recognizer to deliver its final result.
    /// Falls back to partial text after a timeout.
    func stopAndFinalize(completion: @escaping (String) -> Void) {
        // Stop audio capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Signal end of audio — let recognizer finish processing
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        rmsLevel = 0.0
        smoothedRMS = 0.0

        // If final result already available, return immediately
        if !finalText.isEmpty {
            recognitionTask?.cancel()
            recognitionTask = nil
            completion(finalText)
            return
        }

        // Wait for recognizer to deliver final result, with timeout fallback
        stopCompletion = completion

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let cb = self.stopCompletion else { return }
            self.stopCompletion = nil
            self.stopTimeoutItem = nil
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            cb(self.partialText)
        }
        stopTimeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeout)
    }

    /// Returns the current transcription text (final if available, otherwise partial).
    func currentText() -> String {
        finalText.isEmpty ? partialText : finalText
    }

    // MARK: - Recognition Task Management

    private func startRecognitionTask() {
        guard let speechRecognizer, let request = recognitionRequest else { return }

        recognitionGeneration += 1
        let generation = recognitionGeneration

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard generation == self.recognitionGeneration else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async {
                    guard generation == self.recognitionGeneration else { return }

                    self.partialText = text
                    if isFinal {
                        self.finalText = self.partialText
                        if let cb = self.stopCompletion {
                            self.stopTimeoutItem?.cancel()
                            self.stopTimeoutItem = nil
                            self.stopCompletion = nil
                            self.recognitionTask?.cancel()
                            self.recognitionTask = nil
                            cb(self.finalText)
                        }
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    return
                }
                print("[AudioEngine] Recognition error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - RMS Computation

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return 0.0 }

        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let minDb: Float = -60.0
        let db = 20.0 * log10(max(rms, 1e-6))
        let normalized = max(0, (db - minDb) / (-minDb))
        return min(1.0, normalized)
    }

    private func updateRMS(_ rawRMS: Float) {
        if rawRMS > smoothedRMS {
            smoothedRMS = smoothedRMS + attackRate * (rawRMS - smoothedRMS)
        } else {
            smoothedRMS = smoothedRMS + releaseRate * (rawRMS - smoothedRMS)
        }
        rmsLevel = smoothedRMS
    }
}

enum AudioEngineError: LocalizedError {
    case speechRecognizerUnavailable
    case noMicrophoneInput

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available for the selected language."
        case .noMicrophoneInput:
            return "No microphone input detected."
        }
    }
}
