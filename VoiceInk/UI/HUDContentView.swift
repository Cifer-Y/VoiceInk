import SwiftUI
import AppKit

/// NSVisualEffectView wrapper for SwiftUI backgrounds.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = .behindWindow
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Mini orb with a self-driven breathing pulse animation for refining state.
struct PulsingOrbView: View {
    let size: CGFloat
    @State private var pulse: Float = 0.2

    var body: some View {
        AudioOrbView(rmsLevel: pulse, size: size, lightStyle: true)
            .onAppear { startPulsing() }
    }

    private func startPulsing() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            let t = Date().timeIntervalSinceReferenceDate
            let v = sin(t * 2.2) * 0.25 + sin(t * 3.5) * 0.1
            pulse = Float(0.25 + v)
        }
    }
}

/// Content view for the floating capsule HUD.
/// Morphs between a circle (Whisper recording) and a rounded rectangle (refining/text).
struct HUDContentView: View {
    let rmsLevel: Float
    let text: String
    let status: HUDStatus
    let compactMode: Bool
    let speedLabel: String

    enum HUDStatus {
        case recording
        case refining
    }

    init(rmsLevel: Float, text: String, status: HUDStatus, compactMode: Bool = false, speedLabel: String = "") {
        self.rmsLevel = rmsLevel
        self.text = text
        self.status = status
        self.compactMode = compactMode
        self.speedLabel = speedLabel
    }

    private let accent = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)
    // Dark warm brown for readable text on orange
    private let textColor = Color(red: 0.25, green: 0.12, blue: 0.0)
    private let textColorLight = Color(red: 0.35, green: 0.18, blue: 0.0)

    private var isOrb: Bool {
        compactMode && status == .recording
    }

    // Animated shape properties
    private var shapeWidth: CGFloat { isOrb ? 130 : 340 }
    private var shapeHeight: CGFloat { isOrb ? 130 : max(56, textHeight) }
    private var shapeRadius: CGFloat { isOrb ? 65 : 20 }

    private var textHeight: CGFloat {
        guard !text.isEmpty else { return 56 }
        // Rough estimate: 20 per line, up to 6 lines
        let charPerLine = 24
        let lines = min(6, max(1, (text.count + charPerLine - 1) / charPerLine))
        return CGFloat(lines) * 20 + 30
    }

    // Orb background is slightly larger than the inner orb for the "outer ring" look
    private var orbBgSize: CGFloat { 135 }

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                // Morphing background: circle ↔ rounded rect
                RoundedRectangle(cornerRadius: shapeRadius)
                    .fill(accent.opacity(isOrb ? 0.25 : 0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: shapeRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(isOrb ? 0 : 0.6)
                    )
                    .frame(width: isOrb ? orbBgSize : shapeWidth, height: isOrb ? orbBgSize : shapeHeight)

                // Orb content
                orbContent
                    .opacity(isOrb ? 1 : 0)
                    .scaleEffect(isOrb ? 1 : 0.3)

                // Capsule content
                capsuleContent
                    .frame(width: shapeWidth)
                    .opacity(isOrb ? 0 : 1)
                    .scaleEffect(isOrb ? 0.5 : 1)
            }
            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: isOrb)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shapeHeight)
        }
        .frame(width: 360, height: 160)
    }

    // Orb content: fluid blob + time
    private var orbContent: some View {
        ZStack {
            AudioOrbView(rmsLevel: rmsLevel, size: 130)

            if !text.isEmpty {
                Text(text)
                    .font(.custom("AvenirNext-Bold", size: 20))
                    .foregroundStyle(Color(red: 0.35, green: 0.15, blue: 0.0).opacity(0.85))
                    .shadow(color: .white.opacity(0.3), radius: 2)
            }
        }
        .frame(width: 130, height: 130)
    }

    // Capsule content: indicator + text
    private var capsuleContent: some View {
        HStack(spacing: 12) {
            // Left indicator
            Group {
                switch status {
                case .recording:
                    WaveformBarsView(rmsLevel: rmsLevel)
                case .refining:
                    PulsingOrbView(size: 44)
                        .frame(width: 48, height: 48)
                }
            }

            // Right: text + optional speed label
            VStack(alignment: .leading, spacing: 4) {
                if status == .refining && text.isEmpty {
                    Text("Refining...")
                        .foregroundStyle(textColorLight)
                        .font(.custom("Avenir Next", size: 14).weight(.medium))
                } else if text.isEmpty {
                    Text("Listening...")
                        .foregroundStyle(textColorLight)
                        .font(.custom("Avenir Next", size: 14).weight(.medium))
                } else {
                    Text(text)
                        .font(.custom("Avenir Next", size: 14).weight(.regular))
                        .foregroundStyle(textColor)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !speedLabel.isEmpty {
                    Text(speedLabel)
                        .font(.custom("Avenir Next", size: 11).weight(.medium))
                        .foregroundStyle(textColorLight.opacity(0.7))
                }
            }
            .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
