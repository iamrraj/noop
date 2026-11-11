#if os(iOS)
import SwiftUI
import StrandDesign

/// Sleep, Recovery and Effort as three rings, each opening its detail screen.
struct DashboardRingsRow: View {
    let sleepPerformance: Double?
    let recovery: Double?
    /// Stored 0–100 effort; shown on the user's chosen scale.
    let effort: Double?
    let effortScale: EffortScale

    private static let diameter: CGFloat = 96
    private static let lineWidth: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
            ring("SLEEP", route: .sleep, value: sleepPerformance, fraction: (sleepPerformance ?? 0) / 100,
                 color: StrandPalette.restColor, format: { "\(Int($0.rounded()))%" })
            ring("RECOVERY", route: .metric("recovery"), value: recovery, fraction: (recovery ?? 0) / 100,
                 color: StrandPalette.recoveryColor(recovery ?? 0), format: { "\(Int($0.rounded()))%" })
            ring("EFFORT", route: .metric("strain"),
                 value: effort.map { UnitFormatter.effortValue($0, scale: effortScale) },
                 fraction: (effort ?? 0) / 100, color: StrandPalette.effortColor,
                 format: { effortScale == .whoop ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" })
        }
    }

    private func ring(_ title: LocalizedStringKey, route: TabRoute, value: Double?, fraction: Double,
                      color: Color, format: @escaping (Double) -> String) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: NoopMetrics.rowSpacing) {
                if let value {
                    GlowRing(fraction: min(1, max(0, fraction)), value: value, format: format, color: color,
                             diameter: Self.diameter, lineWidth: Self.lineWidth)
                } else {
                    Text("—")
                        .font(GlowRing.centerFont(diameter: Self.diameter))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: Self.diameter, height: Self.diameter)
                }
                HStack(spacing: NoopMetrics.syncIndicatorLabelSpacing) {
                    Text(title)
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                    Image(systemName: "chevron.right").font(StrandFont.overline)
                }
                .foregroundStyle(StrandPalette.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
#endif
