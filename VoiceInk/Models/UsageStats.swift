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
    var llmRefinements: Int {
        didSet { defaults.set(llmRefinements, forKey: "stats.llmRefinements") }
    }
    var hallucinationsCaught: Int {
        didSet { defaults.set(hallucinationsCaught, forKey: "stats.hallucinationsCaught") }
    }
    var todayCharacters: Int {
        didSet { defaults.set(todayCharacters, forKey: "stats.todayCharacters") }
    }
    var totalCharacters: Int {
        didSet { defaults.set(totalCharacters, forKey: "stats.totalCharacters") }
    }
    var totalLatencyMs: Double {
        didSet { defaults.set(totalLatencyMs, forKey: "stats.totalLatencyMs") }
    }
    var latencySamples: Int {
        didSet { defaults.set(latencySamples, forKey: "stats.latencySamples") }
    }
    var totalConfidence: Double {
        didSet { defaults.set(totalConfidence, forKey: "stats.totalConfidence") }
    }
    var confidenceSamples: Int {
        didSet { defaults.set(confidenceSamples, forKey: "stats.confidenceSamples") }
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
        self.llmRefinements = defaults.integer(forKey: "stats.llmRefinements")
        self.hallucinationsCaught = defaults.integer(forKey: "stats.hallucinationsCaught")
        self.todayCharacters = defaults.integer(forKey: "stats.todayCharacters")
        self.totalCharacters = defaults.integer(forKey: "stats.totalCharacters")
        self.totalLatencyMs = defaults.double(forKey: "stats.totalLatencyMs")
        self.latencySamples = defaults.integer(forKey: "stats.latencySamples")
        self.totalConfidence = defaults.double(forKey: "stats.totalConfidence")
        self.confidenceSamples = defaults.integer(forKey: "stats.confidenceSamples")
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
            todayCharacters = 0
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

    func recordLLMRefinement() {
        llmRefinements += 1
    }

    func recordHallucination() {
        hallucinationsCaught += 1
    }

    func recordCharacters(_ count: Int) {
        resetTodayIfNeeded()
        todayCharacters += count
        totalCharacters += count
    }

    func recordLatency(_ ms: Double) {
        totalLatencyMs += ms
        latencySamples += 1
    }

    func recordConfidence(_ avg: Float) {
        totalConfidence += Double(avg)
        confidenceSamples += 1
    }

    /// Average end-to-end latency (recording stop → text injected).
    var avgLatency: String {
        guard latencySamples > 0 else { return "—" }
        let avg = totalLatencyMs / Double(latencySamples)
        return avg < 1000 ? String(format: "%.0fms", avg) : String(format: "%.1fs", avg / 1000)
    }

    /// Average Whisper confidence score (0–100%).
    var avgConfidence: String {
        guard confidenceSamples > 0 else { return "—" }
        let avg = totalConfidence / Double(confidenceSamples) * 100
        return String(format: "%.0f%%", avg)
    }

    /// LLM acceptance rate: percentage of refinements accepted without manual correction.
    var llmAcceptanceRate: String {
        guard llmRefinements > 0 else { return "—" }
        let accepted = llmRefinements - manualCorrectionCount
        let rate = Double(max(accepted, 0)) / Double(llmRefinements) * 100
        return String(format: "%.0f%%", rate)
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
