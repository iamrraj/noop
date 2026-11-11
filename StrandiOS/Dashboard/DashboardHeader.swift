#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The dashboard's top bar: profile picture, the day switcher, and the strap battery.
struct DashboardHeader: View {
    @EnvironmentObject private var profile: ProfileStore
    @Binding var dayOffset: Int
    let selectedKey: String

    @State private var showsProfile = false
    @State private var showsDevice = false

    private static let avatarSize: CGFloat = 36

    var body: some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Button { showsProfile = true } label: {
                ProfileAvatarView(imageData: profile.avatarImageData, size: Self.avatarSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
            Spacer(minLength: 0)
            daySwitcher
            Spacer(minLength: 0)
            Button { showsDevice = true } label: { DashboardBatteryBadge() }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the strap's details")
        }
        .sheet(isPresented: $showsProfile) { DashboardProfileView() }
        .sheet(isPresented: $showsDevice) { DashboardDeviceView() }
    }

    private var daySwitcher: some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Button { dayOffset -= 1 } label: {
                Image(systemName: "chevron.left").font(StrandFont.headline)
            }
            .accessibilityLabel("Previous day")
            Text(dayLabel)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 96)
            Button { dayOffset = min(0, dayOffset + 1) } label: {
                Image(systemName: "chevron.right").font(StrandFont.headline)
                    .foregroundStyle(dayOffset >= 0 ? StrandPalette.textTertiary : StrandPalette.textPrimary)
            }
            .disabled(dayOffset >= 0)
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(StrandPalette.textPrimary)
        .padding(.horizontal, NoopMetrics.cardInnerSpacing)
        .padding(.vertical, NoopMetrics.rowSpacing)
        .background(StrandPalette.surfaceRaised, in: Capsule())
    }

    private var dayLabel: String {
        switch dayOffset {
        case 0: return String(localized: "TODAY")
        case -1: return String(localized: "YESTERDAY")
        default: return BodyVitalReading.dayLabel(selectedKey).uppercased()
        }
    }
}

/// Strap battery, in its own leaf so the live state's frequent updates do not redraw the header.
private struct DashboardBatteryBadge: View {
    @EnvironmentObject private var live: LiveState

    var body: some View {
        HStack(spacing: NoopMetrics.syncIndicatorLabelSpacing) {
            Text(live.batteryPct.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Image(systemName: live.bonded ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .foregroundStyle(live.bonded ? StrandPalette.statusPositive : StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(live.batteryPct.map { "Strap battery \(Int($0.rounded())) percent" } ?? "Strap battery unknown")
        .accessibilityValue(live.bonded ? "Connected" : "Not connected")
    }
}
#endif
