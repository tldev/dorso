import Foundation
import os

// MARK: - Data Models

struct DailyStats: Codable, Identifiable {
    var id: String { dayKey }
    let date: Date
    var totalSeconds: TimeInterval
    var slouchSeconds: TimeInterval
    var slouchCount: Int
    
    var dayKey: String {
        Self.dayKey(for: date)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    var postureScore: Double {
        guard totalSeconds > 0 else { return 0.0 }
        let ratio = max(0, min(1, 1.0 - (slouchSeconds / totalSeconds)))
        return ratio * 100.0
    }
}

// MARK: - Analytics Manager

class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()

    private static let logger = Logger(subsystem: "com.thelazydeveloper.dorso", category: "Analytics")
    private static let legacyMigrationFlagKey = "analyticsMigratedPosturrToDorso.v1"
    
    @Published var todayStats: DailyStats
    private var history: [String: DailyStats] = [:]
    private let fileURL: URL
    private var saveTimer: Timer?
    private var saveGeneration: UInt64 = 0
    private var lastSavedGeneration: UInt64 = 0

    private let persistenceQueue: DispatchQueue
    private let calendar: Calendar
    private let now: () -> Date
    
    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        persistenceQueue: DispatchQueue = DispatchQueue(label: "dorso.analytics.persistence", qos: .utility)
    ) {
        self.calendar = calendar
        self.now = now
        self.persistenceQueue = persistenceQueue

        let fileManager = FileManager.default
        let resolvedURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.fileURL = resolvedURL

        // Ensure directory exists
        let directoryURL = resolvedURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Failed to create analytics directory: \(error.localizedDescription, privacy: .public)")
        }

        if fileURL == nil {
            do {
                _ = try Self.migrateLegacyAnalyticsIfNeeded(
                    currentURL: resolvedURL,
                    legacyURL: Self.legacyFileURL(fileManager: fileManager),
                    migrationKey: Self.legacyMigrationFlagKey
                )
            } catch {
                Self.logger.error("Legacy analytics migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        Self.logger.info("Initializing analytics. Storage: \(resolvedURL.path, privacy: .public)")
        
        // Initialize with default
        let today = now()
        self.todayStats = DailyStats(date: today, totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
        
        loadHistory()
        checkDayRollover()
        
        // Auto-save timer (every 60 seconds)
        startSaveTimer()
    }
    
    deinit {
        saveTimer?.invalidate()
        flushHistoryToDisk()
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDir = appSupport ?? fileManager.temporaryDirectory
        let appDir = baseDir.appendingPathComponent("Dorso", isDirectory: true)
        return appDir.appendingPathComponent("analytics.json")
    }

    private static func legacyFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDir = appSupport ?? fileManager.temporaryDirectory
        let legacyDir = baseDir.appendingPathComponent("Posturr", isDirectory: true)
        return legacyDir.appendingPathComponent("analytics.json")
    }

    @discardableResult
    static func migrateLegacyAnalyticsIfNeeded(
        currentURL: URL,
        legacyURL: URL,
        migrationKey: String = legacyMigrationFlagKey,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard !userDefaults.bool(forKey: migrationKey) else { return false }

        guard fileManager.fileExists(atPath: legacyURL.path) else {
            userDefaults.set(true, forKey: migrationKey)
            return false
        }

        var mergedHistory: [String: DailyStats] = [:]
        if fileManager.fileExists(atPath: currentURL.path) {
            mergedHistory = try readHistory(from: currentURL)
        }

        let legacyHistory = try readHistory(from: legacyURL)
        mergedHistory = merge(current: mergedHistory, with: legacyHistory)

        try fileManager.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let mergedData = try JSONEncoder().encode(mergedHistory)
        try mergedData.write(to: currentURL, options: [.atomic])

        userDefaults.set(true, forKey: migrationKey)
        logger.info("Migrated legacy analytics from \(legacyURL.path, privacy: .public) to \(currentURL.path, privacy: .public); legacy file retained")
        return true
    }

    private static func readHistory(from url: URL) throws -> [String: DailyStats] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: DailyStats].self, from: data)
    }

    private static func merge(current: [String: DailyStats], with legacy: [String: DailyStats]) -> [String: DailyStats] {
        var merged = current
        for (dayKey, legacyStats) in legacy {
            guard let currentStats = merged[dayKey] else {
                merged[dayKey] = legacyStats
                continue
            }
            merged[dayKey] = mergeDay(current: currentStats, with: legacyStats)
        }
        return merged
    }

    private static func mergeDay(current: DailyStats, with legacy: DailyStats) -> DailyStats {
        if isEquivalent(current, legacy) {
            return current
        }

        let totalSeconds = current.totalSeconds + legacy.totalSeconds
        let slouchSeconds = min(totalSeconds, current.slouchSeconds + legacy.slouchSeconds)
        let slouchCount = current.slouchCount + legacy.slouchCount
        let date = min(current.date, legacy.date)

        return DailyStats(
            date: date,
            totalSeconds: totalSeconds,
            slouchSeconds: slouchSeconds,
            slouchCount: slouchCount
        )
    }

    private static func isEquivalent(_ lhs: DailyStats, _ rhs: DailyStats) -> Bool {
        let tolerance: TimeInterval = 0.0001
        return abs(lhs.totalSeconds - rhs.totalSeconds) < tolerance
            && abs(lhs.slouchSeconds - rhs.slouchSeconds) < tolerance
            && lhs.slouchCount == rhs.slouchCount
            && lhs.dayKey == rhs.dayKey
    }
    
    private func startSaveTimer() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.saveHistoryIfNeeded()
        }
    }
    
    // MARK: - Tracking Methods
    
    func trackTime(interval: TimeInterval, isSlouching: Bool) {
        checkDayRollover()
        
        todayStats.totalSeconds += interval
        if isSlouching {
            todayStats.slouchSeconds += interval
        }
        
        // Update history cache
        let key = DailyStats.dayKey(for: todayStats.date, calendar: calendar)
        history[key] = todayStats
        markDirty()
    }
    
    func recordSlouchEvent() {
        checkDayRollover()
        todayStats.slouchCount += 1
        let key = DailyStats.dayKey(for: todayStats.date, calendar: calendar)
        history[key] = todayStats
        markDirty()
        // Slouch events are significant - schedule a save promptly.
        saveHistory()
    }
    
    // MARK: - Data Retrieval
    
    func getLast7Days() -> [DailyStats] {
        var result: [DailyStats] = []
        let now = now()
        
        // Generate last 7 days including today
        for i in (0..<7).reversed() {
             if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let dayKey = DailyStats.dayKey(for: date, calendar: calendar)
                if let stats = history[dayKey] {
                    result.append(stats)
                } else {
                    // Return empty entry for missing days
                    result.append(DailyStats(date: date, totalSeconds: 0, slouchSeconds: 0, slouchCount: 0))
                }
            }
        }
        
        return result
    }
    
    // MARK: - Internal Logic
    
    private func checkDayRollover() {
        let now = now()
        let todayKey = DailyStats.dayKey(for: now, calendar: calendar)
        let currentKey = DailyStats.dayKey(for: todayStats.date, calendar: calendar)
        if currentKey != todayKey {
            // New day - ensure we save the previous day first
            if todayStats.totalSeconds > 0 {
                history[currentKey] = todayStats
                saveHistory()
            }
            
            todayStats = DailyStats(date: now, totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
            history[todayKey] = todayStats
        }
    }

    private func markDirty() {
        saveGeneration += 1
    }

    private var hasUnsavedChanges: Bool {
        saveGeneration != lastSavedGeneration
    }

    func saveHistoryIfNeeded() {
        guard hasUnsavedChanges else { return }
        saveHistory()
    }
    
    private func saveHistory() {
        let snapshot = history
        let generation = saveGeneration
        let url = fileURL

        persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic])
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lastSavedGeneration = max(self.lastSavedGeneration, generation)
                }
                Self.logger.debug("Analytics history saved")
            } catch {
                Self.logger.error("Failed to save analytics history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func flushHistoryToDisk() {
        let snapshot = history
        let generation = saveGeneration

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            lastSavedGeneration = max(lastSavedGeneration, generation)
            Self.logger.debug("Analytics history flushed")
        } catch {
            Self.logger.error("Failed to flush analytics history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func injectMarketingData() {
        let now = now()
        let dataPoints: [(daysAgo: Int, score: Double, slouchCount: Int, hours: Double)] = [
            (6, 68, 22, 4.5),
            (5, 74, 16, 5.2),
            (4, 71, 19, 6.1),  // dip — natural regression
            (3, 82, 11, 5.8),
            (2, 79, 13, 4.9),  // slight pullback
            (1, 88,  7, 6.3),
            (0, 91,  5, 3.2),  // today — partial day
        ]
        for point in dataPoints {
            guard let date = calendar.date(byAdding: .day, value: -point.daysAgo, to: now) else { continue }
            let totalSeconds: TimeInterval = point.hours * 3600
            let slouchSeconds = totalSeconds * (1.0 - point.score / 100.0)
            let key = DailyStats.dayKey(for: date, calendar: calendar)
            let stats = DailyStats(date: date, totalSeconds: totalSeconds, slouchSeconds: slouchSeconds, slouchCount: point.slouchCount)
            history[key] = stats
            if point.daysAgo == 0 { todayStats = stats }
        }
        saveHistory()
        Self.logger.info("Marketing mode: injected 7 days of demo analytics data")
    }

    private func loadHistory() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            history = try JSONDecoder().decode([String: DailyStats].self, from: data)
            
            // Restore today's stats if they exist in history
            let todayKey = DailyStats.dayKey(for: now(), calendar: calendar)
            if let existingToday = history[todayKey] {
                todayStats = existingToday
            }
            Self.logger.info("Loaded analytics history: \(self.history.count, privacy: .public) days recorded")
        } catch {
            Self.logger.error("Failed to load analytics history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
