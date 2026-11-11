#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The profile screen behind the dashboard's avatar: fitness age and day streak, the wearer's
/// records and streaks over a chosen window, and a count of activities by sport. Everything is
/// computed on the phone from the stored days; there is no account behind it.
struct DashboardProfileView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = ""

    @State private var window: ProfileHighlights.Window = .allTime
    @State private var restByDay: [String: Double] = [:]
    @State private var workouts: [WorkoutRow] = []
    @State private var fitnessAge: Double?

    private static let avatarSize: CGFloat = 96

    private var todayKey: String { Repository.localDayKey(Date()) }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    private var allDays: [HighlightDay] {
        repo.days.map {
            HighlightDay(day: $0.day, sleepPerformance: restByDay[$0.day], recovery: $0.recovery,
                         effort: $0.strain, restingHr: $0.restingHr.map(Double.init), hrv: $0.avgHrv)
        }
    }

    var body: some View {
        let all = allDays
        let summary = ProfileHighlights.summary(ProfileHighlights.days(all, in: window, todayKey: todayKey))
        let streaks = ProfileHighlights.streaks(all, todayKey: todayKey)
        NavigationStack {
            ScreenScaffold(title: nil) {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: Self.avatarSize)
                    headlineTiles(recoveries: ProfileHighlights.summary(all).recoveries, streakDays: streaks.days)
                    DashboardProfileHighlights(window: $window, summary: summary, streaks: streaks,
                                               effortScale: effortScale)
                    DashboardProfileActivities(stats: activityStats, effortScale: effortScale)
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
        }
        // Keyed on the day count so a refresh that lands after the sheet opens reloads the series too.
        .task(id: repo.days.count) { await load() }
    }

    private func headlineTiles(recoveries: Int, streakDays: Int) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
            tile(value: fitnessAge.map { "\(Int($0.rounded()))" } ?? "—", title: "FITNESS AGE",
                 detail: fitnessAge == nil ? String(localized: "Needs age, sex and a week of nights")
                                           : String(localized: "Updated weekly"))
            tile(value: "\(streakDays)", title: "DAY STREAK",
                 detail: String(localized: "\(recoveries) recoveries in total"))
        }
    }

    private func tile(value: String, title: LocalizedStringKey, detail: String) -> some View {
        NoopCard {
            VStack(spacing: NoopMetrics.rowSpacing) {
                Text(value).font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
                Text(title)
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    /// Workouts inside the chosen window, grouped by sport.
    private var activityStats: [ProfileHighlights.ActivityStat] {
        let first = window.days.flatMap { DashboardWeek.shift(todayKey, by: -($0 - 1)) }
        let inWindow = workouts.filter { row in
            let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(row.startTs)))
            return key <= todayKey && (first.map { key >= $0 } ?? true)
        }
        return ProfileHighlights.activities(inWindow.map { (sport: $0.sport, effort: $0.strain) })
    }

    private func load() async {
        let rest = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        restByDay = Dictionary(rest.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        workouts = await repo.workoutRows()
        fitnessAge = await repo.exploreSeries(key: "fitness_age", source: "my-whoop").last?.value
    }
}
#endif
