import Carbon
import AppKit

/// Handles CJK input method detection and temporary switching for reliable text injection.
enum InputMethodHelper {
    /// Returns the current input source ID (e.g., "com.apple.inputmethod.SCIM.ITABC").
    static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    /// Checks if the current input method is a CJK composing input method.
    static func isCJKInputMethod() -> Bool {
        guard let sourceID = currentInputSourceID() else { return false }
        let cjkPrefixes = [
            "com.apple.inputmethod.SCIM",      // Simplified Chinese
            "com.apple.inputmethod.TCIM",      // Traditional Chinese
            "com.apple.inputmethod.Kotoeri",   // Japanese
            "com.apple.inputmethod.Korean",    // Korean
            "com.apple.inputmethod.ChineseHandwriting",
            "com.sogou.inputmethod",
            "com.baidu.inputmethod",
            "com.iflytek.inputmethod",
            "com.tencent.inputmethod",
            "jp.sourceforge.inputmethod",
        ]
        return cjkPrefixes.contains { sourceID.hasPrefix($0) }
    }

    /// Switches to the ASCII-capable input source (e.g., ABC keyboard).
    /// Returns the previous input source ID for restoration.
    @discardableResult
    static func switchToASCII() -> String? {
        let previousID = currentInputSourceID()

        guard let sources = TISCreateInputSourceList(
            [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary,
            false
        )?.takeRetainedValue() as? [TISInputSource] else {
            return previousID
        }

        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            // Look for ASCII-capable sources
            if sourceID == "com.apple.keylayout.ABC" || sourceID == "com.apple.keylayout.US" {
                TISSelectInputSource(source)
                // Small delay to let the input source switch take effect
                usleep(50_000) // 50ms
                return previousID
            }
        }

        return previousID
    }

    /// Restores a previously saved input source by ID.
    static func restoreInputSource(id: String) {
        guard let sources = TISCreateInputSourceList(
            [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary,
            false
        )?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            if sourceID == id {
                TISSelectInputSource(source)
                return
            }
        }
    }
}
