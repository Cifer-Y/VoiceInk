import Foundation
import whisper
import AVFoundation

/// Local Whisper speech-to-text service using whisper.cpp.
/// Manages model download, loading, and audio transcription.
final class WhisperService {
    private var context: OpaquePointer? // whisper_context

    enum WhisperError: LocalizedError {
        case modelNotFound
        case modelLoadFailed
        case transcriptionFailed
        case audioLoadFailed

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "Whisper model not downloaded."
            case .modelLoadFailed: return "Failed to load Whisper model."
            case .transcriptionFailed: return "Whisper transcription failed."
            case .audioLoadFailed: return "Failed to load audio file."
            }
        }
    }

    // MARK: - Model Management

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceInk/Models", isDirectory: true)
    }()

    static func modelPath(for size: String) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(size).bin")
    }

    static func isModelDownloaded(_ size: String) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: size).path)
    }

    static func deleteModel(_ size: String) {
        try? FileManager.default.removeItem(at: modelPath(for: size))
    }

    /// Downloads a Whisper model from Hugging Face. Returns progress via callback.
    static func downloadModel(
        size: String,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Result<URL, Error>) -> Void
    ) {
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(size).bin"
        guard let url = URL(string: urlString) else {
            onComplete(.failure(WhisperError.modelNotFound))
            return
        }

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = modelPath(for: size)
        let delegate = DownloadDelegate(onProgress: onProgress) { tempURL, error in
            if let error {
                onComplete(.failure(error))
                return
            }
            guard let tempURL else {
                onComplete(.failure(WhisperError.modelNotFound))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                onComplete(.success(destination))
            } catch {
                onComplete(.failure(error))
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
    }

    // MARK: - Model Loading

    func loadModel(size: String) throws {
        if context != nil { return } // Already loaded

        let path = Self.modelPath(for: size)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WhisperError.modelNotFound
        }

        let params = whisper_context_default_params()
        let ctx = path.path.withCString { cPath in
            whisper_init_from_file_with_params(cPath, params)
        }
        guard let ctx else {
            throw WhisperError.modelLoadFailed
        }
        self.context = ctx
    }

    func unloadModel() {
        if let context {
            whisper_free(context)
        }
        context = nil
    }

    var isModelLoaded: Bool { context != nil }

    // MARK: - Transcription

    /// Transcribes a 16kHz mono WAV file to text.
    /// - Parameters:
    ///   - audioURL: Path to 16kHz mono WAV file.
    ///   - language: Locale string (e.g. "zh-CN").
    ///   - initialPrompt: Optional prompt to bias Whisper's decoder toward specific vocabulary.
    func transcribe(audioURL: URL, language: String, initialPrompt: String = "") throws -> String {
        guard let context else { throw WhisperError.modelLoadFailed }

        // Load audio samples (16kHz mono float32)
        let samples = try loadAudioSamples(from: audioURL)
        guard !samples.isEmpty else { return "" }

        // Configure whisper params
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(ProcessInfo.processInfo.activeProcessorCount - 2, 2))
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_non_speech_tokens = true
        params.translate = false
        params.single_segment = false
        params.no_timestamps = true

        // Set language (map locale to Whisper language code)
        let langCode = whisperLanguage(from: language)

        // Run whisper_full inside nested withCString blocks to keep C pointers alive
        let langResult: Int32
        if initialPrompt.isEmpty {
            langResult = langCode.withCString { cLang in
                params.language = cLang
                return samples.withUnsafeBufferPointer { buffer in
                    whisper_full(context, params, buffer.baseAddress, Int32(samples.count))
                }
            }
        } else {
            langResult = langCode.withCString { cLang in
                initialPrompt.withCString { cPrompt in
                    params.language = cLang
                    params.initial_prompt = cPrompt
                    return samples.withUnsafeBufferPointer { buffer in
                        whisper_full(context, params, buffer.baseAddress, Int32(samples.count))
                    }
                }
            }
        }

        guard langResult == 0 else {
            throw WhisperError.transcriptionFailed
        }

        // Collect segments
        let nSegments = whisper_full_n_segments(context)
        var result = ""
        for i in 0..<nSegments {
            if let cText = whisper_full_get_segment_text(context, i) {
                result += String(cString: cText)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audio Loading

    /// Loads audio from a file and converts to 16kHz mono Float32 samples.
    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WhisperError.audioLoadFailed
        }

        // Target format: 16kHz mono float32
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw WhisperError.audioLoadFailed
        }

        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        // Read source audio
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw WhisperError.audioLoadFailed
        }
        try file.read(into: sourceBuffer)

        // Convert to 16kHz mono if needed
        if sourceFormat.sampleRate == 16000 && sourceFormat.channelCount == 1 {
            guard let channelData = sourceBuffer.floatChannelData else { throw WhisperError.audioLoadFailed }
            return Array(UnsafeBufferPointer(start: channelData[0], count: Int(sourceBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw WhisperError.audioLoadFailed
        }

        let ratio = 16000.0 / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw WhisperError.audioLoadFailed
        }

        var isDone = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if isDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            isDone = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError, withInputFrom: inputBlock)
        if let conversionError { throw conversionError }

        guard let channelData = convertedBuffer.floatChannelData else { throw WhisperError.audioLoadFailed }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
    }

    // MARK: - Helpers

    private func whisperLanguage(from locale: String) -> String {
        // "zh-CN" -> "zh", "en-US" -> "en", "ja-JP" -> "ja"
        String(locale.prefix(2))
    }

    deinit {
        unloadModel()
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onFinish: (URL?, Error?) -> Void

    init(onProgress: @escaping (Double) -> Void, onFinish: @escaping (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onFinish(location, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onFinish(nil, error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress(progress) }
    }
}
