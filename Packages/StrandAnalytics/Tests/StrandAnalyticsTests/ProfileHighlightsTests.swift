import XCTest
@testable import StrandAnalytics

final class ProfileHighlightsTests: XCTestCase {

    private let today = "2026-11-11"

    private func day(_ offset: Int, sleep: Double? = nil, recovery: Double? = nil, effort: Double? = nil,
                     rhr: Double? = nil, hrv: Double? = nil) -> HighlightDay {
        HighlightDay(day: DashboardWeek.shift(today, by: offset) ?? today, sleepPerformance: sleep,
                     recovery: recovery, effort: effort, restingHr: rhr, hrv: hrv)
    }

    // MARK: - Windows

    func testMonthWindowIsThirtyDaysIncludingToday() {
        let all = [day(-30), day(-29), day(0)]
        XCTAssertEqual(ProfileHighlights.days(all, in: .month, todayKey: today).map(\.day),
                       ["2026-10-13", "2026-11-11"])
    }

    func testQuarterWindowIsNinetyDays() {
        let all = [day(-90), day(-89)]
        XCTAssertEqual(ProfileHighlights.days(all, in: .quarter, todayKey: today).count, 1)
    }

    func testAllTimeKeepsEverythingUpToToday() {
        let all = [day(-900), day(0), day(1)]
        XCTAssertEqual(ProfileHighlights.days(all, in: .allTime, todayKey: today).count, 2)
        XCTAssertEqual(ProfileHighlights.days(all, in: .month, todayKey: today).count, 1)
    }

    func testUnparseableTodayFallsBackToEverythingNotAfterIt() {
        XCTAssertEqual(ProfileHighlights.days([day(0)], in: .month, todayKey: "zzzz").count, 1)
        XCTAssertEqual(ProfileHighlights.days([], in: .month, todayKey: today), [])
    }

    // MARK: - Summary

    func testSummaryTakesExtremesAndCountsRecoveries() {
        let summary = ProfileHighlights.summary([
            day(-2, sleep: 80, recovery: 40, effort: 30, rhr: 60, hrv: 35),
            day(-1, sleep: 95, recovery: 90, effort: 80, rhr: 54, hrv: 61),
            day(0, sleep: 70, effort: 55, rhr: 66),
        ])
        XCTAssertEqual(summary.bestSleep, 95)
        XCTAssertEqual(summary.peakRecovery, 90)
        XCTAssertEqual(summary.maxEffort, 80)
        XCTAssertEqual(summary.lowestRestingHr, 54)
        XCTAssertEqual(summary.highestRestingHr, 66)
        XCTAssertEqual(summary.lowestHrv, 35)
        XCTAssertEqual(summary.highestHrv, 61)
        XCTAssertEqual(summary.recoveries, 2)
    }

    func testSummaryOfNothingIsAllGaps() {
        let summary = ProfileHighlights.summary([])
        XCTAssertNil(summary.bestSleep)
        XCTAssertNil(summary.lowestHrv)
        XCTAssertEqual(summary.recoveries, 0)
        XCTAssertNil(ProfileHighlights.summary([day(0)]).peakRecovery)
    }

    func testZeroIsARealValue() {
        XCTAssertEqual(ProfileHighlights.summary([day(0, recovery: 0)]).peakRecovery, 0)
        XCTAssertEqual(ProfileHighlights.summary([day(0, recovery: 0)]).recoveries, 1)
    }

    // MARK: - Streaks

    func testStreaksCountRunsEndingToday() {
        let all = [
            day(-3, sleep: 60, recovery: 70, effort: 50),
            day(-2, sleep: 75, recovery: 50, effort: 50),
            day(-1, sleep: 80, recovery: 70, effort: 20),
            day(0, sleep: 71, recovery: 67, effort: 48),
        ]
        let streaks = ProfileHighlights.streaks(all, todayKey: today)
        XCTAssertEqual(streaks.days, 4)
        XCTAssertEqual(streaks.sleep, 3)
        XCTAssertEqual(streaks.greenRecovery, 2)
        XCTAssertEqual(streaks.effort, 1)
    }

    func testThresholdsAreInclusive() {
        let streaks = ProfileHighlights.streaks(
            [day(0, sleep: 70, recovery: 67, effort: ProfileHighlights.effortStreakFloor)], todayKey: today)
        XCTAssertEqual(streaks, ProfileHighlights.Streaks(days: 1, sleep: 1, greenRecovery: 1, effort: 1))
        let below = ProfileHighlights.streaks([day(0, sleep: 69.9, recovery: 66.9, effort: 47)], todayKey: today)
        XCTAssertEqual(below, ProfileHighlights.Streaks(days: 1, sleep: 0, greenRecovery: 0, effort: 0))
    }

    func testNoDataMeansNoStreak() {
        XCTAssertEqual(ProfileHighlights.streaks([], todayKey: today),
                       ProfileHighlights.Streaks(days: 0, sleep: 0, greenRecovery: 0, effort: 0))
        XCTAssertEqual(ProfileHighlights.streaks([day(0)], todayKey: today).days, 0)
    }

    // MARK: - Activities

    func testActivitiesGroupCountAndAverage() {
        let stats = ProfileHighlights.activities([
            (sport: "Running", effort: 40), (sport: "Weightlifting", effort: 30),
            (sport: "running", effort: 60), (sport: "Weightlifting", effort: nil),
            (sport: "Weightlifting", effort: 50), (sport: "Yoga", effort: nil),
        ])
        XCTAssertEqual(stats.map(\.sport), ["Weightlifting", "Running", "Yoga"])
        XCTAssertEqual(stats.map(\.count), [3, 2, 1])
        XCTAssertEqual(stats[0].averageEffort, 40)
        XCTAssertEqual(stats[1].averageEffort, 50)
        XCTAssertNil(stats[2].averageEffort)
    }

    func testActivitiesTieBreakByNameAndSkipBlankSports() {
        let stats = ProfileHighlights.activities([
            (sport: "Yoga", effort: nil), (sport: "  ", effort: 10), (sport: "Cycling", effort: nil), (sport: "", effort: nil),
        ])
        XCTAssertEqual(stats.map(\.sport), ["Cycling", "Yoga"])
        XCTAssertEqual(ProfileHighlights.activities([]), [])
    }
}
