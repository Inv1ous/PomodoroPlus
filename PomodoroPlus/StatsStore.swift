import Foundation
import Combine

/// Manages stats logging and summaries
class StatsStore: ObservableObject {
    
    @Published private(set) var todaySummary = StatsSummary.empty
    @Published private(set) var weekSummary = StatsSummary.empty
    @Published private(set) var allTimeSummary = StatsSummary.empty
    
    private let appHome: AppHome
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    /// Serial queue for stats I/O and aggregation
    private let workQueue = DispatchQueue(label: "com.PomodoroPlus.stats", qos: .utility)
    
    private var allEntries: [StatsEntry] = []
    
    init(appHome: AppHome) {
        self.appHome = appHome
    }
    
    // MARK: - Load
    
    func load() {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.loadAllEntries()
            let summaries = self.computeSummaries()
            DispatchQueue.main.async {
                self.applySummaries(summaries)
            }
        }
    }
    
    private func loadAllEntries() {
        allEntries = []
        
        let url = appHome.statsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let entry = try? decoder.decode(StatsEntry.self, from: data) {
                allEntries.append(entry)
            }
        }
    }
    
    // MARK: - Log
    
    func log(
        profileId: String,
        phase: TimerPhase,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        skipped: Bool,
        strictMode: Bool
    ) {
        let entry = StatsEntry.create(
            profileId: profileId,
            phase: phase,
            plannedSeconds: plannedSeconds,
            actualSeconds: actualSeconds,
            completed: completed,
            skipped: skipped,
            strictMode: strictMode
        )

        // Do I/O + summary computation off-main
        workQueue.async { [weak self] in
            guard let self = self else { return }

            // Append to file
            self.appendToFile(entry)

            // Update in-memory data
            self.allEntries.append(entry)

            // Publish summaries on main
            let summaries = self.computeSummaries()
            DispatchQueue.main.async {
                self.applySummaries(summaries)
            }
        }
    }

private func appendToFile(_ entry: StatsEntry) {
        guard let data = try? encoder.encode(entry),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        // Remove newlines from JSON for JSONL format
        let line = jsonString.replacingOccurrences(of: "\n", with: "") + "\n"
        
        let url = appHome.statsFileURL
        
        if let fileHandle = FileHandle(forWritingAtPath: url.path) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                fileHandle.write(lineData)
            }
        } else {
            // File doesn't exist, create it
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Summaries
    
    private func updateSummaries() {
        // Called from potentially non-main threads (eg. timer / background work). Keep computation off-main,
        // then publish summaries on main to satisfy SwiftUI thread-safety.
        let summaries = computeSummaries()
        DispatchQueue.main.async { [weak self] in
            self?.applySummaries(summaries)
        }
    }

    /// Pure computation of summaries from current entries (safe to call from background queues)
    private func computeSummaries() -> (today: StatsSummary, week: StatsSummary, allTime: StatsSummary) {
        let now = Date()
        let calendar = Calendar.current

        // Today
        let todayStart = calendar.startOfDay(for: now)
        let todayEntries = allEntries.filter { entry in
            guard let date = parseDate(entry.ts) else { return false }
            return date >= todayStart
        }
        let today = computeSummary(from: todayEntries)

        // This week
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let weekEntries = allEntries.filter { entry in
            guard let date = parseDate(entry.ts) else { return false }
            return date >= weekStart
        }
        let week = computeSummary(from: weekEntries)

        // All time
        let allTime = computeSummary(from: allEntries)

        return (today: today, week: week, allTime: allTime)
    }

    @MainActor
    private func applySummaries(_ summaries: (today: StatsSummary, week: StatsSummary, allTime: StatsSummary)) {
        todaySummary = summaries.today
        weekSummary = summaries.week
        allTimeSummary = summaries.allTime
    }

    private func computeSummary(from entries: [StatsEntry]) -> StatsSummary {
        var summary = StatsSummary()
        
        for entry in entries where entry.phase == .work {
            summary.totalSessions += 1
            
            if entry.completed {
                summary.completedSessions += 1
                summary.totalFocusMinutes += entry.actualSeconds / 60
            }
            
            if entry.skipped {
                summary.skippedSessions += 1
            }
        }
        
        return summary
    }
    
    private func parseDate(_ ts: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: ts)
    }
    
    // MARK: - Query Helpers
    
    func entries(for profileId: String) -> [StatsEntry] {
        allEntries.filter { $0.profileId == profileId }
    }
    
    func recentEntries(limit: Int = 10) -> [StatsEntry] {
        Array(allEntries.suffix(limit).reversed())
    }
}
