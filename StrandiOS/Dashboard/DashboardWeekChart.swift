#if os(iOS)
import Charts
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Seven days of effort and recovery on one chart. Both are plotted on the stored 0–100 axis so the
/// two lines share a scale; the point labels carry each value in its own display unit.
struct DashboardWeekChart: View {
    let points: [DashboardWeekPoint]
    let selectedKey: String
    let effortScale: EffortScale

    private static let height: CGFloat = 220

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("EFFORT & RECOVERY")
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textPrimary)
                if points.contains(where: { $0.effort != nil || $0.recovery != nil }) {
                    chart
                    legend
                } else {
                    Text("No scored days in this week yet.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            if points.contains(where: { $0.day == selectedKey }) {
                RuleMark(x: .value("Day", selectedKey))
                    .foregroundStyle(StrandPalette.surfaceInset)
                    .lineStyle(StrokeStyle(lineWidth: 28))
            }
            ForEach(points) { point in
                // The higher point carries its label above and the lower one below, so two values
                // that land close together never print over each other.
                let effortOnTop = (point.effort ?? 0) >= (point.recovery ?? 0)
                if let recovery = point.recovery {
                    LineMark(x: .value("Day", point.day), y: .value("Score", recovery),
                             series: .value("Series", "Recovery"))
                        .foregroundStyle(StrandPalette.textTertiary)
                    PointMark(x: .value("Day", point.day), y: .value("Score", recovery))
                        .foregroundStyle(StrandPalette.recoveryColor(recovery))
                        .annotation(position: effortOnTop ? .bottom : .top) {
                            Text("\(Int(recovery.rounded()))%")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.recoveryColor(recovery))
                        }
                }
                if let effort = point.effort {
                    LineMark(x: .value("Day", point.day), y: .value("Score", effort),
                             series: .value("Series", "Effort"))
                        .foregroundStyle(StrandPalette.effortColor)
                    PointMark(x: .value("Day", point.day), y: .value("Score", effort))
                        .foregroundStyle(StrandPalette.effortColor)
                        .annotation(position: effortOnTop ? .top : .bottom) {
                            Text(effortText(effort))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.effortColor)
                        }
                }
            }
        }
        .chartXScale(domain: points.map(\.day))
        .chartYScale(domain: -15...115)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: points.map(\.day)) { value in
                AxisValueLabel {
                    if let day = value.as(String.self) {
                        Text(Self.axisLabel(day))
                            .multilineTextAlignment(.center)
                            .font(StrandFont.caption)
                            .foregroundStyle(day == selectedKey ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    }
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityLabel("Effort and recovery over seven days")
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.cardInnerSpacing) {
            Label("Effort", systemImage: "circle.fill").foregroundStyle(StrandPalette.effortColor)
            Label("Recovery", systemImage: "circle.fill").foregroundStyle(StrandPalette.textSecondary)
        }
        .font(StrandFont.caption)
    }

    private func effortText(_ stored: Double) -> String {
        let shown = UnitFormatter.effortValue(stored, scale: effortScale)
        return effortScale == .whoop ? String(format: "%.1f", shown) : "\(Int(shown.rounded()))"
    }

    /// "Wed\n11" in the user's language.
    static func axisLabel(_ day: String) -> String {
        guard let weekday = DashboardWeek.weekday(day), let number = DashboardWeek.dayOfMonth(day) else { return day }
        let symbols = Calendar.current.shortWeekdaySymbols
        let name = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
        return "\(name)\n\(number)"
    }
}
#endif
