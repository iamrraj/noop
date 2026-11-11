#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A reduced Today for a wearer who wants the basics at a glance — the recovery, effort and sleep
/// rings, steps against a goal, heart rate and the strap's battery — in large type, with nothing to
/// configure. Shown in place of the full
/// dashboard when "Simple home" is on (`CarePrefs.simpleHomeKey`).
struct SimpleHomeView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(CarePrefs.stepGoalKey) private var storedStepGoal = CarePrefs.defaultStepGoal

    @State private var phoneStepsToday: Int?
    @State private var estimatedStepsToday: Int?
    @State private var fitnessAge: Double?

    private var stepGoal: Int { storedStepGoal > 0 ? storedStepGoal : CarePrefs.defaultStepGoal }

    private var todayKey: String { Repository.localDayKey(Date()) }

    private var today: CareDay {
        CareDay(day: todayKey, metric: repo.days.last(where: { $0.day == todayKey }),
                phoneSteps: phoneStepsToday, estimatedSteps: estimatedStepsToday)
    }

    /// Last night belongs to the day it ended on; before today's row exists, the most recent night.
    private var lastNight: DailyMetric? {
        repo.days.last(where: { $0.day == todayKey && $0.totalSleepMin != nil })
            ?? repo.days.last(where: { $0.totalSleepMin != nil })
    }

    var body: some View {
        ScreenScaffold(title: "Today", onRefresh: { await repo.refresh(); await loadSteps() }) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                scoresCard
                stepsCard
                SimpleHeartCard(restingHr: lastNight?.restingHr)
                fitnessAgeCard
                SimpleStrapCard()
            }
        }
        .task(id: repo.days.count) { await loadSteps() }
    }

    /// The day whose scores the rings show: today once it has a recovery score, else the most recent
    /// scored day, so the row is never blank first thing in the morning.
    private var scoredDay: DailyMetric? {
        repo.days.last(where: { $0.day == todayKey && $0.recovery != nil })
            ?? repo.days.last(where: { $0.recovery != nil })
    }

    private static let ringDiameter: CGFloat = 84
    private static let ringLineWidth: CGFloat = 8
    /// The sleep ring fills against a plain eight-hour night.
    private static let sleepTargetMinutes = 480.0

    private var scoresCard: some View {
        let day = scoredDay
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
                scoreRing(title: "Recovery", value: day?.recovery, fraction: (day?.recovery ?? 0) / 100,
                          color: StrandPalette.recoveryColor(day?.recovery ?? 0),
                          format: { "\(Int($0.rounded()))" })
                scoreRing(title: "Effort", value: day?.strain, fraction: (day?.strain ?? 0) / 100,
                          color: StrandPalette.effortColor,
                          format: { "\(Int($0.rounded()))" })
                scoreRing(title: "Sleep", value: lastNight?.totalSleepMin.map { $0 / 60 },
                          fraction: (lastNight?.totalSleepMin ?? 0) / Self.sleepTargetMinutes,
                          color: StrandPalette.restColor,
                          format: { String(format: "%.1f h", $0) })
            }
            .frame(maxWidth: .infinity)
            if let day, day.day != todayKey {
                Text("Today is not scored yet. Showing \(day.day).")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            }
        }
    }

    private func scoreRing(title: LocalizedStringKey, value: Double?, fraction: Double, color: Color,
                           format: @escaping (Double) -> String) -> some View {
        VStack(spacing: NoopMetrics.rowSpacing) {
            if let value {
                GlowRing(fraction: min(1, max(0, fraction)), value: value, format: format, color: color,
                         diameter: Self.ringDiameter, lineWidth: Self.ringLineWidth)
            } else {
                Text("—")
                    .font(GlowRing.centerFont(diameter: Self.ringDiameter))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            }
            Text(title)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var stepsCard: some View {
        let day = today
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SimpleCardTitle(title: "Steps", icon: "shoeprints.fill")
                Text(day.steps.map { "\($0)" } ?? "—")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityLabel(day.steps.map { "\($0) steps" } ?? "No step count yet")
                ProgressView(value: CareReport.stepProgress(steps: day.steps, goal: stepGoal))
                    .tint(StrandPalette.accent)
                    .accessibilityHidden(true)
                Text(stepsCaption(day))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func stepsCaption(_ day: CareDay) -> String {
        guard let steps = day.steps else { return String(localized: "Goal \(stepGoal). No step count yet today.") }
        let base = steps >= stepGoal
            ? String(localized: "Goal of \(stepGoal) reached.")
            : String(localized: "\(stepGoal - steps) to go to reach \(stepGoal).")
        return day.stepsAreEstimated ? base + " " + String(localized: "Estimated from strap movement.") : base
    }

    private var fitnessAgeCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SimpleCardTitle(title: "Fitness age", icon: "figure.walk")
                Text(fitnessAge.map { String(localized: "\(Int($0.rounded())) years") } ?? "—")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(fitnessAge == nil
                     ? String(localized: "Needs age and sex in Settings and about a week of nights. Updated weekly.")
                     : String(localized: "A fitness comparison from resting heart rate and activity, not a medical age. Updated weekly."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadSteps() async {
        let key = todayKey
        let phone = await repo.appleDailyRows(days: 3)
        phoneStepsToday = phone.last(where: { $0.day == key })?.steps
        let estimates = await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: 3)
        estimatedStepsToday = estimates.last(where: { $0.day == key }).map { Int($0.value.rounded()) }
        fitnessAge = await repo.exploreSeries(key: "fitness_age", source: "my-whoop").last?.value
    }
}

/// The icon-and-title line shared by the simple-home cards.
private struct SimpleCardTitle: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Image(systemName: icon)
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

/// Live heart rate. A leaf with its own `LiveState` subscription, so the ~1 Hz heart-rate tick
/// re-renders this card only and never the whole screen (the same split TodayView makes).
private struct SimpleHeartCard: View {
    @EnvironmentObject private var live: LiveState
    let restingHr: Int?

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SimpleCardTitle(title: "Heart rate", icon: "heart.fill")
                Text(live.heartRate.map { String(localized: "\($0) bpm") } ?? "—")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(restingHr.map { String(localized: "Resting: \($0) bpm") }
                     ?? String(localized: "Resting heart rate not available yet."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}

/// Strap battery and connection, stated in words as well as colour.
private struct SimpleStrapCard: View {
    @EnvironmentObject private var live: LiveState

    private var batteryIsLow: Bool {
        guard let pct = live.batteryPct else { return false }
        return Int(pct.rounded()) <= CareAlertEngine.Thresholds().batteryLowPct
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SimpleCardTitle(title: "Strap", icon: batteryIsLow ? "battery.25" : "battery.75")
                Text(live.batteryPct.map { String(localized: "\(Int($0.rounded()))% battery") } ?? "—")
                    .font(StrandFont.title1)
                    .foregroundStyle(batteryIsLow ? StrandPalette.statusCritical : StrandPalette.textPrimary)
                Text(statusText)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private var statusText: String {
        if batteryIsLow { return String(localized: "Battery is low. Please charge the strap.") }
        return live.bonded ? String(localized: "Connected to the strap.")
                           : String(localized: "Not connected. Keep the phone near the strap.")
    }
}
#endif
