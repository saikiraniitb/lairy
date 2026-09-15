import AppKit
import SwiftUI
import Core

@MainActor
public struct IntentInboxView: View {
    @ObservedObject private var store: IntentInboxStore
    @AppStorage(SettingKey.intentDebugModeEnabled.name) private var debugMode = SettingKey.intentDebugModeEnabled.defaultValue

    public init(store: IntentInboxStore = .shared) {
        self.store = store
    }

    public var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Intent Inbox").font(.title2.bold())
                    Spacer()
                    Button(action: { Task { await store.reload() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload")
                }
                .padding()

                List(selection: $store.selectedID) {
                    ForEach(IntentInboxGroup.allCases, id: \.self) { group in
                        intentSection(group)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 300, idealWidth: 340)

            Group {
                if let intent = store.selectedIntent {
                    detail(intent)
                } else {
                    ContentUnavailableView(
                        "Select an intent",
                        systemImage: "scope",
                        description: Text("Inspect its original selected text and metadata.")
                    )
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { await store.reload() }
        .overlay(alignment: .bottom) {
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.15), in: Capsule())
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func intentSection(_ group: IntentInboxGroup) -> some View {
        let matches = store.intents(in: group)
        if !matches.isEmpty {
            Section(group.title) {
                ForEach(matches) { intent in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: rowSymbol(for: intent, group: group))
                                .foregroundStyle(intent.status == .done ? Color.green : Color.secondary)
                            Text(intent.summary).lineLimit(2)
                        }
                        if group == .remember {
                            EmptyView()
                        } else if let context = rowTemporalLabel(for: intent) ?? intent.waitingFor.map({ "Waiting for \($0)" }) ?? intent.trigger {
                            Text(context)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                        }
                        Text(intent.sourceApplicationName ?? "Unknown app")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 22)
                    }
                    .tag(intent.id)
                    .contextMenu {
                        statusMenu(intent)
                        Divider()
                        Button("Delete", role: .destructive) { store.delete(intent.id) }
                    }
                }
            }
        }
    }

    /// Human-readable temporal metadata for a row, never an internal date representation.
    private func rowTemporalLabel(for intent: CapturedIntent) -> String? {
        if let followUp = intent.followUpAt {
            return "Follow up \(dayLabel(followUp.date))"
        }
        if let event = intent.eventAt {
            return event.hasTime ? "\(dayLabel(event.date)), \(timeLabel(event.date))" : dayLabel(event.date)
        }
        if let due = intent.dueAt {
            return due.hasTime ? "\(dayLabel(due.date)), \(timeLabel(due.date))" : dayLabel(due.date)
        }
        return nil
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        let formatter = DateFormatter()
        formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) ? "EEEE" : "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func rowSymbol(for intent: CapturedIntent, group: IntentInboxGroup) -> String {
        switch group {
        case .done: return "checkmark.circle.fill"
        case .remember: return "bookmark"
        case .waiting: return "clock"
        default: return "circle"
        }
    }

    private func detail(_ intent: CapturedIntent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(intent.type.rawValue.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu(intent.status.rawValue.capitalized) { statusMenu(intent) }
                }
                Text(intent.summary).font(.title2.bold()).textSelection(.enabled)

                if intent.eventAt != nil || (intent.unresolvedTimeText != nil && IntentTemporalResolver.containsMeetingWording(intent.sourceText)) {
                    // A grounded meeting/event time outranks the waiting-type default below — see
                    // the matching branch order in IntentPreviewView (Preview == saved semantics).
                    IntentWhenControl(value: temporalBinding(for: intent, keyPath: \.eventAt), kind: .event, unresolvedTimeText: intent.unresolvedTimeText)
                } else if intent.type == .waiting {
                    IntentWhenControl(value: temporalBinding(for: intent, keyPath: \.followUpAt), kind: .followUp, unresolvedTimeText: intent.unresolvedTimeText)
                } else if intent.type != .remember {
                    IntentWhenControl(value: temporalBinding(for: intent, keyPath: \.dueAt), kind: .due, unresolvedTimeText: intent.unresolvedTimeText)
                }

                metadata(intent)

                if !intent.resources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(intent.resources, id: \.url) { resource in
                            Link(resource.label ?? resource.url, destination: URL(string: resource.url) ?? URL(string: "about:blank")!)
                                .font(.callout)
                        }
                    }
                }

                Divider()
                detailBlock("ORIGINAL SOURCE", intent.sourceText)
                detailBlock("SOURCE APPLICATION", intent.sourceApplicationName ?? "Unknown app")
                if debugMode {
                    Divider()
                    Text("DEBUG").font(.caption.bold()).foregroundStyle(.secondary)
                    detailBlock("SOURCE BUNDLE IDENTIFIER", intent.sourceApplicationBundleIdentifier ?? "unknown")
                    detailBlock("PARSER", intent.parser)
                    detailBlock("CONFIDENCE", intent.parserConfidence.map { String($0) } ?? "unavailable")
                    detailBlock("RAW STRUCTURED OUTPUT", intent.diagnostics?.rawResponse ?? "unavailable")
                    detailBlock("GROUNDING EVIDENCE", intent.diagnostics?.rawArguments ?? "none")
                    detailBlock("FIELDS REMOVED BY VALIDATOR", intent.diagnostics?.validationResult ?? "unavailable")
                    Button("Copy Debug Information") { copyDebug(intent) }
                }
                HStack {
                    Button("Delete", role: .destructive) { store.delete(intent.id) }
                    Spacer()
                    if intent.status != .cancelled {
                        Button("Cancel") { store.setStatus(.cancelled, for: intent.id) }
                    }
                    if intent.status == .done {
                        Button("Reopen") { store.setStatus(.open, for: intent.id) }
                    } else {
                        Button("Mark Done") { store.setStatus(.done, for: intent.id) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func metadata(_ intent: CapturedIntent) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            metadataRow("Requested by", intent.requestedBy)
            metadataRow("To", intent.target)
            metadataRow("Waiting for", intent.waitingFor)
            metadataRow("Trigger", intent.trigger)
            metadataRow("Requested outcome", intent.requestedOutcome)
            metadataRow("Subject", intent.subject)
        }
    }

    private func temporalBinding(
        for intent: CapturedIntent,
        keyPath: WritableKeyPath<CapturedIntent, IntentTemporalValue?>
    ) -> Binding<IntentTemporalValue?> {
        Binding(
            get: { intent[keyPath: keyPath] },
            set: { newValue in
                var updated = intent
                updated[keyPath: keyPath] = newValue
                store.update(updated)
            }
        )
    }

    @ViewBuilder
    private func metadataRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(title).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func detailBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func statusMenu(_ intent: CapturedIntent) -> some View {
        if intent.status != .open { Button("Reopen") { store.setStatus(.open, for: intent.id) } }
        if intent.status != .waiting { Button("Mark Waiting") { store.setStatus(.waiting, for: intent.id) } }
        if intent.status != .done { Button("Mark Done") { store.setStatus(.done, for: intent.id) } }
        if intent.status != .cancelled { Button("Cancel") { store.setStatus(.cancelled, for: intent.id) } }
    }

    private func copyDebug(_ intent: CapturedIntent) {
        let text = """
        SOURCE TEXT
        \(intent.sourceText)

        SOURCE APP
        \(intent.sourceApplicationName ?? "unknown") (\(intent.sourceApplicationBundleIdentifier ?? "unknown"))

        PARSER
        \(intent.parser)

        RAW STRUCTURED OUTPUT
        \(intent.diagnostics?.rawResponse ?? "unavailable")

        GROUNDING EVIDENCE
        \(intent.diagnostics?.rawArguments ?? "none")

        FIELDS REMOVED BY VALIDATOR
        \(intent.diagnostics?.validationResult ?? "unavailable")

        CONFIDENCE
        \(intent.parserConfidence.map { String($0) } ?? "unavailable")

        LATENCY
        \(intent.diagnostics?.latencyMilliseconds.map { String($0) } ?? "unavailable")

        FINAL SAVED INTENT
        \(encoded(intent))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func encoded(_ intent: CapturedIntent) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(intent), let value = String(data: data, encoding: .utf8) else {
            return "unavailable"
        }
        return value
    }
}
