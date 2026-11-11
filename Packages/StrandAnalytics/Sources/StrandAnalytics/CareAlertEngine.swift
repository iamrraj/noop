import Foundation

// CareAlertEngine.swift — decides when a family member should be told something looks off.
//
// Every rule compares a day against the wearer's OWN recent history rather than a population norm,
// because a resting heart rate of 58 is ordinary for one person and a warning for another. Absolute
// limits exist only as a backstop for a wearer with too little history to have a baseline.
//
// These are "worth a phone call" prompts, not findings. Nothing here diagnoses anything, and the
// wording an alert carries is written to say what was observed, not what it means.

public struct CareAlert: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case restingHrHigh, restingHrLow, lowActivity, shortSleep, noData, batteryLow, strapSilent
    }

    public let kind: Kind
    /// Short label for an email subject.
    public let title: String
    /// One full sentence stating what was observed.
    public let message: String

    public init(kind: Kind, title: String, message: String) {
        self.kind = kind; self.title = title; self.message = message
    }
}

public enum CareAlertEngine {

    public struct Thresholds: Equatable, Sendable {
        /// Prior days needed before a personal baseline is trusted.
        public var minBaselineDays = 5
        /// Resting HR must differ from the baseline by at least this many bpm...
        public var restingHrDeltaBpm = 10.0
        /// ...and by at least this fraction of it, so a low baseline is not over-sensitive.
        public var restingHrDeltaFraction = 0.15
        /// Backstops used only without a baseline.
        public var restingHrAbsoluteHigh = 100
        public var restingHrAbsoluteLow = 40
        /// A day's steps below this fraction of the usual day counts as very low activity.
        public var lowActivityFraction = 0.3
        /// Ignore the activity rule for a wearer whose usual day is already below this.
        public var lowActivityMinBaselineSteps = 1000.0
        public var shortSleepMinutes = 240.0
        public var shortSleepFraction = 0.6
        public var batteryLowPct = 15
        public var strapSilentSeconds = 12 * 3600
        public init() {}
    }

    /// Alerts for one completed `day`, judged against `history` (earlier days, any order; the day
    /// itself is ignored if present).
    public static func dayAlerts(day: CareDay, history: [CareDay],
                                 thresholds: Thresholds = Thresholds()) -> [CareAlert] {
        if day.isEmpty {
            return [CareAlert(kind: .noData, title: "no strap data",
                              message: "No strap data was recorded on \(day.day). The strap may not have been worn or has not synced.")]
        }
        let prior = history.filter { $0.day < day.day }
        var alerts: [CareAlert] = []

        if let rhr = day.restingHr {
            let baseline = median(prior.compactMap { $0.restingHr.map(Double.init) }, minCount: thresholds.minBaselineDays)
            if let baseline {
                let margin = max(thresholds.restingHrDeltaBpm, baseline * thresholds.restingHrDeltaFraction)
                let usual = Int(baseline.rounded())
                if Double(rhr) >= baseline + margin {
                    alerts.append(CareAlert(kind: .restingHrHigh, title: "resting heart rate high",
                                            message: "Resting heart rate was \(rhr) bpm, well above the usual \(usual) bpm."))
                } else if Double(rhr) <= baseline - margin {
                    alerts.append(CareAlert(kind: .restingHrLow, title: "resting heart rate low",
                                            message: "Resting heart rate was \(rhr) bpm, well below the usual \(usual) bpm."))
                }
            } else if rhr >= thresholds.restingHrAbsoluteHigh {
                alerts.append(CareAlert(kind: .restingHrHigh, title: "resting heart rate high",
                                        message: "Resting heart rate was \(rhr) bpm."))
            } else if rhr <= thresholds.restingHrAbsoluteLow {
                alerts.append(CareAlert(kind: .restingHrLow, title: "resting heart rate low",
                                        message: "Resting heart rate was \(rhr) bpm."))
            }
        }

        if let steps = day.steps,
           let usual = median(prior.compactMap { $0.steps.map(Double.init) }, minCount: thresholds.minBaselineDays),
           usual >= thresholds.lowActivityMinBaselineSteps,
           Double(steps) < usual * thresholds.lowActivityFraction {
            alerts.append(CareAlert(kind: .lowActivity, title: "very low activity",
                                    message: "Only \(steps) steps, against a usual day of about \(Int(usual.rounded()))."))
        }

        if let sleep = day.sleepMinutes {
            let usual = median(prior.compactMap { $0.sleepMinutes }, minCount: thresholds.minBaselineDays)
            let belowUsual = usual.map { sleep < $0 * thresholds.shortSleepFraction } ?? false
            if sleep < thresholds.shortSleepMinutes || belowUsual {
                var message = "Slept \(CareReport.durationText(sleep))"
                if let usual { message += ", against a usual \(CareReport.durationText(usual))" }
                alerts.append(CareAlert(kind: .shortSleep, title: "short sleep", message: message + "."))
            }
        }
        return alerts
    }

    /// Alerts about the strap itself, judged at `nowTs`.
    public static func deviceAlerts(device: CareDeviceStatus, nowTs: Int,
                                    thresholds: Thresholds = Thresholds()) -> [CareAlert] {
        var alerts: [CareAlert] = []
        if let pct = device.batteryPct, pct <= thresholds.batteryLowPct {
            alerts.append(CareAlert(kind: .batteryLow, title: "strap battery low",
                                    message: "Strap battery is at \(pct)% and needs charging."))
        }
        if let last = device.lastContactTs, nowTs - last >= thresholds.strapSilentSeconds {
            alerts.append(CareAlert(kind: .strapSilent, title: "strap out of contact",
                                    message: "The phone has not heard from the strap for \((nowTs - last) / 3600) hours."))
        }
        return alerts
    }

    // MARK: - Cool-down

    /// Drop alerts whose kind was already sent within `cooldownSeconds`, so a condition that persists
    /// (a strap left uncharged for a week) produces one email a day rather than one per background wake.
    /// `lastSent` maps `Kind.rawValue` to the unix second it last went out.
    public static func dueAlerts(_ alerts: [CareAlert], lastSent: [String: Int], nowTs: Int,
                                 cooldownSeconds: Int = 24 * 3600) -> [CareAlert] {
        alerts.filter { alert in
            guard let sent = lastSent[alert.kind.rawValue] else { return true }
            return nowTs - sent >= cooldownSeconds
        }
    }

    /// The ledger after `alerts` went out at `nowTs`.
    public static func recordSent(_ alerts: [CareAlert], into lastSent: [String: Int],
                                  nowTs: Int) -> [String: Int] {
        var updated = lastSent
        for alert in alerts { updated[alert.kind.rawValue] = nowTs }
        return updated
    }

    // MARK: - Helpers

    /// Median of `values`, or nil when there are fewer than `minCount` — too little to call a baseline.
    static func median(_ values: [Double], minCount: Int) -> Double? {
        guard values.count >= max(1, minCount) else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
