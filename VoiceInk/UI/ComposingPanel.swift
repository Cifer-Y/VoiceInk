import AppKit
import SwiftUI

/// Persistent panel for long-text composing mode.
/// Stays visible while user records multiple segments. Shows accumulated text
/// with confirm/cancel actions.
final class ComposingPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    private var text: String = ""
    private var rmsLevel: Float = 0.0
    private var isRecording: Bool = false

    var onConfirm: ((String) -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        if panel != nil {
            updateContent()
            return
        }

        let hosting = NSHostingView(rootView: makeContentView())
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 160)
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = hosting
        self.panel = panel

        positionPanel()

        // Entrance animation
        panel.alphaValue = 0
        panel.setFrame(panel.frame.offsetBy(dx: 0, dy: -20), display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 20), display: true)
        }
    }

    func dismiss() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
            self?.text = ""
            self?.isRecording = false
        })
    }

    func updateText(_ newText: String) {
        text = newText
        updateContent()
        resizePanel()
    }

    func updateRMS(_ level: Float) {
        rmsLevel = level
        updateContent()
    }

    func setRecording(_ recording: Bool) {
        isRecording = recording
        updateContent()
    }

    func currentText() -> String {
        text
    }

    // MARK: - Private

    private func makeContentView() -> AnyView {
        AnyView(
            ComposingContentView(
                text: text,
                rmsLevel: rmsLevel,
                isRecording: isRecording,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.onConfirm?(self.text)
                },
                onCancel: { [weak self] in
                    self?.onCancel?()
                }
            )
        )
    }

    private func updateContent() {
        hostingView?.rootView = makeContentView()
    }

    private func resizePanel() {
        guard let panel else { return }

        let font = NSFont.systemFont(ofSize: 14)
        let textWidth: CGFloat = 360 // 400 - padding
        let boundingRect = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        // Text height + top bar (40) + bottom bar (44) + padding (24)
        let newHeight = max(160, min(ceil(boundingRect.height) + 108, 400))
        let currentFrame = panel.frame

        guard abs(currentFrame.height - newHeight) > 1 else { return }

        let newY = currentFrame.minY + currentFrame.height - newHeight
        let newFrame = NSRect(x: currentFrame.minX, y: newY, width: 400, height: newHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
