import Foundation
import Observation

/// Tracks usage statistics for VoiceInk, persisted in UserDefaults.
@Observable
final class UsageStats {
    private let defaults = UserDefaults.standard

    var totalRecordings: Int {
        didSet { defaults.set(totalRecordings, forKey: "stats.totalRecordings") }
    }
    var todayRecordings: Int {
        didSet { defaults.set(todayRecordings, forKey: "stats.todayRecordings") }
    }
    var totalRecordingSeconds: Double {
        didSet { defaults.set(totalRecordingSeconds, forKey: "stats.totalRecordingSeconds") }
    }
    var todayRecordingSeconds: Double {
        didSet { defaults.set(todayRecordingSeconds, forKey: "stats.todayRecordingSeconds") }
    }
    var manualCorrectionCount: Int {
        didSet { defaults.set(manualCorrectionCount, forKey: "stats.manualCorrectionCount") }
    }
    var composingCount: Int {
        didSet { defaults.set(composingCount, forKey: "stats.composingCount") }
    }
    var lastRecordingDate: String {
        didSet { defaults.set(lastRecordingDate, forKey: "stats.lastRecordingDate") }
    }

    init() {
        self.totalRecordings = defaults.integer(forKey: "stats.totalRecordings")
        self.todayRecordings = defaults.integer(forKey: "stats.todayRecordings")
        self.totalRecordingSeconds = defaults.double(forKey: "stats.totalRecordingSeconds")
        self.todayRecordingSeconds = defaults.double(forKey: "stats.todayRecordingSeconds")
        self.manualCorrectionCount = defaults.integer(forKey: "stats.manualCorrectionCount")
        self.composingCount = defaults.integer(forKey: "stats.composingCount")
        self.lastRecordingDate = defaults.string(forKey: "stats.lastRecordingDate") ?? ""
        resetTodayIfNeeded()
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func resetTodayIfNeeded() {
        if lastRecordingDate != todayString {
            todayRecordings = 0
            todayRecordingSeconds = 0
            lastRecordingDate = todayString
        }
    }

    func recordSession(duration: TimeInterval) {
        resetTodayIfNeeded()
        totalRecordings += 1
        todayRecordings += 1
        totalRecordingSeconds += duration
        todayRecordingSeconds += duration
    }

    func recordManualCorrection() {
        manualCorrectionCount += 1
    }

    func recordComposing() {
        composingCount += 1
    }

    var formattedTodayDuration: String {
        formatDuration(todayRecordingSeconds)
    }

    var formattedTotalDuration: String {
        formatDuration(totalRecordingSeconds)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
