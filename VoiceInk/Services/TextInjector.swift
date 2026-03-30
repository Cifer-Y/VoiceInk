import AppKit
import CoreGraphics

/// Injects text into the currently focused input field via clipboard + Cmd+V.
/// Handles CJK input method switching and clipboard restoration.
enum TextInjector {

    static func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents
        let savedContents = saveClipboard(pasteboard)

        // 2. Check if CJK input method is active, switch to ASCII if needed
        let wasCJK = InputMethodHelper.isCJKInputMethod()
        var previousInputSourceID: String?
        if wasCJK {
            previousInputSourceID = InputMethodHelper.switchToASCII()
        }

        // 3. Write text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        usleep(30_000) // 30ms

        // 4. Simulate Cmd+V
        simulatePaste()

        // 5. Restore input method after paste
        if wasCJK, let previousID = previousInputSourceID {
            // Delay before restoring to let paste complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                InputMethodHelper.restoreInputSource(id: previousID)
            }
        }

        // 6. Restore original clipboard contents after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            restoreClipboard(pasteboard, contents: savedContents)
        }
    }

    // MARK: - Clipboard Save/Restore

    private struct ClipboardItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private static func saveClipboard(_ pasteboard: NSPasteboard) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        guard let types = pasteboard.types else { return items }

        for type in types {
            if let data = pasteboard.data(forType: type) {
                items.append(ClipboardItem(type: type, data: data))
            }
        }
        return items
    }

    private static func restoreClipboard(_ pasteboard: NSPasteboard, contents: [ClipboardItem]) {
        guard !contents.isEmpty else { return }
        pasteboard.clearContents()
        for item in contents {
            pasteboard.setData(item.data, forType: item.type)
        }
    }


    // MARK: - Simulate Cmd+V

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
