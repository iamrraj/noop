import Foundation
import StrandAnalytics
import WhoopStore

/// Sends the family "care" emails: a morning summary of the wearer's previous day, and alert emails
/// when the strap needs attention.
///
/// There is no timer. iOS decides when a backgrounded app runs, so `runIfDue` is called from every
/// wake the app already gets (foreground, background transition, the periodic background task) and
/// works out from the clock and its own bookkeeping whether anything is owed. Every decision is a
/// pure function in StrandAnalytics (`CareSchedule`, `CareAlertEngine`, `CareReport`); this type
/// gathers the inputs, sends, and records what went out.
@MainActor
enum CareReporter {

    enum Outcome: Equatable {
        case notConfigured
        case disabled
        case nothingDue
        case sent(String)
        case failed(String)
    }

    /// How much history feeds the personal baselines.
    static let baselineDays = 35

    private static var isRunning = false

    @discardableResult
    static func runIfDue(model: AppModel, now: Date = Date(), defaults: UserDefaults = .standard) async -> Outcome {
        guard let config = CareConfig.fromBundle else { return .notConfigured }
        guard CarePrefs.isEnabled(defaults) else { return .disabled }
        // Foreground, background and the periodic task can all land together; one pass is enough.
        guard !isRunning else { return .nothingDue }
        isRunning = true
        defer { isRunning = false }

        let nowTs = Int(now.timeIntervalSince1970)
        let calendar = Calendar.current
        let todayKey = Repository.localDayKey(now)
        let device = await deviceStatus(model: model)
        let deviceAlerts = CareAlertEngine.deviceAlerts(device: device, nowTs: nowTs)

        let decision = CareSchedule.summaryDecision(
            localHour: calendar.component(.hour, from: now), todayKey: todayKey,
            lastSummaryDay: defaults.string(forKey: CarePrefs.lastSummaryDayKey),
            lastContactTs: device.lastContactTs,
            todayStartTs: Int(calendar.startOfDay(for: now).timeIntervalSince1970),
            sendHour: CarePrefs.sendHour(defaults))

        if decision == .send {
            let email = await summaryEmail(config: config, model: model, now: now, device: device,
                                           deviceAlerts: deviceAlerts, defaults: defaults)
            let outcome = await deliver(email, config: config, now: now, defaults: defaults)
            if case .sent = outcome {
                defaults.set(todayKey, forKey: CarePrefs.lastSummaryDayKey)
                // The summary already carried these, so they must not go out again as an alert.
                record(deviceAlerts, nowTs: nowTs, defaults: defaults)
            }
            return outcome
        }

        let due = CareAlertEngine.dueAlerts(deviceAlerts, lastSent: CarePrefs.alertLedger(defaults), nowTs: nowTs)
        guard !due.isEmpty else { return .nothingDue }
        let email = CareReport.urgentAlert(personName: config.personName, alerts: due, day: todayKey)
        let outcome = await deliver(email, config: config, now: now, defaults: defaults)
        if case .sent = outcome { record(due, nowTs: nowTs, defaults: defaults) }
        return outcome
    }

    /// The "Send test email" button: yesterday's summary, sent now, without touching the bookkeeping
    /// that decides when the real one is due.
    static func sendTest(model: AppModel, now: Date = Date(), defaults: UserDefaults = .standard) async -> Outcome {
        guard let config = CareConfig.fromBundle else { return .notConfigured }
        let device = await deviceStatus(model: model)
        let alerts = CareAlertEngine.deviceAlerts(device: device, nowTs: Int(now.timeIntervalSince1970))
        let email = await summaryEmail(config: config, model: model, now: now, device: device,
                                       deviceAlerts: alerts, defaults: defaults)
        return await deliver(CareEmail(subject: "[Test] " + email.subject, body: email.body),
                             config: config, now: now, defaults: defaults)
    }

    // MARK: - Gathering

    private static func deviceStatus(model: AppModel) async -> CareDeviceStatus {
        // The stored reading survives a cold background launch, when the live state is still empty.
        let stored = await model.repo.latestBattery()
        let battery = model.live.batteryPct ?? stored?.soc
        let contacts = [model.live.lastSyncedAt.map { Int($0) }, stored?.ts].compactMap { $0 }
        return CareDeviceStatus(batteryPct: battery.map { Int($0.rounded()) },
                                lastContactTs: contacts.max(),
                                connected: model.live.bonded)
    }

    private static func summaryEmail(config: CareConfig, model: AppModel, now: Date,
                                     device: CareDeviceStatus, deviceAlerts: [CareAlert],
                                     defaults: UserDefaults) async -> CareEmail {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = Repository.localDayKey(yesterday)
        let fromKey = Repository.localDayKey(calendar.date(byAdding: .day, value: -baselineDays, to: now) ?? now)

        let metrics = await model.repo.dailyMetrics(fromDay: fromKey, toDay: yesterdayKey)
        let phone = await model.repo.appleDailyRows(days: baselineDays + 2)
        let estimates = await model.repo.exploreSeries(key: "steps_est", source: "my-whoop", days: baselineDays + 2)

        let metricByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        let phoneSteps = Dictionary(phone.compactMap { row in row.steps.map { (row.day, $0) } },
                                    uniquingKeysWith: { _, last in last })
        let estimateByDay = Dictionary(estimates.map { ($0.day, Int($0.value.rounded())) },
                                       uniquingKeysWith: { _, last in last })

        func careDay(_ key: String) -> CareDay {
            CareDay(day: key, metric: metricByDay[key], phoneSteps: phoneSteps[key],
                    estimatedSteps: estimateByDay[key])
        }
        let historyKeys = Set(metricByDay.keys).union(phoneSteps.keys).filter { $0 >= fromKey && $0 < yesterdayKey }
        let day = careDay(yesterdayKey)
        // Banked weekly, so the latest value is the current one whatever day it was written.
        let fitnessAge = await model.repo.exploreSeries(key: "fitness_age", source: "my-whoop").last?.value
        let dayAlerts = CareAlertEngine.dayAlerts(day: day, history: historyKeys.map(careDay))

        return CareReport.dailySummary(personName: config.personName, day: day,
                                       stepGoal: CarePrefs.stepGoal(defaults), device: device,
                                       alerts: dayAlerts + deviceAlerts,
                                       nowTs: Int(now.timeIntervalSince1970), fitnessAge: fitnessAge)
    }

    // MARK: - Sending

    private static func deliver(_ email: CareEmail, config: CareConfig, now: Date,
                                defaults: UserDefaults) async -> Outcome {
        do {
            try await SMTPTransport.send(config: config, email: email, now: now)
            defaults.removeObject(forKey: CarePrefs.lastErrorKey)
            defaults.set(now.timeIntervalSince1970, forKey: CarePrefs.lastSentAtKey)
            return .sent(email.subject)
        } catch {
            let reason = describe(error)
            defaults.set(reason, forKey: CarePrefs.lastErrorKey)
            return .failed(reason)
        }
    }

    private static func record(_ alerts: [CareAlert], nowTs: Int, defaults: UserDefaults) {
        guard !alerts.isEmpty else { return }
        defaults.set(CareAlertEngine.recordSent(alerts, into: CarePrefs.alertLedger(defaults), nowTs: nowTs),
                     forKey: CarePrefs.alertLedgerKey)
    }

    /// A reason fit to show on screen. Never includes the credentials: `SMTPError` carries only the
    /// server's reply text, and the transport errors only the system's description.
    static func describe(_ error: Error) -> String {
        switch error {
        case SMTPError.rejected(let stage, let code, let text):
            return "The mail server refused at \(stage) (\(code)): \(text)"
        case SMTPError.invalidField(let field):
            return "The \(field) setting is not valid."
        case SMTPError.malformedReply:
            return "The mail server sent a reply that could not be read."
        case SMTPTransport.TransportError.timedOut:
            return "The mail server did not answer in time."
        case SMTPTransport.TransportError.closedByServer:
            return "The mail server closed the connection."
        case SMTPTransport.TransportError.connectionFailed(let detail):
            return "Could not reach the mail server: \(detail)"
        default:
            return "Sending failed: \(error.localizedDescription)"
        }
    }
}
