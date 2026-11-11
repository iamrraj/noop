import Foundation

// CareReport.swift — the daily "keep an eye on someone" summary a family member receives by email.
//
// Pure and deterministic: the app layer gathers one completed day's values plus the strap's current
// state and hands them in; this file only turns them into a subject line and a plain-text body. No
// I/O, no clock, no locale — every number is formatted with a fixed format so the same inputs always
// produce the same email, which is what makes the wording testable.

/// One completed local day of the wearer's data. Every value is optional because a day the strap was
/// off the wrist, or a night that was never staged, legitimately has none.
public struct CareDay: Equatable, Sendable {
    public let day: String              // yyyy-MM-dd
    public var steps: Int?
    /// True when `steps` is the on-device motion estimate rather than a counted figure, so the email
    /// can say so instead of presenting an estimate as a measurement.
    public var stepsAreEstimated: Bool
    public var sleepMinutes: Double?
    public var disturbances: Int?
    public var restingHr: Int?
    public var hrvMs: Double?
    public var recovery: Double?        // 0–100
    public var strain: Double?          // 0–100
    public var workouts: Int?

    public init(day: String, steps: Int? = nil, stepsAreEstimated: Bool = false,
                sleepMinutes: Double? = nil, disturbances: Int? = nil, restingHr: Int? = nil,
                hrvMs: Double? = nil, recovery: Double? = nil, strain: Double? = nil,
                workouts: Int? = nil) {
        self.day = day; self.steps = steps; self.stepsAreEstimated = stepsAreEstimated
        self.sleepMinutes = sleepMinutes; self.disturbances = disturbances
        self.restingHr = restingHr; self.hrvMs = hrvMs; self.recovery = recovery
        self.strain = strain; self.workouts = workouts
    }

    /// True when the day carries nothing at all — the signature of a strap that was not worn or never
    /// synced, as opposed to a quiet day.
    public var isEmpty: Bool {
        steps == nil && sleepMinutes == nil && restingHr == nil && hrvMs == nil
            && recovery == nil && strain == nil
    }
}

/// The strap's state at the moment the report is built.
public struct CareDeviceStatus: Equatable, Sendable {
    public var batteryPct: Int?
    /// Unix seconds the phone last heard from the strap (a completed sync or a battery reading),
    /// nil when none is known.
    public var lastContactTs: Int?
    public var connected: Bool

    public init(batteryPct: Int? = nil, lastContactTs: Int? = nil, connected: Bool = false) {
        self.batteryPct = batteryPct; self.lastContactTs = lastContactTs; self.connected = connected
    }
}

/// A finished email: what goes on the subject line and in the body.
public struct CareEmail: Equatable, Sendable {
    public let subject: String
    public let body: String
    public init(subject: String, body: String) { self.subject = subject; self.body = body }
}

public enum CareReport {

    /// Shown wherever a value is missing, so a gap reads as a gap rather than as zero.
    static let missing = "no data"

    /// The morning summary of `day` (yesterday, from the reader's point of view).
    ///
    /// `alerts` are the alerts raised for that same day; they lead the email because they are the
    /// reason someone would act on it. `nowTs` is only used to phrase how long ago the strap was heard from.
    public static func dailySummary(personName: String, day: CareDay, stepGoal: Int?,
                                    device: CareDeviceStatus, alerts: [CareAlert],
                                    nowTs: Int) -> CareEmail {
        let name = displayName(personName)
        var lines: [String] = []
        lines.append("Daily summary for \(name) — \(day.day)")
        lines.append("")

        if !alerts.isEmpty {
            lines.append("NEEDS ATTENTION")
            for alert in alerts { lines.append("  ! \(alert.message)") }
            lines.append("")
        }

        if day.isEmpty {
            lines.append("No strap data was recorded for this day. The strap may not have been worn,")
            lines.append("or it has not synced with the phone yet.")
            lines.append("")
        }

        lines.append("ACTIVITY")
        lines.append("  Steps:      \(stepsText(day, goal: stepGoal))")
        lines.append("  Effort:     \(scoreText(day.strain))")
        lines.append("  Workouts:   \(day.workouts.map(String.init) ?? missing)")
        lines.append("")
        lines.append("SLEEP")
        lines.append("  Time asleep:   \(durationText(day.sleepMinutes))")
        lines.append("  Disturbances:  \(day.disturbances.map(String.init) ?? missing)")
        lines.append("")
        lines.append("HEART AND RECOVERY")
        lines.append("  Resting heart rate:  \(day.restingHr.map { "\($0) bpm" } ?? missing)")
        lines.append("  Heart-rate variability:  \(day.hrvMs.map { "\(Int($0.rounded())) ms" } ?? missing)")
        lines.append("  Recovery:  \(scoreText(day.recovery))")
        lines.append("")
        lines.append("STRAP")
        lines.append("  Battery:    \(device.batteryPct.map { "\($0)%" } ?? missing)")
        lines.append("  Last heard from strap:  \(lastContactText(device.lastContactTs, nowTs: nowTs))")
        lines.append("  Connected:  \(device.connected ? "yes" : "no")")
        lines.append("")
        lines.append(footer)

        let flag = alerts.isEmpty ? "" : " — \(alerts.count) alert\(alerts.count == 1 ? "" : "s")"
        return CareEmail(subject: "\(name): daily summary \(day.day)\(flag)",
                         body: lines.joined(separator: "\n"))
    }

    /// An out-of-cycle email for alerts that should not wait for the morning.
    public static func urgentAlert(personName: String, alerts: [CareAlert], day: String) -> CareEmail {
        let name = displayName(personName)
        var lines = ["Alert for \(name) — \(day)", ""]
        for alert in alerts { lines.append("! \(alert.message)") }
        lines.append("")
        lines.append(footer)
        let headline = alerts.first?.title ?? "alert"
        let extra = alerts.count > 1 ? " (+\(alerts.count - 1) more)" : ""
        return CareEmail(subject: "ALERT \(name): \(headline)\(extra)", body: lines.joined(separator: "\n"))
    }

    static let footer = """
        Sent automatically by NOOP from the wearer's phone. These figures come from a wrist strap and
        can be delayed or wrong. This is not a medical or emergency alert system.
        """

    // MARK: - Formatting

    static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "NOOP wearer" : trimmed
    }

    static func stepsText(_ day: CareDay, goal: Int?) -> String {
        guard let steps = day.steps else { return missing }
        var text = String(steps)
        if let goal, goal > 0 {
            let pct = Int((Double(steps) / Double(goal) * 100).rounded())
            text += " of \(goal) goal (\(pct)%)"
        }
        if day.stepsAreEstimated { text += " (estimate)" }
        return text
    }

    /// Progress toward the step goal as a 0–1 fraction for a progress bar. Capped at 1 so a day past
    /// the goal fills the bar rather than overflowing it; 0 when there is no count or no goal.
    public static func stepProgress(steps: Int?, goal: Int) -> Double {
        guard let steps, goal > 0, steps > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }

    static func scoreText(_ value: Double?) -> String {
        guard let value else { return missing }
        return "\(Int(value.rounded())) / 100"
    }

    static func durationText(_ minutes: Double?) -> String {
        guard let minutes, minutes >= 0 else { return missing }
        let total = Int(minutes.rounded())
        return "\(total / 60) h \(total % 60) min"
    }

    static func lastContactText(_ lastContactTs: Int?, nowTs: Int) -> String {
        guard let lastContactTs else { return "unknown" }
        let age = max(0, nowTs - lastContactTs)
        if age < 3600 { return "\(age / 60) min ago" }
        if age < 48 * 3600 { return "\(age / 3600) h ago" }
        return "\(age / 86_400) days ago"
    }
}
