#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Records, current streaks and notable stats over a chosen window.
struct DashboardProfileHighlights: View {
    @Binding var window: ProfileHighlights.Window
    let summary: ProfileHighlights.Summary
    let streaks: ProfileHighlights.Streaks
    let effortScale: EffortScale

    private static let ringDiameter: CGFloat = 80
    private static let ringLineWidth: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text("Data Highlights").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    DashboardWindowPicker(window: $window)
                    HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
                        record("Best Sleep", value: summary.bestSleep, fraction: (summary.bestSleep ?? 0) / 100,
                               color: StrandPalette.restColor, format: { "\(Int($0.rounded()))%" })
                        record("Peak Recovery", value: summary.peakRecovery, fraction: (summary.peakRecovery ?? 0) / 100,
                               color: StrandPalette.recoveryColor(summary.peakRecovery ?? 0), format: { "\(Int($0.rounded()))%" })
                        record("Max Effort", value: summary.maxEffort.map { UnitFormatter.effortValue($0, scale: effortScale) },
                               fraction: (summary.maxEffort ?? 0) / 100, color: StrandPalette.effortColor,
                               format: { effortScale == .whoop ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" })
                    }
                    section("STREAKS") {
                        HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
                            streak(streaks.sleep, "70%+ Sleep", icon: "moon.fill", tint: StrandPalette.restColor)
                            streak(streaks.greenRecovery, "Green Recovery", icon: "heart.fill", tint: StrandPalette.statusPositive)
                            streak(streaks.effort, effortScale == .whoop ? "10+ Effort" : "48+ Effort",
                                   icon: "flame.fill", tint: StrandPalette.effortColor)
                        }
                    }
                    section("NOTABLE STATS") {
                        VStack(spacing: NoopMetrics.rowSpacing) {
                            stat("Lowest resting heart rate", summary.lowestRestingHr, unit: "bpm")
                            stat("Highest resting heart rate", summary.highestRestingHr, unit: "bpm")
                            stat("Lowest HRV", summary.lowestHrv, unit: "ms")
                            stat("Highest HRV", summary.highestHrv, unit: "ms")
                        }
                    }
                }
            }
        }
    }

    private func record(_ title: LocalizedStringKey, value: Double?, fraction: Double, color: Color,
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
            Text(title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text(title)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textSecondary)
            content()
        }
    }

    private func streak(_ days: Int, _ title: LocalizedStringKey, icon: String, tint: Color) -> some View {
        VStack(spacing: NoopMetrics.syncIndicatorLabelSpacing) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text("\(days) days").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: LocalizedStringKey, _ value: Double?, unit: String) -> some View {
        HStack {
            Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 0)
            Text(value.map { "\(Int($0.rounded())) \(unit)" } ?? "—")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 1M / 3M / All time switch shared by the profile's sections.
struct DashboardWindowPicker: View {
    @Binding var window: ProfileHighlights.Window

    var body: some View {
        Picker("Period", selection: $window) {
            Text("1M").tag(ProfileHighlights.Window.month)
            Text("3M").tag(ProfileHighlights.Window.quarter)
            Text("ALL TIME").tag(ProfileHighlights.Window.allTime)
        }
        .pickerStyle(.segmented)
    }
}

/// Activities in the window, most frequent first, each with a bar scaled to the most frequent.
struct DashboardProfileActivities: View {
    let stats: [ProfileHighlights.ActivityStat]
    let effortScale: EffortScale

    private static let shown = 6

    var body: some View {
        let top = stats.first?.count ?? 0
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text("Activity Summary").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    Text("\(stats.reduce(0) { $0 + $1.count })")
                        .font(StrandFont.title1)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("TOTAL ACTIVITIES")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if stats.isEmpty {
                        Text("No activities in this period.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    ForEach(stats.prefix(Self.shown)) { stat in
                        VStack(alignment: .leading, spacing: NoopMetrics.syncIndicatorLabelSpacing) {
                            HStack {
                                Image(systemName: WorkoutTypeIconography.systemSymbolName(for: stat.sport))
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .accessibilityHidden(true)
                                Text(stat.sport.uppercased())
                                    .font(StrandFont.overline)
                                    .tracking(StrandFont.overlineTracking)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                if let effort = stat.averageEffort {
                                    Text(effortText(effort)).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Text("\(stat.count)x").font(StrandFont.headline).foregroundStyle(StrandPalette.effortColor)
                            }
                            ProgressView(value: top > 0 ? Double(stat.count) / Double(top) : 0)
                                .tint(StrandPalette.effortColor)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func effortText(_ stored: Double) -> String {
        let shown = UnitFormatter.effortValue(stored, scale: effortScale)
        return effortScale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))"
    }
}
#endif
