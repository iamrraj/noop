#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// One card per headline metric: the day's value, an arrow against the week before it, and the
/// typical value that arrow is measured from.
struct DashboardMetricRows: View {
    let rows: [DashboardMetricRow]

    var body: some View {
        VStack(spacing: NoopMetrics.rowSpacing) {
            ForEach(rows) { row in
                NavigationLink(value: row.route) { card(row) }.buttonStyle(.plain)
            }
        }
    }

    private func card(_ row: DashboardMetricRow) -> some View {
        NoopCard {
            HStack(spacing: NoopMetrics.cardInnerSpacing) {
                Image(systemName: row.icon)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityHidden(true)
                Text(row.title)
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: NoopMetrics.syncIndicatorLabelSpacing) {
                        Text(row.value.map { "\(Int($0.rounded())) \(row.unit)" } ?? "—")
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let trend = row.trend {
                            Image(systemName: symbol(trend.direction))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .accessibilityLabel(label(trend.direction))
                        }
                    }
                    if let trend = row.trend {
                        Text("Typical \(Int(trend.typical.rounded()))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ direction: DashboardWeek.Direction) -> String {
        switch direction {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "minus"
        }
    }

    private func label(_ direction: DashboardWeek.Direction) -> LocalizedStringKey {
        switch direction {
        case .up: return "Above typical"
        case .down: return "Below typical"
        case .flat: return "About typical"
        }
    }
}
#endif
