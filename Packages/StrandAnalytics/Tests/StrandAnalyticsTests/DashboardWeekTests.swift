import XCTest
@testable import StrandAnalytics

final class DashboardWeekTests: XCTestCase {

    func testShiftWithinAndAcrossMonthsAndYears() {
        XCTAssertEqual(DashboardWeek.shift("2026-11-11", by: -1), "2026-11-10")
        XCTAssertEqual(DashboardWeek.shift("2026-11-11", by: 0), "2026-11-11")
        XCTAssertEqual(DashboardWeek.shift("2026-11-30", by: 1), "2026-12-01")
        XCTAssertEqual(DashboardWeek.shift("2026-01-01", by: -1), "2025-12-31")
        XCTAssertEqual(DashboardWeek.shift("2028-02-28", by: 1), "2028-02-29")
        XCTAssertEqual(DashboardWeek.shift("2026-02-28", by: 1), "2026-03-01")
    }

    func testShiftRejectsKeysThatAreNotDays() {
        for bad in ["", "today", "2026-11", "2026-13-01", "2026-02-30", "2026-11-11-01", "a-b-c"] {
            XCTAssertNil(DashboardWeek.shift(bad, by: 1), bad)
        }
    }

    func testWeekEndingIsSevenDaysOldestFirst() {
        XCTAssertEqual(DashboardWeek.weekEnding("2026-11-11"),
                       ["2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11"])
        XCTAssertEqual(DashboardWeek.weekEnding("2026-03-02").first, "2026-02-24")
        XCTAssertEqual(DashboardWeek.weekEnding("nonsense"), [])
    }

    func testWeekdayAndDayOfMonth() {
        XCTAssertEqual(DashboardWeek.weekday("2026-11-11"), 4)      // Wednesday
        XCTAssertEqual(DashboardWeek.weekday("2026-11-08"), 1)      // Sunday
        XCTAssertEqual(DashboardWeek.dayOfMonth("2026-11-05"), 5)
        XCTAssertNil(DashboardWeek.weekday("nope"))
        XCTAssertNil(DashboardWeek.dayOfMonth("nope"))
    }

    func testStressBandBoundaries() {
        XCTAssertEqual(DashboardWeek.stressBand(0), .low)
        XCTAssertEqual(DashboardWeek.stressBand(0.99), .low)
        XCTAssertEqual(DashboardWeek.stressBand(1), .medium)
        XCTAssertEqual(DashboardWeek.stressBand(1.99), .medium)
        XCTAssertEqual(DashboardWeek.stressBand(2), .high)
        XCTAssertEqual(DashboardWeek.stressBand(3), .high)
        XCTAssertEqual(DashboardWeek.stressBand(-1), .low)
    }

    func testTrendDirections() {
        XCTAssertEqual(DashboardWeek.trend(current: 60, previous: [50, 50, 50]),
                       DashboardWeek.Trend(typical: 50, direction: .up))
        XCTAssertEqual(DashboardWeek.trend(current: 40, previous: [50, 50, 50])?.direction, .down)
        XCTAssertEqual(DashboardWeek.trend(current: 50.5, previous: [50, 50, 50])?.direction, .flat)
        XCTAssertEqual(DashboardWeek.trend(current: 51.1, previous: [50, 50, 50])?.direction, .up)
    }

    func testTrendNeedsACurrentValueAndEnoughDays() {
        XCTAssertNil(DashboardWeek.trend(current: nil, previous: [50, 50, 50]))
        XCTAssertNil(DashboardWeek.trend(current: 50, previous: [50, 50]))
        XCTAssertNil(DashboardWeek.trend(current: 50, previous: []))
        XCTAssertNotNil(DashboardWeek.trend(current: 50, previous: [50], minDays: 0))
    }

    func testTrendAroundZeroAndNegativeTypical() {
        XCTAssertEqual(DashboardWeek.trend(current: 0, previous: [0, 0, 0])?.direction, .flat)
        XCTAssertEqual(DashboardWeek.trend(current: 0.1, previous: [0, 0, 0])?.direction, .up)
        XCTAssertEqual(DashboardWeek.trend(current: -2, previous: [-1, -1, -1])?.direction, .down)
    }
}
