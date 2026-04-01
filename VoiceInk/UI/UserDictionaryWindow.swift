import SwiftUI
import AppKit

/// View for managing user dictionary entries.
struct UserDictionaryView: View {
    let entries: [UserDictionaryEntry]
    let onAdd: (UserDictionaryEntry) -> Void
    let onUpdate: (UserDictionaryEntry) -> Void
    let onDelete: (UUID) -> Void
    let onClose: () -> Void

    @State private var newTerm = ""
    @State private var editingEntry: UserDictionaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("User Dictionary")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Add terms you use often to improve recognition accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Add new entry form
            HStack(spacing: 8) {
                TextField("e.g. Claude, Kubernetes, VoiceInk", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addEntry() }

                Button("Add") {
                    addEntry()
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            // Entry list
            if entries.isEmpty {
                Text("No dictionary entries yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            DictionaryEntryRow(
                                entry: entry,
                                isEditing: editingEntry?.id == entry.id,
                                onEdit: { editingEntry = entry },
                                onSave: { updated in
                                    onUpdate(updated)
                                    editingEntry = nil
                                },
                                onCancelEdit: { editingEntry = nil },
                                onDelete: onDelete
                            )
                        }
                    }
                }
                .frame(maxHeight: 350)
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
        .frame(width: 420)
        .frame(minHeight: 250)
    }

    private func addEntry() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        onAdd(UserDictionaryEntry(term: term))
        newTerm = ""
    }
}

struct DictionaryEntryRow: View {
    let entry: UserDictionaryEntry
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: (UserDictionaryEntry) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void

    @State private var editTerm: String = ""

    var body: some View {
        if isEditing {
            editingView
        } else {
            displayView
        }
    }

    private var displayView: some View {
        HStack {
            Text(entry.term)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Button {
                editTerm = entry.term
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                onDelete(entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var editingView: some View {
        HStack(spacing: 8) {
            TextField("Term", text: $editTerm)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveEdit() }

            Button("Save") {
                saveEdit()
            }
            .disabled(editTerm.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel") {
                onCancelEdit()
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func saveEdit() {
        var updated = entry
        updated.term = editTerm.trimmingCharacters(in: .whitespaces)
        onSave(updated)
    }
}

// MARK: - Window Controller

final class UserDictionaryWindowController {
    private var window: NSWindow?

    func show(dictionaryManager: UserDictionaryManager) {
        window?.close()

        let view = UserDictionaryView(
            entries: dictionaryManager.entries,
            onAdd: { [weak self, weak dictionaryManager] entry in
                dictionaryManager?.add(entry: entry)
                if let dm = dictionaryManager {
                    self?.show(dictionaryManager: dm)
                }
            },
            onUpdate: { [weak self, weak dictionaryManager] entry in
                dictionaryManager?.update(entry: entry)
                if let dm = dictionaryManager {
                    self?.show(dictionaryManager: dm)
                }
            },
            onDelete: { [weak self, weak dictionaryManager] id in
                dictionaryManager?.removeEntry(id: id)
                if let dm = dictionaryManager {
                    self?.show(dictionaryManager: dm)
                }
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )

        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInk — User Dictionary"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }
}
