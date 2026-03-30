import SwiftUI
import AppKit

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StatsView: View {
    let stats: UsageStats

    private let accentOrange = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(accentOrange)
                Text("Usage Stats")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }

            // Today highlight
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("\(stats.todayRecordings)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(accentOrange)
                    Text("Today")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accentOrange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text("\(stats.totalRecordings)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("All Time")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Detail cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatCard(
                    icon: "clock.fill",
                    title: "Recording Time",
                    value: stats.formattedTotalDuration,
                    color: .green
                )
                StatCard(
                    icon: "sun.max.fill",
                    title: "Today's Time",
                    value: stats.formattedTodayDuration,
                    color: .purple
                )
                StatCard(
                    icon: "pencil.circle.fill",
                    title: "Corrections",
                    value: "\(stats.manualCorrectionCount)",
                    color: .pink
                )
                StatCard(
                    icon: "text.bubble.fill",
                    title: "Long Text",
                    value: "\(stats.composingCount)",
                    color: accentOrange
                )
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

final class StatsWindowController {
    private var window: NSWindow?

    func show(stats: UsageStats) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = StatsView(stats: stats)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 340)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInk — Usage Stats"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
