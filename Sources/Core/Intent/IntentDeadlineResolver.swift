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

        let weekdayNames = calendar.weekdaySymbols.map { $0.lowercased() }
        let shortWeekdayNames = calendar.shortWeekdaySymbols.map { $0.lowercased() }
        let components = phrase.split(separator: " ").map(String.init)
        let isExplicitNext = components.first == "next"
        let weekdayPhrase = isExplicitNext ? components.dropFirst().first : components.first
        if components.count <= 2, let weekdayPhrase,
           let zeroBasedWeekday = weekdayNames.firstIndex(of: weekdayPhrase)
            ?? shortWeekdayNames.firstIndex(of: weekdayPhrase) {
            let wantedWeekday = zeroBasedWeekday + 1
            let currentWeekday = calendar.component(.weekday, from: start)
            var delta = (wantedWeekday - currentWeekday + 7) % 7
            if delta == 0 || isExplicitNext {
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
}
