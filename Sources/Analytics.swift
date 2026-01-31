import Foundation

// MARK: - Data Models

struct DailyStats: Codable, Identifiable {
    var id: String { dateString }
    let date: Date
    var totalSeconds: TimeInterval
    var slouchSeconds: TimeInterval
    var slouchCount: Int
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
    
    @Published var todayStats: DailyStats
    private var history: [String: DailyStats] = [:]
    private let fileURL: URL
    private var saveTimer: Timer?
    private var hasUnsavedChanges = false
    
    private init() {
        // Setup file path
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Posturr")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("analytics.json")
        print("[Analytics] Initializing. Storage: \(fileURL.path)")
        
        // Initialize with default
        let today = Date()
        self.todayStats = DailyStats(date: today, totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
        
        loadHistory()
        checkDayRollover()
        
        // Auto-save timer (every 60 seconds)
        startSaveTimer()
    }
    
    deinit {
        saveTimer?.invalidate()
        saveHistory()
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
        history[todayStats.dateString] = todayStats
        hasUnsavedChanges = true
    }
    
    func recordSlouchEvent() {
        checkDayRollover()
        todayStats.slouchCount += 1
        history[todayStats.dateString] = todayStats
        hasUnsavedChanges = true
        // Slouch events are significant, save immediately to prevent data loss on crash
        saveHistory()
    }
    
    // MARK: - Data Retrieval
    
    func getLast7Days() -> [DailyStats] {
        let calendar = Calendar.current
        var result: [DailyStats] = []
        
        // Generate last 7 days including today
        for i in (0..<7).reversed() {
             if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let dateString = formatDate(date)
                if let stats = history[dateString] {
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
        let todayString = formatDate(Date())
        if todayStats.dateString != todayString {
            // New day - ensure we save the previous day first
            if todayStats.totalSeconds > 0 {
                history[todayStats.dateString] = todayStats
                saveHistory()
            }
            
            todayStats = DailyStats(date: Date(), totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
            history[todayString] = todayStats
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func saveHistoryIfNeeded() {
        guard hasUnsavedChanges else { return }
        saveHistory()
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL)
            hasUnsavedChanges = false
            print("[Analytics] History saved")
        } catch {
            print("[Analytics] Failed to save history: \(error)")
        }
    }
    
    private func loadHistory() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            history = try JSONDecoder().decode([String: DailyStats].self, from: data)
            
            // Restore today's stats if they exist in history
            let todayString = formatDate(Date())
            if let existingToday = history[todayString] {
                todayStats = existingToday
            }
            print("[Analytics] Loaded history: \(history.count) days recorded")
        } catch {
            print("[Analytics] Failed to load history: \(error)")
        }
    }
}
