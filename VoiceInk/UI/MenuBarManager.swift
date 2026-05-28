import AppKit
import SwiftUI

/// Manages the NSStatusItem and its menu.
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let settings: AppSettings
    private let correctionManager: CorrectionManager

    var onLanguageChanged: ((String) -> Void)?
    var onLLMToggled: ((Bool) -> Void)?
    var onLLMSettingsRequested: (() -> Void)?
    var onCorrectionHistoryRequested: (() -> Void)?
    var onUserDictionaryRequested: (() -> Void)?
    var onStatsRequested: (() -> Void)?
    var onQuit: (() -> Void)?

    init(settings: AppSettings, correctionManager: CorrectionManager) {
        self.settings = settings
        self.correctionManager = correctionManager
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoiceInk")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        rebuildMenu()
    }

    func updateIcon(for state: TranscriptionState) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle, .correctionReady, .composing:
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoiceInk")
        case .composingRecording, .recording:
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
        case .refining, .composingRefining:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Refining")
        case .injecting:
            button.image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Injecting")
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
        }
        button.image?.size = NSSize(width: 16, height: 16)
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Status
        let statusItem = NSMenuItem(title: "VoiceInk — Hold Right Option to record", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // Language submenu
        let languageMenu = NSMenu()
        for locale in Constants.supportedLocales {
            let item = NSMenuItem(title: locale.name, action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = locale.id
            if locale.id == settings.locale {
                item.state = .on
            }
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: "Recognition Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        // Settings
        let settingsMenuItem = NSMenuItem(title: "Settings…", action: #selector(openLLMSettings(_:)), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        menu.addItem(.separator())

        // Correction History
        let historyItem = NSMenuItem(title: "Correction History…", action: #selector(openCorrectionHistory(_:)), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        // User Dictionary
        let dictionaryItem = NSMenuItem(title: "User Dictionary…", action: #selector(openUserDictionary(_:)), keyEquivalent: "")
        dictionaryItem.target = self
        menu.addItem(dictionaryItem)

        // Usage Stats
        let statsItem = NSMenuItem(title: "Usage Stats…", action: #selector(openStats(_:)), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit VoiceInk", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let localeID = sender.representedObject as? String else { return }
        settings.locale = localeID
        onLanguageChanged?(localeID)
        rebuildMenu()
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        settings.llmEnabled.toggle()
        onLLMToggled?(settings.llmEnabled)
        rebuildMenu()
    }

    @objc private func openLLMSettings(_ sender: NSMenuItem) {
        onLLMSettingsRequested?()
    }

    @objc private func openCorrectionHistory(_ sender: NSMenuItem) {
        onCorrectionHistoryRequested?()
    }

    @objc private func openUserDictionary(_ sender: NSMenuItem) {
        onUserDictionaryRequested?()
    }

    @objc private func openStats(_ sender: NSMenuItem) {
        onStatsRequested?()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        onQuit?()
    }
}
