import SwiftUI
import AppKit

// MARK: - Stat Row (list-style: label left, value right)

private struct StatRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)
        }
        .padding(.top, 6)
    }
}

// MARK: - Stats View

struct StatsView: View {
    let stats: UsageStats

    private let accent = Color(red: 0xF0 / 255.0, green: 0x9F / 255.0, blue: 0x47 / 255.0)

    var body: some View {
        VStack(spacing: 14) {
            // Hero: today vs all time
            HStack(spacing: 0) {
                heroNumber(value: "\(stats.todayRecordings)", label: "Today", highlight: true)
                Divider().frame(height: 40).padding(.horizontal, 16)
                heroNumber(value: "\(stats.totalRecordings)", label: "All Time", highlight: false)
            }
            .padding(.vertical, 12)

            // Recording section
            SectionHeader(title: "Recording")
            StatRow(title: "Recording Time", value: stats.formattedTotalDuration, icon: "clock")
            StatRow(title: "Today's Time", value: stats.formattedTodayDuration, icon: "sun.max")
            StatRow(title: "Today's Chars", value: formatted(stats.todayCharacters), icon: "character.cursor.ibeam")
            StatRow(title: "Total Chars", value: formatted(stats.totalCharacters), icon: "text.justify.left")

            // Performance section
            SectionHeader(title: "Performance")
            StatRow(title: "Avg Response Time", value: stats.avgLatency, icon: "bolt")

            // AI Quality section
            SectionHeader(title: "AI Quality")
            StatRow(title: "LLM Accuracy", value: stats.llmAcceptanceRate, icon: "checkmark.seal")
            StatRow(title: "Manual Corrections", value: "\(stats.manualCorrectionCount)", icon: "pencil")
            StatRow(title: "Long Text Sessions", value: "\(stats.composingCount)", icon: "text.bubble")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 340)
    }

    private func heroNumber(value: String, label: String, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ? accent : .primary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Window Controller

final class StatsWindowController {
    private var window: NSWindow?

    func show(stats: UsageStats) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = StatsView(stats: stats)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 490)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 490),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Usage Stats"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
