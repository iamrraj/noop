import XCTest
import WhoopStore
@testable import StrandAnalytics

final class CareScheduleTests: XCTestCase {

    private let midnight = 1_000_000

    private func decide(hour: Int, lastDay: String? = nil, contact: Int? = nil) -> CareSchedule.Decision {
        CareSchedule.summaryDecision(localHour: hour, todayKey: "2026-11-11", lastSummaryDay: lastDay,
                                     lastContactTs: contact, todayStartTs: midnight)
    }

    func testTooEarly() {
        XCTAssertEqual(decide(hour: 0, contact: midnight + 60), .notDue)
        XCTAssertEqual(decide(hour: 6, contact: midnight + 60), .notDue)
    }

    func testSendsOnceSyncedAfterSendHour() {
        XCTAssertEqual(decide(hour: 7, contact: midnight), .send)
        XCTAssertEqual(decide(hour: 9, contact: midnight + 3600), .send)
    }

    func testAlreadySentToday() {
        XCTAssertEqual(decide(hour: 9, lastDay: "2026-11-11", contact: midnight + 60), .notDue)
        XCTAssertEqual(decide(hour: 23, lastDay: "2026-11-11"), .notDue)
    }

    func testYesterdaysSendDoesNotBlockToday() {
        XCTAssertEqual(decide(hour: 8, lastDay: "2026-11-10", contact: midnight + 60), .send)
    }

    func testWaitsForASyncUntilTheDeadline() {
        XCTAssertEqual(decide(hour: 7, contact: midnight - 1), .waitingForSync)
        XCTAssertEqual(decide(hour: 10, contact: nil), .waitingForSync)
    }

    func testSendsAnywayAtTheDeadline() {
        XCTAssertEqual(decide(hour: 11, contact: nil), .send)
        XCTAssertEqual(decide(hour: 20, contact: midnight - 86_400), .send)
    }

    func testDeadlineBeforeSendHourNeverWaits() {
        let decision = CareSchedule.summaryDecision(localHour: 9, todayKey: "d", lastSummaryDay: nil,
                                                    lastContactTs: nil, todayStartTs: midnight,
                                                    sendHour: 9, waitUntilHour: 6)
        XCTAssertEqual(decision, .send)
    }

    // MARK: - CareDay from stored rows

    private func metric(steps: Int? = nil) -> DailyMetric {
        DailyMetric(day: "2026-11-10", totalSleepMin: 400, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: 2, restingHr: 60, avgHrv: 41, recovery: 70, strain: 30,
                    exerciseCount: 1, steps: steps)
    }

    func testStrapCountWinsOverPhoneAndEstimate() {
        let day = CareDay(day: "2026-11-10", metric: metric(steps: 5000), phoneSteps: 4000, estimatedSteps: 3000)
        XCTAssertEqual(day.steps, 5000)
        XCTAssertFalse(day.stepsAreEstimated)
        XCTAssertEqual(day.sleepMinutes, 400)
        XCTAssertEqual(day.disturbances, 2)
        XCTAssertEqual(day.restingHr, 60)
        XCTAssertEqual(day.hrvMs, 41)
        XCTAssertEqual(day.recovery, 70)
        XCTAssertEqual(day.strain, 30)
        XCTAssertEqual(day.workouts, 1)
    }

    func testPhoneCountUsedWhenStrapHasNone() {
        let day = CareDay(day: "2026-11-10", metric: metric(), phoneSteps: 4000, estimatedSteps: 3000)
        XCTAssertEqual(day.steps, 4000)
        XCTAssertFalse(day.stepsAreEstimated)
    }

    func testEstimateIsFlagged() {
        let day = CareDay(day: "2026-11-10", metric: metric(), phoneSteps: nil, estimatedSteps: 3000)
        XCTAssertEqual(day.steps, 3000)
        XCTAssertTrue(day.stepsAreEstimated)
    }

    func testPhoneZeroIsACountNotAGap() {
        let day = CareDay(day: "2026-11-10", metric: nil, phoneSteps: 0, estimatedSteps: 3000)
        XCTAssertEqual(day.steps, 0)
        XCTAssertFalse(day.stepsAreEstimated)
    }

    func testNoRowAndNoStepsIsEmpty() {
        let day = CareDay(day: "2026-11-10", metric: nil, phoneSteps: nil, estimatedSteps: nil)
        XCTAssertTrue(day.isEmpty)
        XCTAssertFalse(day.stepsAreEstimated)
    }

    func testPhoneStepsAloneMakeADayNonEmpty() {
        XCTAssertFalse(CareDay(day: "2026-11-10", metric: nil, phoneSteps: 1200, estimatedSteps: nil).isEmpty)
    }
}
