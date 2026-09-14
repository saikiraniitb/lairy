// IntentWhenControl.swift
// OpenClip
//
// The one reusable "When" control — used identically from Capture Preview and Intent Inbox detail
// editing (never two separate date-editing implementations). Expresses the user's choice; it never
// schedules or cancels a notification itself — that's IntentInboxStore/IntentCaptureCoordinator's
// job via IntentNotificationScheduling.
import SwiftUI
import Core

@MainActor
public struct IntentWhenControl: View {
    public enum Kind: Equatable {
        case due
        case event
        case followUp

        var addLabel: LocalizedStringKey {
            switch self {
            case .due: return "+ Add deadline"
            case .event: return "+ Add time"
            case .followUp: return "+ Add follow-up"
            }
        }

        var fieldLabel: LocalizedStringKey {
            switch self {
            case .due, .event: return "When"
            case .followUp: return "Follow up"
            }
        }
    }

    @Binding private var value: IntentTemporalValue?
    /// A clock time was detected but no date could be resolved (e.g. "5pm" with no day
    /// mentioned) — offered as quick-resolve chips rather than silently inventing a date.
    private var unresolvedTimeText: String?
    private let kind: Kind

    @State private var isPresented = false
    @State private var pickerDate: Date = Date()
    @State private var includesTime = false

    public init(value: Binding<IntentTemporalValue?>, kind: Kind, unresolvedTimeText: String? = nil) {
        self._value = value
        self.kind = kind
        self.unresolvedTimeText = unresolvedTimeText
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(kind.fieldLabel).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)

            if let value {
                Button(displayText(for: value)) { present(seeding: value) }
                    .buttonStyle(.plain)
                Button {
                    self.value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
            } else if let unresolvedTimeText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time mentioned: \(unresolvedTimeText)").font(.caption)
                    HStack(spacing: 6) {
                        Button("Today") { resolveUnresolvedTime(dayOffset: 0) }
                        Button("Tomorrow") { resolveUnresolvedTime(dayOffset: 1) }
                        Button("Pick date…") { present(seeding: nil) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button(kind.addLabel) { present(seeding: nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .popover(isPresented: $isPresented) { popoverContent }
    }

    // MARK: - Popover

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(quickOptions, id: \.title) { option in
                Button(option.title) {
                    apply(date: option.date, hasTime: option.hasTime)
                    isPresented = false
                }
                .buttonStyle(.plain)
            }

            Divider()

            DatePicker("Pick Date…", selection: $pickerDate, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.field)

            Toggle("Add Time…", isOn: $includesTime)
            if includesTime {
                DatePicker("Time", selection: $pickerDate, displayedComponents: [.hourAndMinute])
                    .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Done") {
                    apply(date: pickerDate, hasTime: includesTime)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private struct QuickOption { let title: String; let date: Date; let hasTime: Bool }

    private var quickOptions: [QuickOption] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var options: [QuickOption] = [
            QuickOption(title: "Today", date: startOfToday, hasTime: false),
            QuickOption(title: "Tomorrow", date: calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday, hasTime: false)
        ]
        if kind == .event {
            let thisEvening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfToday) ?? startOfToday
            options.append(QuickOption(title: "This evening", date: thisEvening, hasTime: true))
        }
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilFriday = ((6 - weekday) + 7) % 7
        let nextFriday = calendar.date(byAdding: .day, value: daysUntilFriday == 0 ? 7 : daysUntilFriday, to: startOfToday) ?? startOfToday
        options.append(QuickOption(title: "Friday", date: nextFriday, hasTime: false))
        options.append(QuickOption(title: "Next week", date: calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday, hasTime: false))
        return options
    }

    // MARK: - Actions

    private func present(seeding seed: IntentTemporalValue?) {
        pickerDate = seed?.date ?? Date()
        includesTime = seed?.hasTime ?? false
        isPresented = true
    }

    private func apply(date: Date, hasTime: Bool) {
        value = IntentTemporalValue(date: date, hasTime: hasTime, sourceText: nil, provenance: .userSelected)
    }

    private func resolveUnresolvedTime(dayOffset: Int) {
        guard let timeText = unresolvedTimeText else { return }
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
        guard let (hour, minute) = Self.parseTimeOfDay(timeText) else {
            apply(date: day, hasTime: false)
            return
        }
        let combined = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        apply(date: combined, hasTime: true)
    }

    private func displayText(for value: IntentTemporalValue) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = value.hasTime ? .short : .none
        if Calendar.current.isDateInToday(value.date) {
            formatter.dateStyle = .none
            let prefix = String(localized: "Today")
            return value.hasTime ? "\(prefix), \(formatter.string(from: value.date))" : prefix
        }
        if Calendar.current.isDateInTomorrow(value.date) {
            let prefix = String(localized: "Tomorrow")
            return value.hasTime ? "\(prefix), \(formatter.string(from: value.date))" : prefix
        }
        return formatter.string(from: value.date)
    }

    private static func parseTimeOfDay(_ phrase: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(\d{1,2})(:([0-5]\d))?\s?(am|pm)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsPhrase = phrase as NSString
        guard let match = regex.firstMatch(in: phrase, options: [], range: NSRange(location: 0, length: nsPhrase.length)) else { return nil }
        guard let hourBase = Int(nsPhrase.substring(with: match.range(at: 1))) else { return nil }
        let minute = match.range(at: 3).location != NSNotFound ? Int(nsPhrase.substring(with: match.range(at: 3))) ?? 0 : 0
        let meridiem = nsPhrase.substring(with: match.range(at: 4)).lowercased()
        var hour = hourBase % 12
        if meridiem == "pm" { hour += 12 }
        return (hour, minute)
    }
}
