import Foundation

// DashboardWeek.swift — the day arithmetic and trend reads behind the dashboard home.
//
// Pure and calendar-explicit: day keys are the `yyyy-MM-dd` strings the rest of the app stores, and
// every shift goes through a fixed UTC Gregorian calendar so a daylight-saving change in the device
// zone can never skip or repeat a day.

public enum DashboardWeek {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return nil }
        // Reject keys the calendar had to normalise (2026-02-30 → March), which are not real days.
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2] ? date : nil
    }

    private static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day `days` after `key` (negative = earlier), or nil when `key` is not a real day.
    public static func shift(_ key: String, by days: Int) -> String? {
        guard let start = date(key), let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return nil
        }
        return self.key(moved)
    }

    /// The seven days ending on `key`, oldest first. Empty when `key` is not a real day.
    public static func weekEnding(_ key: String) -> [String] {
        (0..<7).reversed().compactMap { shift(key, by: -$0) }
    }

    /// Weekday index of `key`, 1 = Sunday … 7 = Saturday, for a caller to format in the user's language.
    public static func weekday(_ key: String) -> Int? {
        date(key).map { calendar.component(.weekday, from: $0) }
    }

    /// Day of the month of `key`.
    public static func dayOfMonth(_ key: String) -> Int? {
        date(key).map { calendar.component(.day, from: $0) }
    }

    // MARK: - Stress band

    public enum StressBand: Equatable, Sendable { case low, medium, high }

    /// The band a 0–3 stress level falls in: under 1 low, under 2 medium, otherwise high.
    public static func stressBand(_ level: Double) -> StressBand {
        level < 1 ? .low : (level < 2 ? .medium : .high)
    }

    // MARK: - Trend

    public enum Direction: Equatable, Sendable { case up, down, flat }

    public struct Trend: Equatable, Sendable {
        /// Mean of the comparison days.
        public let typical: Double
        public let direction: Direction
    }

    /// How `current` sits against the mean of `previous` (the days before it). nil when there is no
    /// current value or fewer than `minDays` comparison values — a trend arrow drawn from one or two
    /// days is noise. A difference within `tolerance` (a fraction of the typical value) reads as flat.
    public static func trend(current: Double?, previous: [Double], minDays: Int = 3,
                             tolerance: Double = 0.02) -> Trend? {
        guard let current, previous.count >= max(1, minDays) else { return nil }
        let typical = previous.reduce(0, +) / Double(previous.count)
        let band = abs(typical) * tolerance
        let direction: Direction = current > typical + band ? .up : (current < typical - band ? .down : .flat)
        return Trend(typical: typical, direction: direction)
    }
}
