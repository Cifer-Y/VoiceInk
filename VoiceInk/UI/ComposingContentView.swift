import SwiftUI

/// Content view for the composing (long-text) panel.
/// Shows accumulated text with recording indicator and confirm/cancel buttons.
struct ComposingContentView: View {
    let text: String
    let rmsLevel: Float
    let isRecording: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: mode label + recording indicator
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0))
                Text("Long Text Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if isRecording {
                    WaveformView(rmsLevel: rmsLevel)
                        .frame(width: 44, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.3)

            // Text area
            ScrollView {
                Group {
                    if text.isEmpty {
                        Text("Hold Right Option to record. Release to add text.\nDouble-tap Right Option to confirm.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    } else {
                        Text(text)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.3)

            // Bottom bar: cancel + confirm buttons
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .frame(width: 70)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Esc to cancel, Double-tap ⌃R to confirm")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 70)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .opacity(text.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 12))
    }
}
