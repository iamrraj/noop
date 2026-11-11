#if os(iOS)
import SwiftUI
import StrandDesign

/// The strap screen behind the dashboard's battery badge: which strap is connected, when it last
/// synced, its battery, and a manual sync.
struct DashboardDeviceView: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    private var batteryPct: Int? { live.batteryPct.map { Int($0.rounded()) } }

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: nil) {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    connectionCard
                    batteryCard
                    syncCard
                    NavigationLink { DevicesView() } label: { linkRow("Manage devices", icon: "applewatch") }
                        .buttonStyle(.plain)
                    NavigationLink { PowerSavingView() } label: { linkRow("Power saving", icon: "battery.25") }
                        .buttonStyle(.plain)
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    private var connectionCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                Text(live.bonded ? "CONNECTED TO" : "NOT CONNECTED")
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(live.bonded ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                Text(repo.activeDeviceDisplayName() ?? live.advertisingName ?? String(localized: "No strap"))
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let firmware = live.strapFirmware {
                    Text("Firmware \(firmware)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if !live.bonded {
                    Text("Keep the phone near the strap and leave NOOP open in the background.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var batteryCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("BATTERY")
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(batteryPct.map { "\($0)%" } ?? "—")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                ProgressView(value: Double(batteryPct ?? 0) / 100)
                    .tint(batteryTint)
                    .accessibilityHidden(true)
                Text(batteryStatus).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var batteryTint: Color {
        guard let pct = batteryPct else { return StrandPalette.textTertiary }
        return pct <= 15 ? StrandPalette.statusCritical : (pct <= 40 ? StrandPalette.statusWarning : StrandPalette.statusPositive)
    }

    private var batteryStatus: String {
        guard let pct = batteryPct else { return String(localized: "No battery reading yet.") }
        if live.charging == true { return String(localized: "Charging.") }
        return pct <= 15 ? String(localized: "Low. Please charge the strap.") : String(localized: "Not charging.")
    }

    private var syncCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("SYNC")
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                HStack {
                    Text("Last sync").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 0)
                    Text(lastSyncText).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                }
                Text("NOOP syncs by itself whenever the strap is connected, including in the background. Swiping the app away stops it until NOOP is opened again.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = live.lastSyncError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.statusCritical)
                }
                Button { ble.syncNow() } label: {
                    Text(live.backfilling ? "Syncing…" : "Sync now").font(StrandFont.subhead)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(!live.bonded || live.backfilling)
            }
        }
    }

    private var lastSyncText: String {
        guard let last = live.lastSyncedAt else { return String(localized: "Not yet this session") }
        return Date(timeIntervalSince1970: last).formatted(date: .abbreviated, time: .shortened)
    }

    private func linkRow(_ title: LocalizedStringKey, icon: String) -> some View {
        NoopCard {
            HStack(spacing: NoopMetrics.cardInnerSpacing) {
                Image(systemName: icon).foregroundStyle(StrandPalette.accent).accessibilityHidden(true)
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}
#endif
