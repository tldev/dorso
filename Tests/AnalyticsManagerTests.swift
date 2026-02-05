import XCTest
@testable import PosturrCore

final class AnalyticsManagerTests: XCTestCase {

    func testDayRolloverCreatesNewDayAndPersistsBothDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            let components = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
            return calendar.date(from: components)!
        }

        let day1 = makeDate(2026, 2, 5, 23, 59)
        let day2 = makeDate(2026, 2, 6, 0, 1)

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tmpDir.appendingPathComponent("analytics.json")

        let queue = DispatchQueue(label: "test.analytics.persistence")
        var currentNow = day1

        let manager = AnalyticsManager(
            fileURL: fileURL,
            calendar: calendar,
            now: { currentNow },
            persistenceQueue: queue
        )

        manager.trackTime(interval: 10, isSlouching: false)
        manager.recordSlouchEvent()
        manager.saveHistoryIfNeeded()

        queue.sync {}

        let data1 = try Data(contentsOf: fileURL)
        let history1 = try JSONDecoder().decode([String: DailyStats].self, from: data1)
        let day1Key = DailyStats.dayKey(for: day1, calendar: calendar)
        XCTAssertEqual(history1[day1Key]?.totalSeconds ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(history1[day1Key]?.slouchCount ?? 0, 1)

        currentNow = day2
        manager.trackTime(interval: 5, isSlouching: true)
        manager.saveHistoryIfNeeded()

        queue.sync {}

        let data2 = try Data(contentsOf: fileURL)
        let history2 = try JSONDecoder().decode([String: DailyStats].self, from: data2)
        let day2Key = DailyStats.dayKey(for: day2, calendar: calendar)

        XCTAssertNotNil(history2[day1Key])
        XCTAssertNotNil(history2[day2Key])

        XCTAssertEqual(history2[day2Key]?.totalSeconds ?? 0, 5, accuracy: 0.0001)
        XCTAssertEqual(history2[day2Key]?.slouchSeconds ?? 0, 5, accuracy: 0.0001)

        XCTAssertEqual(DailyStats.dayKey(for: manager.todayStats.date, calendar: calendar), day2Key)
    }
}
