import XCTest
@testable import StrandAnalytics

final class CareReportTests: XCTestCase {

    private let fullDay = CareDay(day: "2026-11-10", steps: 4200, sleepMinutes: 437, disturbances: 3,
                                  restingHr: 61, hrvMs: 38.6, recovery: 71.4, strain: 33.5, workouts: 1)
    private let device = CareDeviceStatus(batteryPct: 64, lastContactTs: 10_000, connected: true)

    func testFullSummary() {
        let email = CareReport.dailySummary(personName: "Mum", day: fullDay, stepGoal: 6000,
                                            device: device, alerts: [], nowTs: 10_000 + 2 * 3600)
        XCTAssertEqual(email.subject, "Mum: daily summary 2026-11-10")
        XCTAssertTrue(email.body.contains("Steps:      4200 of 6000 goal (70%)"))
        XCTAssertTrue(email.body.contains("Effort:     34 / 100"))
        XCTAssertTrue(email.body.contains("Workouts:   1"))
        XCTAssertTrue(email.body.contains("Time asleep:   7 h 17 min"))
        XCTAssertTrue(email.body.contains("Disturbances:  3"))
        XCTAssertTrue(email.body.contains("Resting heart rate:  61 bpm"))
        XCTAssertTrue(email.body.contains("Heart-rate variability:  39 ms"))
        XCTAssertTrue(email.body.contains("Recovery:  71 / 100"))
        XCTAssertTrue(email.body.contains("Battery:    64%"))
        XCTAssertTrue(email.body.contains("Last heard from strap:  2 h ago"))
        XCTAssertTrue(email.body.contains("Connected:  yes"))
        XCTAssertFalse(email.body.contains("NEEDS ATTENTION"))
        XCTAssertTrue(email.body.contains("not a medical or emergency alert system"))
    }

    func testEmptyDaySaysSoAndMarksEveryValueMissing() {
        let email = CareReport.dailySummary(personName: "Mum", day: CareDay(day: "2026-11-10"), stepGoal: 6000,
                                            device: CareDeviceStatus(), alerts: [], nowTs: 0)
        XCTAssertTrue(email.body.contains("No strap data was recorded for this day."))
        XCTAssertTrue(email.body.contains("Steps:      no data"))
        XCTAssertTrue(email.body.contains("Time asleep:   no data"))
        XCTAssertTrue(email.body.contains("Battery:    no data"))
        XCTAssertTrue(email.body.contains("Last heard from strap:  unknown"))
        XCTAssertTrue(email.body.contains("Connected:  no"))
    }

    func testAlertsLeadTheBodyAndFlagTheSubject() {
        let alerts = [CareAlert(kind: .restingHrHigh, title: "resting heart rate high", message: "Resting heart rate was 95 bpm."),
                      CareAlert(kind: .shortSleep, title: "short sleep", message: "Slept 3 h 0 min.")]
        let email = CareReport.dailySummary(personName: "Mum", day: fullDay, stepGoal: nil,
                                            device: device, alerts: alerts, nowTs: 10_000)
        XCTAssertEqual(email.subject, "Mum: daily summary 2026-11-10 — 2 alerts")
        let attention = try? XCTUnwrap(email.body.range(of: "NEEDS ATTENTION"))
        let activity = try? XCTUnwrap(email.body.range(of: "ACTIVITY"))
        if let attention, let activity { XCTAssertTrue(attention.lowerBound < activity.lowerBound) }
        XCTAssertTrue(email.body.contains("  ! Resting heart rate was 95 bpm."))
    }

    func testSingleAlertSubjectIsSingular() {
        let alerts = [CareAlert(kind: .shortSleep, title: "short sleep", message: "m")]
        let email = CareReport.dailySummary(personName: "Mum", day: fullDay, stepGoal: nil,
                                            device: device, alerts: alerts, nowTs: 10_000)
        XCTAssertTrue(email.subject.hasSuffix("— 1 alert"))
    }

    func testStepsWithoutGoalAndEstimated() {
        var day = fullDay
        day.stepsAreEstimated = true
        XCTAssertEqual(CareReport.stepsText(day, goal: nil), "4200 (estimate)")
        XCTAssertEqual(CareReport.stepsText(day, goal: 0), "4200 (estimate)")
        XCTAssertEqual(CareReport.stepsText(day, goal: 4200), "4200 of 4200 goal (100%) (estimate)")
    }

    func testZeroStepsIsReportedNotHidden() {
        XCTAssertEqual(CareReport.stepsText(CareDay(day: "d", steps: 0), goal: 5000), "0 of 5000 goal (0%)")
    }

    func testStepProgress() {
        XCTAssertEqual(CareReport.stepProgress(steps: nil, goal: 5000), 0)
        XCTAssertEqual(CareReport.stepProgress(steps: 0, goal: 5000), 0)
        XCTAssertEqual(CareReport.stepProgress(steps: -5, goal: 5000), 0)
        XCTAssertEqual(CareReport.stepProgress(steps: 2500, goal: 5000), 0.5)
        XCTAssertEqual(CareReport.stepProgress(steps: 9000, goal: 5000), 1)
        XCTAssertEqual(CareReport.stepProgress(steps: 100, goal: 0), 0)
    }

    func testBlankNameFallsBack() {
        XCTAssertEqual(CareReport.displayName("   "), "NOOP wearer")
        XCTAssertEqual(CareReport.displayName(" Mum "), "Mum")
    }

    func testDurationText() {
        XCTAssertEqual(CareReport.durationText(nil), "no data")
        XCTAssertEqual(CareReport.durationText(-1), "no data")
        XCTAssertEqual(CareReport.durationText(0), "0 h 0 min")
        XCTAssertEqual(CareReport.durationText(59.6), "1 h 0 min")
    }

    func testLastContactText() {
        XCTAssertEqual(CareReport.lastContactText(nil, nowTs: 100), "unknown")
        XCTAssertEqual(CareReport.lastContactText(100, nowTs: 100), "0 min ago")
        XCTAssertEqual(CareReport.lastContactText(0, nowTs: 3599), "59 min ago")
        XCTAssertEqual(CareReport.lastContactText(0, nowTs: 3600), "1 h ago")
        XCTAssertEqual(CareReport.lastContactText(0, nowTs: 3 * 86_400), "3 days ago")
        // A clock that ran backwards must not print a negative age.
        XCTAssertEqual(CareReport.lastContactText(500, nowTs: 100), "0 min ago")
    }

    func testUrgentAlert() {
        let alerts = [CareAlert(kind: .batteryLow, title: "strap battery low", message: "Strap battery is at 9% and needs charging."),
                      CareAlert(kind: .strapSilent, title: "strap out of contact", message: "The phone has not heard from the strap for 14 hours.")]
        let email = CareReport.urgentAlert(personName: "Mum", alerts: alerts, day: "2026-11-11")
        XCTAssertEqual(email.subject, "ALERT Mum: strap battery low (+1 more)")
        XCTAssertTrue(email.body.contains("! Strap battery is at 9% and needs charging."))
        XCTAssertTrue(email.body.contains("! The phone has not heard from the strap for 14 hours."))
    }

    func testUrgentAlertWithOneAlertHasNoCountSuffix() {
        let email = CareReport.urgentAlert(personName: "Mum",
                                           alerts: [CareAlert(kind: .batteryLow, title: "strap battery low", message: "m")],
                                           day: "2026-11-11")
        XCTAssertEqual(email.subject, "ALERT Mum: strap battery low")
    }
}
