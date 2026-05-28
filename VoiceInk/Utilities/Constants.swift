import Foundation

enum Constants {
    static let bundleIdentifier = "com.cifer.VoiceInk"
    static let rightOptionKeyCode: UInt16 = 61
    static let shortPressDuration: TimeInterval = 0.2 // 200ms threshold

    // Correction tap window: after injection, user has this many seconds to tap for correction
    static let correctionTapWindow: TimeInterval = 3.0

    static var appSupportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceInk")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var correctionsFilePath: URL {
        appSupportDirectory.appendingPathComponent("corrections.json")
    }

    static var userDictionaryFilePath: URL {
        appSupportDirectory.appendingPathComponent("user_dictionary.json")
    }

    static let maxCorrectionEntries = 200

    static let supportedLocales: [(id: String, name: String)] = [
        ("zh-CN", "简体中文"),
        ("en-US", "English"),
        ("zh-TW", "繁體中文"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
    ]

    static let doubleTapInterval: TimeInterval = 0.4

    // System prompt for LLM refinement (single sentence mode)
    static let llmSystemPrompt = """
    Fix speech recognition errors in Chinese text. Output ONLY the corrected text.

    Priority: fix wrong homophones using context.
    Examples: 就错→纠错, 配森→Python, 模形→模型, 因该→应该, 按门→安门.

    Also: remove fillers (嗯/啊/呃/那个), fix punctuation, convert Chinese phonetic \
    transcriptions of English terms to English. Keep original meaning — do not rephrase.

    Words marked as {word|score} have low speech recognition confidence and are likely \
    wrong. Focus on fixing these first. Unmarked words are high-confidence — avoid \
    changing them unless clearly wrong.

    [pause] marks a significant speech pause. Use it to decide sentence boundaries and \
    punctuation placement (period, comma, paragraph break).
    """

    // System prompt for LLM refinement (long-text composing mode)
    static let llmComposingPrompt = """
    Clean up raw speech-to-text into well-written text. Output ONLY the result.

    1. Fix homophones using context (大圆模型→大语言模型, 交货→交互, 常本→长文本). \
    Convert Chinese phonetic English terms to English (配森→Python, 四欧→4o).
    2. Handle self-corrections: "不是X是Y" / "其实我想说的是Y" → use Y, discard X.
    3. Remove all fillers (嗯/啊/呃), false starts, and repeated attempts.
    4. Reorganize into clear paragraphs. Rephrase freely for clarity, but preserve meaning.

    Words marked as {word|score} have low speech recognition confidence and are likely \
    wrong. Focus on fixing these first. Unmarked words are high-confidence — avoid \
    changing them unless clearly wrong.

    [pause] marks a significant speech pause. Use it to decide sentence/paragraph boundaries.
    """
}
