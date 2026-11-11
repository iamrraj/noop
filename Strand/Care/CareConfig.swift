import Foundation

/// The SMTP account and addresses behind the family "care" emails, injected at build time via the
/// untracked `CareSecrets.xcconfig` → Info.plist. Absent or blank values mean the feature is off:
/// a default build sends nothing and has nowhere to send it.
struct CareConfig: Equatable {
    let host: String
    let port: UInt16
    let username: String
    let password: String
    let from: String
    let to: String
    let personName: String

    /// Build from an Info-dictionary-shaped map. Returns nil unless every required key is present and
    /// non-blank, so a half-filled secrets file disables the feature rather than half-configuring it.
    static func from(_ info: [String: Any]) -> CareConfig? {
        func nonBlank(_ key: String) -> String? {
            guard let s = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty else { return nil }
            return s
        }
        guard let host = nonBlank("CARE_SMTP_HOST"),
              let portText = nonBlank("CARE_SMTP_PORT"), let port = UInt16(portText), port > 0,
              let username = nonBlank("CARE_SMTP_USERNAME"),
              let password = nonBlank("CARE_SMTP_PASSWORD"),
              let from = nonBlank("CARE_EMAIL_FROM"),
              let to = nonBlank("CARE_EMAIL_TO") else { return nil }
        return CareConfig(host: host, port: port, username: username, password: password,
                          from: from, to: to, personName: nonBlank("CARE_PERSON_NAME") ?? "")
    }

    /// The live configuration from the app bundle's Info.plist, or nil if not configured.
    static var fromBundle: CareConfig? { from(Bundle.main.infoDictionary ?? [:]) }
}

/// User-adjustable settings and send bookkeeping, in `UserDefaults`.
enum CarePrefs {
    static let enabledKey = "noop.care.enabled"
    static let stepGoalKey = "noop.care.stepGoal"
    static let sendHourKey = "noop.care.sendHour"
    static let simpleHomeKey = "noop.care.simpleHome"
    static let lastSummaryDayKey = "noop.care.lastSummaryDay"
    static let alertLedgerKey = "noop.care.alertLedger"
    static let lastErrorKey = "noop.care.lastError"
    static let lastSentAtKey = "noop.care.lastSentAt"

    static let defaultStepGoal = 5000
    static let defaultSendHour = 7

    /// On by default: the emails only exist in a build someone deliberately gave credentials to.
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func stepGoal(_ defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: stepGoalKey)
        return stored > 0 ? stored : defaultStepGoal
    }

    static func sendHour(_ defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: sendHourKey) as? Int, (0...23).contains(stored) else {
            return defaultSendHour
        }
        return stored
    }

    static func alertLedger(_ defaults: UserDefaults = .standard) -> [String: Int] {
        defaults.dictionary(forKey: alertLedgerKey) as? [String: Int] ?? [:]
    }
}
