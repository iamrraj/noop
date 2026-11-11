import XCTest
@testable import StrandAnalytics

final class CareAlertEngineTests: XCTestCase {

    private func history(days: Int = 7, restingHr: Int? = 60, steps: Int? = 6000,
                         sleepMinutes: Double? = 420) -> [CareDay] {
        (1...max(1, days)).map {
            CareDay(day: String(format: "2026-11-%02d", $0), steps: steps,
                    sleepMinutes: sleepMinutes, restingHr: restingHr)
        }.prefix(days).map { $0 }
    }

    private func kinds(_ alerts: [CareAlert]) -> [CareAlert.Kind] { alerts.map(\.kind) }

    // MARK: - Day alerts

    func testOrdinaryDayRaisesNothing() {
        let day = CareDay(day: "2026-11-10", steps: 5800, sleepMinutes: 410, restingHr: 62)
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: day, history: history()), [])
    }

    func testEmptyDayIsNoDataAndNothingElse() {
        let alerts = CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10"), history: history())
        XCTAssertEqual(kinds(alerts), [.noData])
    }

    func testRestingHrHighAgainstBaseline() {
        let day = CareDay(day: "2026-11-10", restingHr: 71)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: history())), [.restingHrHigh])
    }

    func testRestingHrJustInsideMarginIsQuiet() {
        // Baseline 60, margin max(10, 9) = 10, so 69 is inside and 70 is the first alerting value.
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 69), history: history()), [])
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 70), history: history())),
                       [.restingHrHigh])
    }

    func testRestingHrLowAgainstBaseline() {
        let day = CareDay(day: "2026-11-10", restingHr: 49)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: history())), [.restingHrLow])
    }

    func testHighBaselineUsesFractionalMargin() {
        // Baseline 80: margin is 15% = 12, not the 10 bpm floor.
        let prior = history(restingHr: 80)
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 91), history: prior), [])
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 92), history: prior)),
                       [.restingHrHigh])
    }

    func testTooLittleHistoryFallsBackToAbsoluteLimits() {
        let prior = history(days: 4)
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 85), history: prior), [])
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 100), history: prior)),
                       [.restingHrHigh])
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 40), history: prior)),
                       [.restingHrLow])
    }

    func testEmptyHistoryStillAppliesAbsoluteLimits() {
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 120), history: [])),
                       [.restingHrHigh])
    }

    func testLowActivityAgainstUsualDay() {
        let day = CareDay(day: "2026-11-10", steps: 1700, restingHr: 60)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: history())), [.lowActivity])
    }

    func testZeroStepsIsLowActivity() {
        let day = CareDay(day: "2026-11-10", steps: 0, restingHr: 60)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: history())), [.lowActivity])
    }

    func testLowActivityIgnoredForAnAlreadySedentaryBaseline() {
        let day = CareDay(day: "2026-11-10", steps: 100, restingHr: 60)
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: day, history: history(steps: 800)), [])
    }

    func testLowActivityNeedsABaseline() {
        let day = CareDay(day: "2026-11-10", steps: 10, restingHr: 60)
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: day, history: history(days: 3)), [])
    }

    func testShortSleepAbsolute() {
        let day = CareDay(day: "2026-11-10", sleepMinutes: 200, restingHr: 60)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: [])), [.shortSleep])
    }

    func testShortSleepRelativeToUsual() {
        // 60% of 420 is 252: 250 alerts even though it clears the 240-minute floor.
        let day = CareDay(day: "2026-11-10", sleepMinutes: 250, restingHr: 60)
        let alerts = CareAlertEngine.dayAlerts(day: day, history: history())
        XCTAssertEqual(kinds(alerts), [.shortSleep])
        XCTAssertEqual(alerts.first?.message, "Slept 4 h 10 min, against a usual 7 h 0 min.")
    }

    func testSeveralRulesCanFireTogether() {
        let day = CareDay(day: "2026-11-10", steps: 300, sleepMinutes: 120, restingHr: 95)
        XCTAssertEqual(kinds(CareAlertEngine.dayAlerts(day: day, history: history())),
                       [.restingHrHigh, .lowActivity, .shortSleep])
    }

    func testHistoryOnOrAfterTheDayIsIgnored() {
        // Only later days carry a baseline, so none applies and 85 bpm stays under the absolute limit.
        let later = (11...20).map { CareDay(day: "2026-11-\($0)", restingHr: 60) }
        XCTAssertEqual(CareAlertEngine.dayAlerts(day: CareDay(day: "2026-11-10", restingHr: 85), history: later), [])
    }

    // MARK: - Device alerts

    func testDeviceQuietWhenHealthy() {
        let device = CareDeviceStatus(batteryPct: 60, lastContactTs: 1_000_000, connected: true)
        XCTAssertEqual(CareAlertEngine.deviceAlerts(device: device, nowTs: 1_000_600), [])
    }

    func testBatteryLowAtThreshold() {
        XCTAssertEqual(kinds(CareAlertEngine.deviceAlerts(device: CareDeviceStatus(batteryPct: 15), nowTs: 0)), [.batteryLow])
        XCTAssertEqual(CareAlertEngine.deviceAlerts(device: CareDeviceStatus(batteryPct: 16), nowTs: 0), [])
    }

    func testStrapSilentAfterTwelveHours() {
        let device = CareDeviceStatus(batteryPct: 80, lastContactTs: 0)
        XCTAssertEqual(CareAlertEngine.deviceAlerts(device: device, nowTs: 12 * 3600 - 1), [])
        let alerts = CareAlertEngine.deviceAlerts(device: device, nowTs: 13 * 3600)
        XCTAssertEqual(kinds(alerts), [.strapSilent])
        XCTAssertEqual(alerts.first?.message, "The phone has not heard from the strap for 13 hours.")
    }

    func testUnknownDeviceStateRaisesNothing() {
        XCTAssertEqual(CareAlertEngine.deviceAlerts(device: CareDeviceStatus(), nowTs: 999_999), [])
    }

    // MARK: - Cool-down

    func testCooldownSuppressesRepeatsUntilItExpires() {
        let alert = CareAlert(kind: .batteryLow, title: "t", message: "m")
        let ledger = CareAlertEngine.recordSent([alert], into: [:], nowTs: 1000)
        XCTAssertEqual(ledger, ["batteryLow": 1000])
        XCTAssertEqual(CareAlertEngine.dueAlerts([alert], lastSent: ledger, nowTs: 1000 + 86_399), [])
        XCTAssertEqual(CareAlertEngine.dueAlerts([alert], lastSent: ledger, nowTs: 1000 + 86_400), [alert])
    }

    func testCooldownIsPerKind() {
        let battery = CareAlert(kind: .batteryLow, title: "t", message: "m")
        let silent = CareAlert(kind: .strapSilent, title: "t", message: "m")
        XCTAssertEqual(CareAlertEngine.dueAlerts([battery, silent], lastSent: ["batteryLow": 500], nowTs: 600), [silent])
    }

    func testRecordSentKeepsOtherKinds() {
        let silent = CareAlert(kind: .strapSilent, title: "t", message: "m")
        XCTAssertEqual(CareAlertEngine.recordSent([silent], into: ["batteryLow": 5], nowTs: 9),
                       ["batteryLow": 5, "strapSilent": 9])
    }

    // MARK: - Median

    func testMedian() {
        XCTAssertNil(CareAlertEngine.median([], minCount: 1))
        XCTAssertNil(CareAlertEngine.median([1, 2], minCount: 3))
        XCTAssertEqual(CareAlertEngine.median([3, 1, 2], minCount: 1), 2)
        XCTAssertEqual(CareAlertEngine.median([4, 1, 3, 2], minCount: 1), 2.5)
    }
}
