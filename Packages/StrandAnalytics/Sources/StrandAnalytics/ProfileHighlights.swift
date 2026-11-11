import Foundation

// ProfileHighlights.swift — the records, streaks and activity counts on the profile screen.
//
// Pure: the app hands in one value per day and one entry per workout; this file filters to a window
// and reduces. All scores are on the stored 0–100 axis; the screen converts for display.

public struct HighlightDay: Equatable, Sendable {
    public let day: String              // yyyy-MM-dd
    public var sleepPerformance: Double?
    public var recovery: Double?
    public var effort: Double?
    public var restingHr: Double?
    public var hrv: Double?

    public init(day: String, sleepPerformance: Double? = nil, recovery: Double? = nil,
                effort: Double? = nil, restingHr: Double? = nil, hrv: Double? = nil) {
        self.day = day; self.sleepPerformance = sleepPerformance; self.recovery = recovery
        self.effort = effort; self.restingHr = restingHr; self.hrv = hrv
    }
}

public enum ProfileHighlights {

    public enum Window: String, CaseIterable, Sendable {
        case month, quarter, allTime

        /// Days covered, counting today; nil for all time.
        public var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .allTime: return nil
            }
        }
    }

    /// The days inside `window`, ending on `todayKey`. Days after today are dropped in every window:
    /// a future-dated row is a clock fault, not a record.
    public static func days(_ all: [HighlightDay], in window: Window, todayKey: String) -> [HighlightDay] {
        let upTo = all.filter { $0.day <= todayKey }
        guard let span = window.days, let first = DashboardWeek.shift(todayKey, by: -(span - 1)) else { return upTo }
        return upTo.filter { $0.day >= first }
    }

    public struct Summary: Equatable, Sendable {
        public var bestSleep: Double?
        public var peakRecovery: Double?
        public var maxEffort: Double?
        public var lowestRestingHr: Double?
        public var highestRestingHr: Double?
        public var lowestHrv: Double?
        public var highestHrv: Double?
        /// Days carrying a recovery score.
        public var recoveries: Int
    }

    public static func summary(_ days: [HighlightDay]) -> Summary {
        let restingHr = days.compactMap(\.restingHr)
        let hrv = days.compactMap(\.hrv)
        return Summary(bestSleep: days.compactMap(\.sleepPerformance).max(),
                       peakRecovery: days.compactMap(\.recovery).max(),
                       maxEffort: days.compactMap(\.effort).max(),
                       lowestRestingHr: restingHr.min(), highestRestingHr: restingHr.max(),
                       lowestHrv: hrv.min(), highestHrv: hrv.max(),
                       recoveries: days.filter { $0.recovery != nil }.count)
    }

    public struct Streaks: Equatable, Sendable {
        /// Consecutive days, ending today, with any recovery score.
        public var days: Int
        public var sleep: Int
        public var greenRecovery: Int
        public var effort: Int
    }

    public static let sleepStreakFloor = 70.0
    public static let greenRecoveryFloor = 67.0
    /// 10 on the 0–21 scale, expressed on the stored 0–100 axis.
    public static let effortStreakFloor = 10.0 / 21.0 * 100.0

    /// The current streaks: runs of qualifying days ending on `todayKey`.
    public static func streaks(_ all: [HighlightDay], todayKey: String) -> Streaks {
        let keys = all.map(\.day)
        func current(_ qualifies: (HighlightDay) -> Bool) -> Int {
            StreakCalculator.streaks(dayKeys: keys, qualified: all.map(qualifies), today: todayKey).current
        }
        return Streaks(days: current { $0.recovery != nil },
                       sleep: current { ($0.sleepPerformance ?? -1) >= sleepStreakFloor },
                       greenRecovery: current { ($0.recovery ?? -1) >= greenRecoveryFloor },
                       effort: current { ($0.effort ?? -1) >= effortStreakFloor })
    }

    public struct ActivityStat: Equatable, Sendable, Identifiable {
        public let sport: String
        public let count: Int
        /// Mean effort over the sessions that carry one; nil when none do.
        public let averageEffort: Double?
        public var id: String { sport }
    }

    /// Sessions grouped by sport, most frequent first (ties by name, so the order is stable).
    /// Sport names are matched case-insensitively and reported as first seen.
    public static func activities(_ sessions: [(sport: String, effort: Double?)]) -> [ActivityStat] {
        var order: [String] = []
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        var efforts: [String: [Double]] = [:]
        for session in sessions {
            let name = session.sport.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if names[key] == nil { names[key] = name; order.append(key) }
            counts[key, default: 0] += 1
            if let effort = session.effort { efforts[key, default: []].append(effort) }
        }
        return order.map { key in
            let values = efforts[key] ?? []
            return ActivityStat(sport: names[key] ?? key, count: counts[key] ?? 0,
                                averageEffort: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.sport.lowercased() < $1.sport.lowercased() }
    }
}
