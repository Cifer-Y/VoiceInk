import AppKit
import SwiftUI

/// Observable state object that drives HUD content from outside SwiftUI.
final class HUDState: ObservableObject {
    @Published var rmsLevel: Float = 0
    @Published var text: String = ""
    @Published var status: HUDContentView.HUDStatus = .recording
    @Published var compactMode: Bool = false
    @Published var speedLabel: String = ""  // e.g. "128 chars/min"
}

/// Wrapper view that observes HUDState and animates transitions.
struct HUDRootView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HUDContentView(
            rmsLevel: state.rmsLevel,
            text: state.text,
            status: state.status,
            compactMode: state.compactMode,
            speedLabel: state.speedLabel
        )
    }
}

/// Floating capsule HUD panel that displays during recording.
/// Uses a fixed-size transparent NSPanel; all layout and animation
/// is handled by SwiftUI inside.
final class HUDPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDRootView>?
    private let hudState = HUDState()

    // Panel is always this size — SwiftUI content animates within it
    private static let panelSize = NSSize(width: 360, height: 160)

    func show() {
        if panel != nil { return }

        let rootView = HUDRootView(state: hudState)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = hosting
        self.panel = panel

        positionPanel()

        // Entrance animation
        panel.alphaValue = 0
        panel.setFrame(
            panel.frame.offsetBy(dx: 0, dy: -20),
            display: false
        )
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(
                panel.frame.offsetBy(dx: 0, dy: 20),
                display: true
            )
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
        })
    }

    func updateRMS(_ level: Float) {
        hudState.rmsLevel = level
    }

    func updateText(_ newText: String) {
        hudState.text = newText
    }

    func setStatus(_ newStatus: HUDContentView.HUDStatus) {
        hudState.status = newStatus
    }

    func setCompactMode(_ compact: Bool) {
        hudState.compactMode = compact
    }

    func setSpeedLabel(_ label: String) {
        hudState.speedLabel = label
    }

    // MARK: - Private

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.minY + 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
