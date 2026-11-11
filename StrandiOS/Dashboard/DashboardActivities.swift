#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The day's sleep and workouts as a list: a coloured badge with the headline figure, the activity
/// name, and its start and end times.
struct DashboardActivities: View {
    let dayKey: String
    let isToday: Bool
    let sleeps: [CachedSleepSession]
    let workouts: [WorkoutRow]
    let effortScale: EffortScale

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text(isToday ? "My Day" : "That Day")
                .font(StrandFont.title1)
                .foregroundStyle(StrandPalette.textPrimary)
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    Text(isToday ? "TODAY'S ACTIVITIES" : "ACTIVITIES")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textPrimary)
                    if sleeps.isEmpty && workouts.isEmpty {
                        Text("Nothing recorded for this day yet.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    ForEach(sleeps, id: \.startTs) { night in
                        NavigationLink(value: TabRoute.sleep) {
                            activityRow(icon: "moon.fill", tint: StrandPalette.restColor,
                                        figure: Self.duration(night.endTs - night.effectiveStartTs),
                                        title: "SLEEP", start: night.effectiveStartTs, end: night.endTs)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(workouts, id: \.startTs) { workout in
                        NavigationLink(value: TabRoute.workouts) {
                            activityRow(icon: WorkoutTypeIconography.systemSymbolName(for: workout.sport),
                                        tint: StrandPalette.effortColor, figure: figure(workout),
                                        title: LocalizedStringKey(workout.sport.uppercased()),
                                        start: workout.startTs, end: workout.endTs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A workout's badge shows its effort when it has one, else how long it lasted.
    private func figure(_ workout: WorkoutRow) -> String {
        guard let strain = workout.strain else { return Self.duration(workout.endTs - workout.startTs) }
        let shown = UnitFormatter.effortValue(strain, scale: effortScale)
        return effortScale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))"
    }

    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func activityRow(icon: String, tint: Color, figure: String, title: LocalizedStringKey,
                             start: Int, end: Int) -> some View {
        HStack(spacing: NoopMetrics.cardInnerSpacing) {
            HStack(spacing: NoopMetrics.syncIndicatorLabelSpacing) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(figure).font(StrandFont.headline)
            }
            .foregroundStyle(StrandPalette.surfaceBase)
            .padding(.horizontal, NoopMetrics.cardInnerSpacing)
            .padding(.vertical, NoopMetrics.rowSpacing)
            .frame(minWidth: 104, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius / 2))
            Text(title)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Self.clock(start))
                Text(Self.clock(end))
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(NoopMetrics.rowSpacing)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
        .accessibilityElement(children: .combine)
    }

    private static func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }
}
#endif
