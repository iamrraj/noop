import Combine
import Foundation
import StrandAnalytics
import UserNotifications

/// A reminder that fires only when the app has stopped running.
///
/// A swiped-away app, or one never reopened after the phone restarted, cannot sync the strap, send an
/// email or notice that it has stopped. So the reminder is scheduled in advance and pushed forward
/// every time the app shows a sign of life; it reaches the screen only when nothing was left running
/// to push it. `CareSchedule.keepAliveFireDate` decides the time and keeps it out of the night.
@MainActor
enum CareKeepAlive {
    static let enabledKey = "noop.care.keepAliveReminder"
    static let identifier = "noop.care.keepalive"
    /// Re-arming replaces a pending request; once per this interval is plenty.
    static let minRearmInterval: TimeInterval = 10 * 60

    private static var lastArmedAt: Date?
    private static var subscriptions: Set<AnyCancellable> = []

    /// On by default wherever the family features are in use: the simple home is switched on, or the
    /// build carries email credentials.
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: enabledKey) as? Bool { return stored }
        return defaults.bool(forKey: CarePrefs.simpleHomeKey) || CareConfig.fromBundle != nil
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Follow the strap's own traffic, so a backgrounded app that is still receiving data keeps
    /// pushing the reminder forward without waiting for iOS to grant a background task.
    static func start(live: LiveState) {
        guard subscriptions.isEmpty else { return }
        live.$lastSyncedAt.dropFirst().sink { _ in Task { @MainActor in rearm() } }.store(in: &subscriptions)
        live.$batteryPct.dropFirst().sink { _ in Task { @MainActor in rearm() } }.store(in: &subscriptions)
    }

    /// Push the reminder forward, or clear it when the feature is off.
    static func rearm(now: Date = Date(), defaults: UserDefaults = .standard, force: Bool = false) {
        let center = UNUserNotificationCenter.current()
        guard isEnabled(defaults) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            lastArmedAt = nil
            return
        }
        if !force, let last = lastArmedAt, now.timeIntervalSince(last) < minRearmInterval { return }
        lastArmedAt = now

        let fireDate = CareSchedule.keepAliveFireDate(now: now, calendar: .current)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "NOOP has stopped updating")
        content.body = String(localized: "Open NOOP so it can keep reading the strap. Leave it open in the background; do not swipe it away.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, fireDate.timeIntervalSince(now)), repeats: false)
        // Adding under the same identifier replaces the pending request.
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
