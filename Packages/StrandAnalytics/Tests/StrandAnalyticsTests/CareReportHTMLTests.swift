import XCTest
@testable import StrandAnalytics

final class CareReportHTMLTests: XCTestCase {

    private let fullDay = CareDay(day: "2026-11-10", steps: 4200, sleepMinutes: 437, disturbances: 3,
                                  restingHr: 61, hrvMs: 38.6, recovery: 71.4, strain: 33.5, workouts: 1)
    private let device = CareDeviceStatus(batteryPct: 64, lastContactTs: 10_000, connected: true)

    private func summary(name: String = "Mum", day: CareDay? = nil, goal: Int? = 6000,
                         alerts: [CareAlert] = [], fitnessAge: Double? = nil) -> String {
        CareReportHTML.dailySummary(personName: name, day: day ?? fullDay, stepGoal: goal, device: device,
                                    alerts: alerts, nowTs: 10_000 + 7200, fitnessAge: fitnessAge)
    }

    func testEscape() {
        XCTAssertEqual(CareReportHTML.escape("<b>\"Tom\" & 'Jerry'</b>"),
                       "&lt;b&gt;&quot;Tom&quot; &amp; &#39;Jerry&#39;&lt;/b&gt;")
        XCTAssertEqual(CareReportHTML.escape(""), "")
    }

    func testSummaryCarriesEveryFigure() {
        let html = summary(fitnessAge: 57.4)
        for expected in ["Daily summary", "Mum", "Tuesday 10 November 2026", ">71<", ">34<", ">7.3<", "4200", "of 6000 goal",
                         "7 h 17 min", "61 bpm", "39 ms", "64%", "2 h ago", "57 (updated weekly)",
                         "not a medical or emergency alert system"] {
            XCTAssertTrue(html.contains(expected), "missing \(expected)")
        }
        XCTAssertFalse(html.contains("Needs attention"))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
    }

    func testFitnessAgeRowOnlyWhenKnown() {
        XCTAssertFalse(summary().contains("Fitness age"))
    }

    func testStepBarWidthFollowsTheGoal() {
        XCTAssertTrue(summary().contains("width=\"70%\""))
        // A full bar is one rounded cell, not a filled cell beside an empty one.
        XCTAssertFalse(summary(goal: 4200).contains("border-radius:4px 0 0 4px"))
        XCTAssertTrue(summary().contains("border-radius:4px 0 0 4px"))
        var none = fullDay
        none.steps = nil
        let html = summary(day: none)
        XCTAssertTrue(html.contains("No step count for this day"))
        XCTAssertFalse(html.contains("width=\"0%\""))
    }

    func testNoGoalAndEstimatedSteps() {
        var day = fullDay
        day.stepsAreEstimated = true
        let html = summary(day: day, goal: nil)
        XCTAssertTrue(html.contains("estimated from strap movement"))
        XCTAssertFalse(html.contains("goal"))
        XCTAssertFalse(summary(goal: 0).contains("of 0 goal"))
    }

    func testEmptyDayShowsTheNoteAndDashes() {
        let html = summary(day: CareDay(day: "2026-11-10"))
        XCTAssertTrue(html.contains("No strap data was recorded for this day."))
        XCTAssertTrue(html.contains("&ndash;"))
        XCTAssertTrue(html.contains("no data"))
    }

    func testAlertsAreShownAndEscaped() {
        let alerts = [CareAlert(kind: .restingHrHigh, title: "t", message: "Resting heart rate was 95 bpm <script>.")]
        let html = summary(alerts: alerts)
        XCTAssertTrue(html.contains("Needs attention"))
        XCTAssertTrue(html.contains("95 bpm &lt;script&gt;."))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("1 item needs attention."))
        XCTAssertTrue(summary(alerts: alerts + alerts).contains("2 items need attention."))
    }

    func testHostileNameCannotInjectMarkup() {
        let html = summary(name: "<img src=x onerror=alert(1)>")
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
    }

    func testRecoveryColourBands() {
        XCTAssertEqual(CareReportHTML.recoveryColor(67), CareReportHTML.good)
        XCTAssertEqual(CareReportHTML.recoveryColor(66.9), CareReportHTML.fair)
        XCTAssertEqual(CareReportHTML.recoveryColor(34), CareReportHTML.fair)
        XCTAssertEqual(CareReportHTML.recoveryColor(33.9), CareReportHTML.poor)
        XCTAssertEqual(CareReportHTML.recoveryColor(0), CareReportHTML.poor)
    }

    func testUrgentAlert() {
        let html = CareReportHTML.urgentAlert(
            personName: "Mum", alerts: [CareAlert(kind: .batteryLow, title: "t", message: "Strap battery is at 9% and needs charging.")],
            day: "2026-11-11")
        XCTAssertTrue(html.contains("Alert"))
        XCTAssertTrue(html.contains("Wednesday 11 November 2026"))
        XCTAssertTrue(html.contains("Strap battery is at 9% and needs charging."))
        XCTAssertFalse(html.contains("Yesterday in detail"))
    }

    func testEmailsCarryBothVersions() {
        let summaryEmail = CareReport.dailySummary(personName: "Mum", day: fullDay, stepGoal: 6000,
                                                   device: device, alerts: [], nowTs: 10_000)
        XCTAssertNotNil(summaryEmail.html)
        XCTAssertTrue(summaryEmail.body.contains("ACTIVITY"))
        XCTAssertNotNil(CareReport.urgentAlert(personName: "Mum", alerts: [], day: "2026-11-11").html)
    }
}
