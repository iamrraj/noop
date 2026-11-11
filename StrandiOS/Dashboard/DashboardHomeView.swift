#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The dashboard home: a day switcher over three score rings, the health and stress monitors, the
/// day's activities, a seven-day effort and recovery chart, and trend rows. Every section reads the
/// one `selectedKey`, so stepping back a day moves the whole screen together.
struct DashboardHomeView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""

    /// 0 is today; negative values step back. Never positive: there is no tomorrow to show.
    @State private var dayOffset = 0
    @State private var restByDay: [String: Double] = [:]
    @State private var workouts: [WorkoutRow] = []
    @State private var stress: DaytimeStress.Result?

    private var todayKey: String { Repository.localDayKey(Date()) }
    private var selectedKey: String { DashboardWeek.shift(todayKey, by: dayOffset) ?? todayKey }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private func row(_ key: String) -> DailyMetric? { repo.days.last(where: { $0.day == key }) }

    var body: some View {
        let key = selectedKey
        let day = row(key)
        ScreenScaffold(title: nil, onRefresh: { await repo.refresh(); await load() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                DashboardHeader(dayOffset: $dayOffset, selectedKey: key)
                DashboardRingsRow(sleepPerformance: restByDay[key], recovery: day?.recovery,
                                  effort: day?.strain, effortScale: effortScale)
                DashboardMonitorTiles(stress: dayOffset == 0 ? stress : nil, isToday: dayOffset == 0)
                // Opt-in "looks like a workout?" suggestion; renders nothing unless the Settings
                // toggle is on and a candidate exists. Today only, as on the other home screens.
                if dayOffset == 0 { AutoWorkoutCard() }
                DashboardActivities(dayKey: key, isToday: dayOffset == 0,
                                    sleeps: sleeps(endingOn: key), workouts: workouts(startingOn: key),
                                    effortScale: effortScale)
                DashboardWeekChart(points: weekPoints(endingOn: key), selectedKey: key, effortScale: effortScale)
                DashboardMetricRows(rows: metricRows(for: key, day: day))
            }
        }
        .task(id: repo.days.count) { await load() }
    }

    // MARK: - Loading

    private func load() async {
        let rest = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        restByDay = Dictionary(rest.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        workouts = await repo.workoutRows()
        stress = await StressDayCurve.today(repo: repo)?.result
    }

    // MARK: - Per-day slices

    private static func localKey(_ ts: Int) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// A night belongs to the day it ended on.
    private func sleeps(endingOn key: String) -> [CachedSleepSession] {
        repo.sleeps.filter { Self.localKey($0.endTs) == key }.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
    }

    private func workouts(startingOn key: String) -> [WorkoutRow] {
        workouts.filter { Self.localKey($0.startTs) == key }.sorted { $0.startTs < $1.startTs }
    }

    private func weekPoints(endingOn key: String) -> [DashboardWeekPoint] {
        DashboardWeek.weekEnding(key).map { dayKey in
            let metric = row(dayKey)
            return DashboardWeekPoint(day: dayKey, effort: metric?.strain, recovery: metric?.recovery)
        }
    }

    private func metricRows(for key: String, day: DailyMetric?) -> [DashboardMetricRow] {
        let previousKeys = DashboardWeek.weekEnding(key).dropLast()
        func previous(_ value: (String) -> Double?) -> [Double] { previousKeys.compactMap(value) }
        func make(_ title: LocalizedStringKey, _ icon: String, _ route: TabRoute, _ unit: String,
                  current: Double?, previous: [Double]) -> DashboardMetricRow {
            DashboardMetricRow(title: title, icon: icon, route: route, unit: unit, value: current,
                               trend: DashboardWeek.trend(current: current, previous: previous))
        }
        return [
            make("Heart rate variability", "waveform.path.ecg", .metric("hrv"), "ms",
                 current: day?.avgHrv, previous: previous { row($0)?.avgHrv }),
            make("Recovery", "heart.circle", .metric("recovery"), "%",
                 current: day?.recovery, previous: previous { row($0)?.recovery }),
            make("Sleep performance", "moon.stars", .metric("sleep_performance"), "%",
                 current: restByDay[key], previous: previous { restByDay[$0] }),
            make("Resting heart rate", "heart", .metric("rhr"), "bpm",
                 current: day?.restingHr.map(Double.init), previous: previous { row($0)?.restingHr.map(Double.init) }),
        ]
    }
}

/// One day on the seven-day chart. Both values are on the stored 0–100 axis.
struct DashboardWeekPoint: Identifiable, Equatable {
    let day: String
    let effort: Double?
    let recovery: Double?
    var id: String { day }
}

/// One trend row under the chart.
struct DashboardMetricRow: Identifiable {
    let title: LocalizedStringKey
    let icon: String
    let route: TabRoute
    let unit: String
    let value: Double?
    let trend: DashboardWeek.Trend?
    var id: String { icon }
}
#endif
