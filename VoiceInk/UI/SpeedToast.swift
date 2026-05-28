import AppKit
import SwiftUI

// MARK: - Speed Toast View

private struct SpeedToastView: View {
    let charCount: Int
    let cpm: Int

    private let accent = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)

    private var speedTier: (emoji: String, label: String) {
        switch cpm {
        case ..<80:  return ("🐢", "Casual")
        case ..<150: return ("🚶", "Steady")
        case ..<250: return ("🏃", "Fast")
        case ..<400: return ("⚡", "Blazing")
        default:     return ("🔥", "On Fire")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(speedTier.emoji)
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(cpm) chars/min")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("\(charCount) chars · \(speedTier.label)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

// MARK: - Speed Toast Controller

final class SpeedToast {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(charCount: Int, cpm: Int) {
        dismiss()

        let view = SpeedToastView(charCount: charCount, cpm: cpm)
        let hosting = NSHostingView(rootView: view)
        let fittingSize = hosting.fittingSize
        let panelW = fittingSize.width
        let panelH = fittingSize.height
        hosting.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position: top-center of screen (where the HUD was)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelW / 2
            let y = screenFrame.maxY - panelH - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel

        // Slide down from above
        panel.alphaValue = 0
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 20))
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }

        // Auto-dismiss after 2 seconds
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
        })
    }
}
