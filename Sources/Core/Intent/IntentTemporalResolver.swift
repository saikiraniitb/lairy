// IntentTemporalResolver.swift
// Core
//
// Decides which temporal bucket (dueAt / eventAt / followUpAt) a grounded deadline phrase belongs
// in, and combines a resolved date with a detected time-of-day when both are present. Never
// invents a date to pair with a bare time mention (see `unresolvedTimeText`).
import Foundation

public enum IntentTemporalResolver {
    /// Meeting/session wording that prefers `eventAt` over `dueAt` when a time is present.
    private static let meetingKeywords = ["meet", "meeting", "session", "call", "sync", "catch up", "chat at", "hangout", "connect"]

    private static let clockTimeRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(\d{1,2})(:([0-5]\d))?\s?(am|pm|AM|PM)\b|\b([01]?\d|2[0-3]):([0-5]\d)\b"#,
            options: []
        )
    }()

    /// Message-list timestamp shapes an app prepends/appends to each rendered message — "26 Aug,
    /// 10:27", "Fri 15:51", or WhatsApp's own copy/export prefix "[06/09/26, 11:00:31 PM]
    /// Saikiran: " — that can leak into a multi-message selection's plain text (sender labels and
    /// timestamps sitting inline between message bubbles get concatenated along with the real
    /// content by the underlying AX/text extraction, or WhatsApp's Cmd+C copy itself adds this
    /// prefix to each copied message). These are never a phrase the user wrote, so they're
    /// stripped before scanning for a genuinely mentioned clock time — see `firstClockTimePhrase`.
    /// Deliberately narrow: each alternative only matches a clock time sitting directly beside an
    /// explicit calendar-date token (day + month name, a weekday abbreviation, or a bracketed
    /// numeric date), which is the universal shape of a rendered/exported message timestamp and
    /// not something a real in-message mention like "at 5pm" or "tomorrow at 8am" ever looks like.
    private static let messageTimestampRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*,?\s*\d{1,2}:\d{2}\s?(?:[AaPp][Mm])?|\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\.?,?\s*\d{1,2}:\d{2}\s?(?:[AaPp][Mm])?|\[\d{1,2}/\d{1,2}/\d{2,4},?\s*\d{1,2}:\d{2}(?::\d{2})?\s?(?:[AaPp][Mm])?\]\s*[^:\n]{1,60}:\s*"#,
            options: []
        )
    }()

    public struct Resolution: Equatable {
        public var dueAt: IntentTemporalValue?
        public var eventAt: IntentTemporalValue?
        public var followUpAt: IntentTemporalValue?
        public var unresolvedTimeText: String?
    }

    /// - Parameters:
    ///   - type: the intent's final type — decides which bucket a resolved value lands in.
    ///   - deadlineText: the grounded temporal phrase (already verified to appear in source text).
    ///   - sourceText: the full selection, scanned for a companion clock time / meeting wording.
    ///   - currentDate: resolution anchor for relative phrases ("tomorrow", "Friday").
    public static func resolve(
        type: IntentType,
        deadlineText: String?,
        sourceText: String,
        currentDate: Date,
        calendar: Calendar = .current
    ) -> Resolution {
        guard let deadlineText, !deadlineText.isEmpty else {
            // No resolvable date phrase — but a bare clock time may still exist on its own
            // (e.g. "Can we have a session at 5pm?" with no day mentioned at all).
            if let timeText = firstClockTimePhrase(in: sourceText) {
                return Resolution(unresolvedTimeText: timeText)
            }
            return Resolution()
        }

        let timePhrase = firstClockTimePhrase(in: deadlineText) ?? firstClockTimePhrase(in: sourceText)
        let timeOfDay = timePhrase.flatMap(parseTimeOfDay)
        // `IntentDeadlineResolver` only understands a bare date phrase — strip a companion clock
        // time (and connecting filler like "at") before resolving, so a combined phrase like
        // "Friday at 5pm" still resolves its date half instead of failing outright.
        let datePhrase = strippingClockTime(timePhrase, from: deadlineText)
        let resolvedDate = IntentDeadlineResolver.resolve(datePhrase, relativeTo: currentDate, calendar: calendar)
            ?? IntentDeadlineResolver.resolve(deadlineText, relativeTo: currentDate, calendar: calendar)

        guard let resolvedDate else {
            // The phrase didn't resolve to a real date (e.g. "next week"), so a time mentioned
            // alongside it still cannot be paired with any date — surface it unresolved rather
            // than inventing one.
            if let timePhrase { return Resolution(unresolvedTimeText: timePhrase) }
            return Resolution()
        }

        let finalDate: Date
        let hasTime: Bool
        if let timeOfDay {
            finalDate = calendar.date(
                bySettingHour: timeOfDay.hour, minute: timeOfDay.minute, second: 0, of: resolvedDate
            ) ?? resolvedDate
            hasTime = true
        } else {
            finalDate = resolvedDate
            hasTime = false
        }

        let value = IntentTemporalValue(date: finalDate, hasTime: hasTime, sourceText: deadlineText, provenance: .modelGrounded)

        switch type {
        case .waiting:
            // A grounded meeting/session time on a WAITING intent is a proposed event ("Let's
            // connect tomorrow at 8am" -> When: Tomorrow, 8:00 AM), not a reminder to check back —
            // only a genuine date-only phrase with no clock time and no meeting wording ("Check
            // again Monday") still becomes a follow-up.
            if hasTime, containsMeetingWording(sourceText) {
                return Resolution(eventAt: value)
            }
            return Resolution(followUpAt: value)
        case .action, .request:
            if hasTime, containsMeetingWording(sourceText) {
                return Resolution(eventAt: value)
            }
            return Resolution(dueAt: value)
        case .remember:
            // REMEMBER never gets a reminder by default, even if a date was mentioned in passing.
            return Resolution()
        }
    }

    /// Removes `timePhrase` (and a trailing connector word like "at"/"@") from `text`, leaving
    /// just the date-shaped remainder — "Friday at 5pm" → "Friday".
    private static func strippingClockTime(_ timePhrase: String?, from text: String) -> String {
        guard let timePhrase, let range = text.range(of: timePhrase, options: .caseInsensitive) else { return text }
        var stripped = text
        stripped.removeSubrange(range)
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        for filler in ["at", "@"] where stripped.lowercased().hasSuffix(filler) {
            stripped = String(stripped.dropLast(filler.count)).trimmingCharacters(in: .whitespaces)
        }
        return stripped
    }

    /// Shared with date-entry UI so choosing a date for a bare meeting time creates an
    /// event, not a deadline or follow-up merely because its intent type is WAITING.
    public static func containsMeetingWording(_ text: String) -> Bool {
        let lower = text.lowercased()
        return meetingKeywords.contains { lower.contains($0) }
    }

    private static func firstClockTimePhrase(in text: String) -> String? {
        let sanitized = strippingMessageTimestamps(from: text)
        let nsText = sanitized as NSString
        guard let match = clockTimeRegex.firstMatch(in: sanitized, options: [], range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return nsText.substring(with: match.range)
    }

    private static func strippingMessageTimestamps(from text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return messageTimestampRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Parses "5pm", "5:30pm", "17:00" into 24-hour hour/minute. Returns nil for anything else.
    private static func parseTimeOfDay(_ phrase: String) -> (hour: Int, minute: Int)? {
        let nsPhrase = phrase as NSString
        guard let match = clockTimeRegex.firstMatch(in: phrase, options: [], range: NSRange(location: 0, length: nsPhrase.length)) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound else { return nil }
            return nsPhrase.substring(with: match.range(at: index))
        }

        if let hourString = group(1), let hour24Base = Int(hourString) {
            let minute = group(3).flatMap(Int.init) ?? 0
            let meridiem = group(4)?.lowercased()
            var hour = hour24Base % 12
            if meridiem == "pm" { hour += 12 }
            return (hour, minute)
        }
        if let hourString = group(5), let minuteString = group(6), let hour = Int(hourString), let minute = Int(minuteString) {
            return (hour, minute)
        }
        return nil
    }
}
