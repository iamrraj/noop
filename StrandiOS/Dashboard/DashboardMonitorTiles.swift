#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The Health Monitor and Stress Monitor tiles, side by side.
struct DashboardMonitorTiles: View {
    @EnvironmentObject private var repo: Repository
    /// Today's stress result; nil on an earlier day or before it has been scored.
    let stress: DaytimeStress.Result?
    let isToday: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
            NavigationLink(value: TabRoute.health) { healthTile }.buttonStyle(.plain)
            NavigationLink(value: TabRoute.stress) { stressTile }.buttonStyle(.plain)
        }
    }

    // MARK: - Health

    /// The latest vital readings, banded against the wearer's own baseline. The same resolver the
    /// Health screen uses, so the tile and the screen it opens can never disagree.
    private var readings: [BodyVitalReading] {
        BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows, temperatureUnit: .celsius)
            .filter { $0.banding.band != .noData }
    }

    private var healthTile: some View {
        let measured = readings
        let outOfRange = measured.filter { $0.banding.band == .outOfRange }.count
        let allInRange = outOfRange == 0
        return tile(title: "HEALTH MONITOR") {
            if measured.isEmpty {
                tileBody(icon: "minus", tint: StrandPalette.textTertiary,
                         headline: "NO DATA", detail: String(localized: "Needs a few nights"))
            } else {
                tileBody(icon: allInRange ? "checkmark" : "exclamationmark",
                         tint: allInRange ? StrandPalette.statusPositive : StrandPalette.statusWarning,
                         headline: allInRange ? "WITHIN RANGE" : "OUT OF RANGE",
                         detail: String(localized: "\(measured.count - outOfRange)/\(measured.count) metrics"))
            }
        }
    }

    // MARK: - Stress

    private var stressTile: some View {
        let latest = stress?.timeline.last(where: { $0.level != nil })
        return tile(title: "STRESS MONITOR") {
            if let latest, let level = latest.level {
                let band = DashboardWeek.stressBand(level)
                tileBody(text: String(format: "%.1f", level), tint: color(band), headline: label(band),
                         detail: Date(timeIntervalSince1970: TimeInterval(latest.startTs))
                            .formatted(date: .omitted, time: .shortened))
            } else {
                tileBody(icon: "minus", tint: StrandPalette.textTertiary, headline: "NO DATA",
                         detail: isToday ? String(localized: "Not scored yet") : String(localized: "Shown for today only"))
            }
        }
    }

    private func color(_ band: DashboardWeek.StressBand) -> Color {
        switch band {
        case .low: return StrandPalette.restColor
        case .medium: return StrandPalette.statusPositive
        case .high: return StrandPalette.statusWarning
        }
    }

    private func label(_ band: DashboardWeek.StressBand) -> LocalizedStringKey {
        switch band {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        }
    }

    // MARK: - Shared chrome

    private func tile<Content: View>(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                content()
            }
        }
    }

    private func tileBody(icon: String? = nil, text: String? = nil, tint: Color,
                          headline: LocalizedStringKey, detail: String) -> some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Group {
                if let text { Text(text) } else if let icon { Image(systemName: icon) }
            }
            .font(StrandFont.headline)
            .foregroundStyle(tint)
            .frame(minWidth: 36, minHeight: 36)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius / 2))
            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(tint)
                Text(detail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
