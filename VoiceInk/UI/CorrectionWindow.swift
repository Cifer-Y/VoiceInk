import SwiftUI
import AppKit

/// Correction popup that appears after injection, allowing the user to fix transcription errors.
struct CorrectionView: View {
    let result: TranscriptionResult
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var editedText: String
    @FocusState private var isTextFieldFocused: Bool

    init(result: TranscriptionResult, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.result = result
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._editedText = State(initialValue: result.finalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Correct Transcription")
                .font(.headline)

            // Show ASR original if LLM refined
            if let llmText = result.llmText, llmText != result.asrText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ASR Original:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.asrText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("LLM Refined:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(llmText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Text("Edit below and confirm:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedText)
                .font(.system(size: 14))
                .frame(minHeight: 60, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3))
                )
                .focused($isTextFieldFocused)

            HStack {
                Text("⌘+Enter to confirm, Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Confirm") {
                    onConfirm(editedText)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

/// Correction History window showing recent correction entries.
struct CorrectionHistoryView: View {
    let entries: [CorrectionEntry]
    let onDelete: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Correction History")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("No corrections yet. After voice input, tap Right Option briefly to correct.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries.reversed()) { entry in
                            CorrectionEntryRow(entry: entry, onDelete: onDelete)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            HStack {
                Spacer()
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 500)
        .frame(minHeight: 200)
    }
}

struct CorrectionEntryRow: View {
    let entry: CorrectionEntry
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("(\(entry.language))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) {
                    onDelete(entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ASR:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.asrText)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Corrected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.correctedText)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Window Controllers

final class CorrectionWindowController {
    private var panel: NSPanel?

    func show(result: TranscriptionResult, onConfirm: @escaping (String) -> Void) {
        dismiss()

        let view = CorrectionView(
            result: result,
            onConfirm: { [weak self] correctedText in
                self?.dismiss()
                onConfirm(correctedText)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Correct Transcription"
        panel.contentView = hosting
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        // Position above where HUD was (bottom center, a bit higher)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 220
            let y = screenFrame.minY + 160
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

final class CorrectionHistoryWindowController {
    private var window: NSWindow?

    func show(correctionManager: CorrectionManager) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = CorrectionHistoryView(
            entries: correctionManager.entries,
            onDelete: { [weak self, weak correctionManager] id in
                correctionManager?.removeEntry(id: id)
                // Refresh the window
                if let cm = correctionManager {
                    self?.show(correctionManager: cm)
                }
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )

        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInk — Correction History"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }
}
