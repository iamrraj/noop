#if os(iOS)
import SwiftUI
import StrandDesign

/// Settings for the family "care" features: the simple home screen, the daily step goal, and the
/// summary and alert emails sent to a family member. The email account itself is build-time
/// configuration (`CareConfig`), so this screen only reports whether one is present.
struct CareSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(CarePrefs.simpleHomeKey) private var simpleHome = false
    @AppStorage(CarePrefs.stepGoalKey) private var stepGoal = CarePrefs.defaultStepGoal
    @AppStorage(CarePrefs.enabledKey) private var emailsEnabled = true
    @AppStorage(CarePrefs.sendHourKey) private var sendHour = CarePrefs.defaultSendHour
    @AppStorage(CarePrefs.lastErrorKey) private var lastError = ""
    @AppStorage(CarePrefs.lastSentAtKey) private var lastSentAt = 0.0

    @State private var isSendingTest = false
    @State private var testResult: String?

    private let config = CareConfig.fromBundle

    var body: some View {
        ScreenScaffold(title: "Family updates",
                       subtitle: "A simpler home screen, a step goal, and emails to a family member.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                homeCard
                emailCard
            }
        }
    }

    private var homeCard: some View {
        StrandCard(padding: NoopMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                cardTitle("Home screen", icon: "house.fill")
                Toggle(isOn: $simpleHome) {
                    Text("Simple home screen")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                caption("Shows only the recovery, effort and sleep rings, steps, heart rate and strap battery in large type, and shortens the More list.")
                Stepper(value: $stepGoal, in: 1000...30_000, step: 500) {
                    Text("Daily step goal: \(stepGoal)")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
        }
    }

    private var emailCard: some View {
        StrandCard(padding: NoopMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                cardTitle("Emails", icon: "envelope.fill")
                if let config {
                    Toggle(isOn: $emailsEnabled) {
                        Text("Send summary and alert emails")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(StrandPalette.accent)
                    caption("Sent to \(config.to). Each morning: yesterday's steps, sleep, heart and strap status. Separately: an alert when the strap battery is low or the phone has lost contact with the strap.")
                    Stepper(value: $sendHour, in: 4...12) {
                        Text("Morning summary from \(sendHour):00")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    caption("iOS decides when the app may run in the background, so the summary goes out at the first chance after this hour, not at an exact time. Nothing is sent while the phone is off.")
                    Button {
                        Task { await sendTest() }
                    } label: {
                        Text(isSendingTest ? "Sending…" : "Send test email")
                            .font(StrandFont.subhead)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(isSendingTest)
                    statusLines
                } else {
                    caption("Emails are not set up in this build. Add Strand/Care/CareSecrets.xcconfig (see the example file beside it) and rebuild the app.")
                }
            }
        }
    }

    @ViewBuilder private var statusLines: some View {
        if let testResult {
            Text(testResult)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if lastSentAt > 0 {
            caption("Last email sent \(Date(timeIntervalSince1970: lastSentAt).formatted(date: .abbreviated, time: .shortened)).")
        }
        if !lastError.isEmpty {
            Label {
                Text("Last attempt failed: \(lastError)")
                    .font(StrandFont.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(StrandPalette.statusCritical)
        }
    }

    private func sendTest() async {
        isSendingTest = true
        defer { isSendingTest = false }
        switch await CareReporter.sendTest(model: model) {
        case .sent: testResult = String(localized: "Test email sent. Check the inbox and the spam folder.")
        case .failed(let reason): testResult = String(localized: "Test email failed: \(reason)")
        case .notConfigured: testResult = String(localized: "Emails are not set up in this build.")
        case .disabled, .nothingDue: testResult = nil
        }
    }

    private func cardTitle(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Image(systemName: icon)
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
