import Foundation

public enum IntentDeadlineResolver {
    /// Resolves only phrases whose local calendar meaning is stable. The original phrase always
    /// remains in `deadlineText`; broad phrases such as "next week" intentionally return nil.
    public static func resolve(
        _ deadlineText: String?,
        relativeTo now: Date,
        calendar sourceCalendar: Calendar = .current
    ) -> Date? {
        guard let deadlineText else { return nil }
        let phrase = deadlineText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !phrase.isEmpty else { return nil }

        var calendar = sourceCalendar
        calendar.timeZone = sourceCalendar.timeZone
        let start = calendar.startOfDay(for: now)

        if phrase == "today" {
            return start
        }
        if phrase == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }

        let components = phrase.split(separator: " ").map(String.init)
        let isExplicitNext = components.first == "next"
        let weekdayPhrase = isExplicitNext ? components.dropFirst().first : components.first
        if components.count <= 2, let weekdayPhrase,
           let wantedWeekday = englishWeekdays[weekdayPhrase] {
            let currentWeekday = calendar.component(.weekday, from: start)
            var delta = (wantedWeekday - currentWeekday + 7) % 7
            if delta == 0 {
                delta += 7
            }
            return calendar.date(byAdding: .day, value: delta, to: start)
        }

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.calendar = calendar
        iso.timeZone = calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        iso.isLenient = false
        if phrase.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return iso.date(from: phrase)
        }

        return nil
    }

    private static let englishWeekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]
}
