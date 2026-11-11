import Foundation

// CareReportHTML.swift — the designed version of the family emails.
//
// Mail clients ignore most of CSS: no stylesheets in Gmail's clipped views, no flexbox or grid in
// Outlook, no web fonts, no scripts. So this is written the way email has to be: nested tables, every
// style inline, system fonts, one fluid 600-pixel column, and colour used only as a second signal
// beside the words. The plain-text body is always sent alongside it and says the same things.
//
// Every value that came from data is escaped on its way in; nothing here trusts a name or a message.

public enum CareReportHTML {

    // MARK: - Palette

    static let ink = "#14181c"
    static let muted = "#5b6670"
    static let rule = "#e3e7ea"
    static let page = "#eef1f3"
    static let card = "#ffffff"
    static let header = "#101418"
    static let effort = "#2a78c8"
    static let sleep = "#5e7896"
    static let good = "#0f9d62"
    static let fair = "#b8860b"
    static let poor = "#c0392b"
    static let alertFill = "#fdf1e7"
    static let alertEdge = "#d9682a"

    static let font = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Recovery is read in three bands, the same thirds the app's ring uses.
    static func recoveryColor(_ value: Double) -> String {
        value >= 67 ? good : (value >= 34 ? fair : poor)
    }

    // MARK: - Documents

    public static func dailySummary(personName: String, day: CareDay, stepGoal: Int?,
                                    device: CareDeviceStatus, alerts: [CareAlert],
                                    nowTs: Int, fitnessAge: Double? = nil) -> String {
        let name = escape(CareReport.displayName(personName))
        var rows: [String] = []
        rows.append(headerBlock(eyebrow: "Daily summary", title: name, detail: escape(CareReport.longDate(day.day))))
        if !alerts.isEmpty { rows.append(alertBlock(alerts)) }
        if day.isEmpty {
            rows.append(noteBlock("No strap data was recorded for this day. The strap may not have been worn, or it has not synced with the phone yet."))
        }
        rows.append(scoreBlock(day))
        rows.append(stepsBlock(day, goal: stepGoal))
        var details: [(String, String)] = [
            ("Time asleep", CareReport.durationText(day.sleepMinutes)),
            ("Sleep disturbances", day.disturbances.map(String.init) ?? CareReport.missing),
            ("Resting heart rate", day.restingHr.map { "\($0) bpm" } ?? CareReport.missing),
            ("Heart-rate variability", day.hrvMs.map { "\(Int($0.rounded())) ms" } ?? CareReport.missing),
            ("Workouts", day.workouts.map(String.init) ?? CareReport.missing),
        ]
        if let fitnessAge { details.append(("Fitness age", "\(Int(fitnessAge.rounded())) (updated weekly)")) }
        rows.append(tableBlock(title: "Yesterday in detail", rows: details))
        rows.append(tableBlock(title: "Strap", rows: [
            ("Battery", device.batteryPct.map { "\($0)%" } ?? CareReport.missing),
            ("Last heard from strap", CareReport.lastContactText(device.lastContactTs, nowTs: nowTs)),
            ("Connected", device.connected ? "Yes" : "No"),
        ]))
        rows.append(footerBlock)
        let preview = alerts.isEmpty ? "Yesterday's steps, sleep, heart and strap status."
                                     : "\(alerts.count) item\(alerts.count == 1 ? "" : "s") need\(alerts.count == 1 ? "s" : "") attention."
        return document(title: "\(name): daily summary", preview: preview, rows: rows)
    }

    public static func urgentAlert(personName: String, alerts: [CareAlert], day: String) -> String {
        let name = escape(CareReport.displayName(personName))
        let rows = [headerBlock(eyebrow: "Alert", title: name, detail: escape(CareReport.longDate(day))), alertBlock(alerts), footerBlock]
        return document(title: "Alert for \(name)", preview: alerts.first?.message ?? "Alert", rows: rows)
    }

    // MARK: - Blocks

    static func document(title: String, preview: String, rows: [String]) -> String {
        """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title></head>
        <body style="margin:0;padding:0;background:\(page);">
        <div style="display:none;max-height:0;overflow:hidden;">\(escape(preview))</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:\(page);"><tr><td align="center" style="padding:24px 12px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:\(card);border-radius:14px;overflow:hidden;font-family:\(font);color:\(ink);">
        \(rows.joined(separator: "\n"))
        </table>
        </td></tr></table>
        </body></html>
        """
    }

    static func headerBlock(eyebrow: String, title: String, detail: String) -> String {
        """
        <tr><td style="background:\(header);padding:28px 28px 24px;">
        <div style="font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#9aa5ae;">\(escape(eyebrow))</div>
        <div style="font-size:28px;line-height:34px;font-weight:700;color:#ffffff;padding-top:6px;">\(title)</div>
        <div style="font-size:15px;color:#c3cad0;padding-top:2px;">\(detail)</div>
        </td></tr>
        """
    }

    static func alertBlock(_ alerts: [CareAlert]) -> String {
        let items = alerts.map {
            "<div style=\"font-size:15px;line-height:22px;color:\(ink);padding-top:6px;\">\(escape($0.message))</div>"
        }.joined()
        return """
        <tr><td style="padding:20px 28px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
        <td style="background:\(alertFill);border-left:4px solid \(alertEdge);border-radius:6px;padding:14px 16px;">
        <div style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;font-weight:700;color:\(alertEdge);">Needs attention</div>
        \(items)
        </td></tr></table>
        </td></tr>
        """
    }

    static func noteBlock(_ text: String) -> String {
        "<tr><td style=\"padding:20px 28px 0;font-size:15px;line-height:22px;color:\(muted);\">\(escape(text))</td></tr>"
    }

    static func scoreBlock(_ day: CareDay) -> String {
        func cell(_ label: String, _ value: String, _ unit: String, _ color: String) -> String {
            """
            <td width="33%" align="center" style="padding:0 4px;">
            <div style="border-top:4px solid \(color);background:#f6f8f9;border-radius:8px;padding:14px 4px 12px;">
            <div style="font-size:30px;line-height:34px;font-weight:700;color:\(ink);">\(value)<span style="font-size:14px;font-weight:600;color:\(muted);">\(unit)</span></div>
            <div style="font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:\(muted);padding-top:4px;">\(label)</div>
            </div></td>
            """
        }
        let dash = "&ndash;"
        let recovery = cell("Recovery", day.recovery.map { "\(Int($0.rounded()))" } ?? dash,
                            day.recovery == nil ? "" : "%", day.recovery.map(recoveryColor) ?? rule)
        let effortCell = cell("Effort", day.strain.map { "\(Int($0.rounded()))" } ?? dash,
                              day.strain == nil ? "" : "/100", day.strain == nil ? rule : effort)
        let hours = day.sleepMinutes.map { String(format: "%.1f", $0 / 60) }
        let sleepCell = cell("Sleep", hours ?? dash, hours == nil ? "" : " h", hours == nil ? rule : sleep)
        return """
        <tr><td style="padding:24px 24px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>\(recovery)\(effortCell)\(sleepCell)</tr></table>
        </td></tr>
        """
    }

    static func stepsBlock(_ day: CareDay, goal: Int?) -> String {
        let goalValue = (goal ?? 0) > 0 ? goal : nil
        let percent = goalValue.map { Int((CareReport.stepProgress(steps: day.steps, goal: $0) * 100).rounded()) } ?? 0
        let headline = day.steps.map(String.init) ?? "&ndash;"
        var caption = day.steps == nil ? "No step count for this day" : (goalValue.map { "of \($0) goal" } ?? "steps")
        if day.stepsAreEstimated { caption += " &middot; estimated from strap movement" }
        // A zero-width cell collapses badly in some clients, so an empty bar is drawn as track only.
        let bar = percent <= 0
            ? "<td style=\"background:\(rule);height:8px;border-radius:4px;font-size:0;line-height:0;\">&nbsp;</td>"
            : percent >= 100
                ? "<td style=\"background:\(good);height:8px;border-radius:4px;font-size:0;line-height:0;\">&nbsp;</td>"
                : "<td width=\"\(percent)%\" style=\"background:\(good);height:8px;border-radius:4px 0 0 4px;font-size:0;line-height:0;\">&nbsp;</td><td style=\"background:\(rule);height:8px;border-radius:0 4px 4px 0;font-size:0;line-height:0;\">&nbsp;</td>"
        return """
        <tr><td style="padding:24px 28px 0;">
        <div style="font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:\(muted);">Steps</div>
        <div style="font-size:30px;line-height:36px;font-weight:700;color:\(ink);">\(headline) <span style="font-size:14px;font-weight:400;color:\(muted);">\(caption)</span></div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:8px;"><tr>\(bar)</tr></table>
        </td></tr>
        """
    }

    static func tableBlock(title: String, rows: [(String, String)]) -> String {
        let body = rows.map { label, value in
            """
            <tr><td style="padding:10px 0;border-top:1px solid \(rule);font-size:15px;color:\(muted);">\(escape(label))</td>
            <td align="right" style="padding:10px 0;border-top:1px solid \(rule);font-size:15px;font-weight:600;color:\(ink);">\(escape(value))</td></tr>
            """
        }.joined(separator: "\n")
        return """
        <tr><td style="padding:28px 28px 0;">
        <div style="font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:\(muted);padding-bottom:8px;">\(escape(title))</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">\(body)</table>
        </td></tr>
        """
    }

    static var footerBlock: String {
        """
        <tr><td style="padding:28px;font-size:12px;line-height:18px;color:\(muted);">
        Sent automatically by NOOP from the wearer's phone. These figures come from a wrist strap and can be delayed or wrong. This is not a medical or emergency alert system.
        </td></tr>
        """
    }
}
