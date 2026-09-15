// IntentReminderPlanner.swift
// Core
//
// Pure, provider-neutral reminder policy: given a captured intent's temporal values, decide
// whether it gets exactly one notification, and when/what it says. No UserNotifications/platform
// dependency here — see `IntentNotificationScheduling` (OpenClip) for the system adapter that
// actually schedules what this computes. Kept as one small internal configuration so the policy
// can change later without touching call sites (IntentCaptureCoordinator, IntentInboxStore).
import Foundation

public enum IntentReminderPolicy {
    /// Local hour a date-only reminder fires at (no time-of-day was ever mentioned/chosen).
    public static let dateOnlyReminderHour = 9
    public static let dateOnlyReminderMinute = 0
    /// How long before a timed due/event moment its single reminder fires.
    public static let timedReminderLeadMinutes = 30
}

public enum IntentReminderPlanner {
    public struct Plan: Equatable {
        public let fireDate: Date
        public let title: String
        public let body: String
    }

    /// Exactly one reminder per intent in V1 — event takes priority over due, which takes
    /// priority over follow-up, matching "prefer eventAt for scheduled commitments, dueAt for
    /// self-owned actions, followUpAt for waiting" from the temporal model. REMEMBER never gets a
    /// reminder (its resolver never populates any of the three fields in the first place, so this
    /// falls out naturally). Only OPEN/WAITING intents get a plan — DONE/CANCELLED never do.
    public static func plan(for intent: CapturedIntent, calendar: Calendar = .current, now: Date = Date()) -> Plan? {
        guard intent.status == .open || intent.status == .waiting else { return nil }
        guard intent.type != .remember else { return nil }

        if let event = intent.eventAt {
            guard let date = fireDate(for: event, calendar: calendar, now: now) else { return nil }
            return Plan(fireDate: date, title: title, body: eventBody(intent, value: event))
        }
        if let due = intent.dueAt {
            guard let date = fireDate(for: due, calendar: calendar, now: now) else { return nil }
            return Plan(fireDate: date, title: title, body: dueBody(intent, value: due, calendar: calendar))
        }
        if let followUp = intent.followUpAt, followUp.date > now {
            return Plan(fireDate: followUp.date, title: title, body: followUpBody(intent))
        }
        return nil
    }

    private static var title: String { String(localized: "IntentOS") }

    private static func fireDate(for value: IntentTemporalValue, calendar: Calendar, now: Date) -> Date? {
        if value.hasTime {
            guard value.date > now else { return nil }
            let preferred = value.date.addingTimeInterval(-Double(IntentReminderPolicy.timedReminderLeadMinutes) * 60)
            // Inside the lead window, notify in one second (or at the event if closer).
            return preferred > now ? preferred : min(now.addingTimeInterval(1), value.date)
        }
        let date = calendar.date(
            bySettingHour: IntentReminderPolicy.dateOnlyReminderHour,
            minute: IntentReminderPolicy.dateOnlyReminderMinute,
            second: 0,
            of: value.date
        ) ?? value.date
        return date > now ? date : nil
    }

    private static func dueBody(_ intent: CapturedIntent, value: IntentTemporalValue, calendar: Calendar) -> String {
        var lines = [intent.summary]
        let when = calendar.isDateInToday(value.date) ? String(localized: "Due today") : String(localized: "Due soon")
        let meta = [when, intent.sourceApplicationName].compactMap { $0 }.joined(separator: " · ")
        lines.append(meta)
        return lines.joined(separator: "\n")
    }

    private static func eventBody(_ intent: CapturedIntent, value: IntentTemporalValue) -> String {
        guard value.hasTime else { return intent.summary }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(intent.summary) at \(formatter.string(from: value.date))"
    }

    private static func followUpBody(_ intent: CapturedIntent) -> String {
        var lines = [intent.summary]
        lines.append(String(localized: "Follow up?"))
        return lines.joined(separator: "\n")
    }
}
