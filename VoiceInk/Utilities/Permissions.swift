import AppKit
import AVFoundation
import Speech

enum Permissions {
    static func requestAll() {
        requestAccessibility()
        requestMicrophone()
        requestSpeechRecognition()
    }

    // MARK: - Accessibility (required for CGEvent tap + simulated keystrokes)

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Microphone

    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    showPermissionAlert(
                        title: "Microphone Access Required",
                        message: "VoiceInk needs microphone access to record speech. Please grant access in System Settings > Privacy & Security > Microphone."
                    )
                }
            }
        }
    }

    // MARK: - Speech Recognition

    static func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                DispatchQueue.main.async {
                    showPermissionAlert(
                        title: "Speech Recognition Access Required",
                        message: "VoiceInk needs speech recognition access to transcribe your voice. Please grant access in System Settings > Privacy & Security > Speech Recognition."
                    )
                }
            }
        }
    }

    // MARK: - Alert

    private static func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
