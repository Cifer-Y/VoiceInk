import SwiftUI

/// Audio-reactive fluid orb visualization.
/// A glowing blob that morphs and pulses with audio RMS levels.
/// Uses layered distorted circles for an organic, Siri-like effect.
struct AudioOrbView: View {
    let rmsLevel: Float
    let size: CGFloat
    var lightStyle: Bool = false

    @State private var smoothLevel: CGFloat = 0

    private let accent = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let baseRadius = size * 0.32
                // Idle breathing: gentle pulse even when silent
                let breath = CGFloat(0.08 + 0.04 * sin(t * 1.8))
                let level = max(smoothLevel, breath)

                // Draw 3 blob layers with different phases for depth
                let layers: [(opacity: Double, scale: CGFloat, phaseOffset: Double)] = lightStyle ? [
                    (0.2, 1.25, 0.0),
                    (0.35, 1.1, 1.0),
                    (0.5, 1.0, 2.0),
                ] : [
                    (0.15, 1.25, 0.0),   // outer glow
                    (0.3, 1.1, 1.0),     // mid layer
                    (0.7, 1.0, 2.0),     // core
                ]

                for layer in layers {
                    let path = blobPath(
                        center: center,
                        radius: baseRadius * layer.scale + baseRadius * level * 0.3,
                        time: t,
                        phaseOffset: layer.phaseOffset,
                        amplitude: level
                    )
                    context.fill(path, with: .color(accent.opacity(layer.opacity)))
                }

                // Bright center highlight
                let highlightRadius = baseRadius * 0.4 * (1.0 + level * 0.2)
                let highlightRect = CGRect(
                    x: center.x - highlightRadius,
                    y: center.y - highlightRadius,
                    width: highlightRadius * 2,
                    height: highlightRadius * 2
                )
                context.fill(Ellipse().path(in: highlightRect), with: .color(.white.opacity(0.15 + Double(level) * 0.1)))
            }
            .frame(width: size, height: size)
        }
        .onChange(of: rmsLevel) { _, newValue in
            let target = CGFloat(newValue)
            smoothLevel += (target - smoothLevel) * 0.35
        }
    }

    /// Generates a smooth blob path using superimposed sine distortions.
    private func blobPath(center: CGPoint, radius: CGFloat, time: Double, phaseOffset: Double, amplitude: CGFloat) -> Path {
        Path { path in
            let points = 60
            let amp = radius * 0.15 * amplitude

            for i in 0...points {
                let angle = Double(i) / Double(points) * .pi * 2

                // Three frequency distortions for organic shape
                let d1 = sin(angle * 3 + time * 2.5 + phaseOffset) * amp
                let d2 = sin(angle * 5 + time * 3.8 + phaseOffset * 1.5) * amp * 0.5
                let d3 = cos(angle * 2 + time * 1.7 + phaseOffset * 0.7) * amp * 0.3

                let r = radius + d1 + d2 + d3
                let x = center.x + CGFloat(cos(angle)) * r
                let y = center.y + CGFloat(sin(angle)) * r

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
    }
}

/// Bar-style waveform for Apple Speech capsule mode.
struct WaveformBarsView: View {
    let rmsLevel: Float

    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 36

    @State private var smoothLevel: CGFloat = 0

    private let accentColor = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight(for: index, time: timeline.date.timeIntervalSinceReferenceDate))
                }
            }
            .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing, height: 40)
        }
        .onChange(of: rmsLevel) { _, newValue in
            smoothLevel += (CGFloat(newValue) - smoothLevel) * 0.4
        }
    }

    private func barHeight(for index: Int, time: Double) -> CGFloat {
        let level = max(smoothLevel, 0.03)
        let norm = Double(index) / Double(barCount - 1)
        let arch = 1.0 - pow(norm * 2.0 - 1.0, 2) * 0.45
        let wave1 = (sin(time * 4.0 + Double(index) * 0.9) + 1.0) / 2.0
        let wave2 = (sin(time * 6.5 + Double(index) * 1.5) + 1.0) / 2.0
        let combined = arch * (0.4 + 0.4 * wave1 + 0.2 * wave2)
        let height = minBarHeight + (maxBarHeight - minBarHeight) * level * CGFloat(combined)
        return min(max(height, minBarHeight), maxBarHeight)
    }
}

// Keep WaveformView as alias for backward compatibility with ComposingPanel
typealias WaveformView = WaveformBarsView
