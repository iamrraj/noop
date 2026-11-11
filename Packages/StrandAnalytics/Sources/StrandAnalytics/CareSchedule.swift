import Foundation
import WhoopStore

// CareSchedule.swift — when the morning summary goes out, and how a stored day becomes a CareDay.
//
// The phone cannot promise a send time: iOS decides when a backgrounded app runs. So instead of a
// timer, every wake asks `summaryDecision` whether the summary for the day that just ended is due,
// and the answer is a pure function of the clock and what has already been sent.

public enum CareSchedule {

    public enum Decision: Equatable, Sendable {
        /// Already sent for today, or too early in the morning.
        case notDue
        /// Due, but the strap has not been heard from since midnight, so yesterday may be incomplete.
        /// Worth holding until `waitUntilHour` in case a sync lands.
        case waitingForSync
        case send
    }

    /// - Parameters:
    ///   - localHour: the wearer's current local hour, 0–23.
    ///   - todayKey: today's local day, `yyyy-MM-dd`.
    ///   - lastSummaryDay: the `todayKey` on which a summary last went out, nil if never.
    ///   - lastContactTs / todayStartTs: unix seconds; a contact at or after local midnight means the
    ///     night has been offloaded and yesterday is as complete as it will get.
    public static func summaryDecision(localHour: Int, todayKey: String, lastSummaryDay: String?,
                                       lastContactTs: Int?, todayStartTs: Int,
                                       sendHour: Int = 7, waitUntilHour: Int = 11) -> Decision {
        if lastSummaryDay == todayKey { return .notDue }
        guard localHour >= sendHour else { return .notDue }
        let syncedToday = lastContactTs.map { $0 >= todayStartTs } ?? false
        if !syncedToday && localHour < max(sendHour, waitUntilHour) { return .waitingForSync }
        return .send
    }

    /// When the "NOOP has stopped updating" reminder should fire if nothing re-arms it first.
    ///
    /// The app pushes this forward every time it runs, so it only ever fires after `quietHours` with
    /// no sign of life — the app was swiped away, or the phone restarted and it was never reopened.
    /// A time that would land overnight is held until `morningHour`: iOS can legitimately leave a
    /// healthy app unrun for hours while its owner sleeps, and waking her to say so helps nobody.
    public static func keepAliveFireDate(now: Date, calendar: Calendar, quietHours: Int = 10,
                                         nightStartHour: Int = 21, morningHour: Int = 8) -> Date {
        let candidate = now.addingTimeInterval(TimeInterval(max(1, quietHours)) * 3600)
        let hour = calendar.component(.hour, from: candidate)
        guard hour >= nightStartHour || hour < morningHour else { return candidate }
        let morning = DateComponents(hour: morningHour, minute: 0, second: 0)
        return calendar.nextDate(after: candidate, matching: morning, matchingPolicy: .nextTime) ?? candidate
    }
}

public extension CareDay {
    /// Build a care day from what the app has stored for it.
    ///
    /// Steps prefer a counted figure — the strap's own counter, then the phone's count for the same
    /// day — and fall back to the on-device motion estimate only when neither exists, flagged so the
    /// email never presents an estimate as a measurement. `metric` is nil for a day with no row.
    init(day: String, metric: DailyMetric?, phoneSteps: Int?, estimatedSteps: Int?) {
        let counted = metric?.steps ?? phoneSteps
        self.init(day: day,
                  steps: counted ?? estimatedSteps,
                  stepsAreEstimated: counted == nil && estimatedSteps != nil,
                  sleepMinutes: metric?.totalSleepMin,
                  disturbances: metric?.disturbances,
                  restingHr: metric?.restingHr,
                  hrvMs: metric?.avgHrv,
                  recovery: metric?.recovery,
                  strain: metric?.strain,
                  workouts: metric?.exerciseCount)
    }
}
