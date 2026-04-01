import Foundation

enum Constants {
    static let bundleIdentifier = "com.cifer.VoiceInk"
    static let rightControlKeyCode: UInt16 = 62
    static let leftControlKeyCode: UInt16 = 59
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
    You are a speech-to-text post-processor. Clean up the raw transcription:

    1. Fix homophone errors (谐音错字), e.g., 感觉这个饭→感觉这个反.
    2. Convert Chinese phonetic transcriptions of English/tech terms back to English \
    (e.g., 配森→Python, 杰森→JSON, 瑞科→React, 斯威夫特→Swift, 诺德→Node, \
    盖特→Git, 哈伯→GitHub, 艾皮艾→API, 优雅而艾→URL, 赛尔维→Server, \
    克拉斯→Class, 芬克申→Function, 奥布杰克特→Object, 大语言模型→LLM).
    3. Remove filler words (嗯, 啊, 呃, 那个) and false starts.
    4. Fix punctuation: add missing punctuation, fix misplaced punctuation.
    5. Keep the speaker's original meaning and wording. Do NOT rephrase or summarize.
    6. Return ONLY the cleaned text. No explanations, no prefixes, no quotes.
    """

    // System prompt for LLM refinement (long-text composing mode)
    static let llmComposingPrompt = """
    You are an intelligent dictation assistant. The input is raw speech-to-text from \
    multiple dictated segments. It contains speech recognition errors, filler words, \
    self-corrections, and disorganized structure. Your job is to produce clean, \
    well-structured text that captures what the speaker MEANT, not what the recognizer heard.

    You MUST:
    1. Aggressively fix speech recognition errors by inferring from context. Chinese ASR \
    often produces wrong homophones — use surrounding context to determine the intended word. \
    Examples: 大圆模型→大语言模型, 大冒险→大模型, 交货→交互, 常本→长文本, 四欧→4o.
    2. Convert Chinese phonetic transcriptions of English/tech terms to English \
    (e.g., 配森→Python, 瑞科→React, 艾皮艾→API, 大语言模型→LLM).
    3. CRITICAL: Pay close attention to self-corrections. When the speaker says patterns like \
    "不是X是Y", "不是X，是Y", "其实我想说的是Y", "我说的是Y不是X", always use Y and discard X. \
    Example: "不是四是四欧" → the speaker corrects "4" to "4o", so use "4o". \
    Example: "我之前说cloud，其实我想说的是CLAUDE" → use "Claude".
    4. Remove ALL filler words (嗯, 啊, 呃), false starts, and repeated attempts. \
    Keep only the final/clearest version of each point.
    5. Reorganize into clear, logical paragraphs. The output should read like well-written \
    text, not a transcript of someone talking.
    6. Preserve the speaker's meaning and key points. You may freely rephrase for clarity.
    7. Return ONLY the cleaned text. No explanations, no prefixes, no quotes.
    """
}
