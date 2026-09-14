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
                    intentSection("OPEN", status: .open)
                    intentSection("DONE", status: .done)
                    intentSection("CANCELLED", status: .cancelled)
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
                        description: Text("Inspect its original selected text and local parser metadata.")
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
    private func intentSection(_ title: String, status: IntentStatus) -> some View {
        let matches = store.intents(with: status)
        if !matches.isEmpty {
            Section(title) {
                ForEach(matches) { intent in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: status == .done ? "checkmark.circle.fill" : status == .cancelled ? "xmark.circle" : "circle")
                                .foregroundStyle(status == .done ? Color.green : Color.secondary)
                            Text(intent.summary).lineLimit(2)
                        }
                        if let context = intent.deadlineText ?? intent.trigger {
                            Text(context)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                        }
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
                metadata(intent)

                Divider()
                detailBlock("ORIGINAL SOURCE", intent.sourceText)
                detailBlock(
                    "SOURCE APPLICATION",
                    [intent.sourceApplicationName, intent.sourceApplicationBundleIdentifier]
                        .compactMap { $0 }.joined(separator: " • ")
                )
                if debugMode {
                    Divider()
                    Text("DEBUG").font(.caption.bold()).foregroundStyle(.secondary)
                    detailBlock("PARSER", intent.parser)
                    detailBlock("CONFIDENCE", intent.parserConfidence.map { String($0) } ?? "unavailable")
                    detailBlock("NEEDLE RAW RESPONSE", intent.diagnostics?.rawResponse ?? "unavailable")
                    detailBlock("TOOL SELECTED", intent.diagnostics?.toolSelected ?? "none")
                    detailBlock("RAW ARGUMENTS", intent.diagnostics?.rawArguments ?? "none")
                    detailBlock("VALIDATION RESULT", intent.diagnostics?.validationResult ?? "unavailable")
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
            metadataRow("Action", intent.action)
            metadataRow("Object", intent.object)
            metadataRow("To", intent.target)
            metadataRow("Deadline", intent.deadlineText)
            metadataRow("Waiting for", intent.trigger)
            metadataRow("Subject", intent.subject)
        }
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

        NEEDLE RAW RESPONSE
        \(intent.diagnostics?.rawResponse ?? "unavailable")

        TOOL SELECTED
        \(intent.diagnostics?.toolSelected ?? "none")

        RAW ARGUMENTS
        \(intent.diagnostics?.rawArguments ?? "none")

        CONFIDENCE
        \(intent.parserConfidence.map { String($0) } ?? "unavailable")

        LATENCY
        \(intent.diagnostics?.latencyMilliseconds.map { String($0) } ?? "unavailable")

        PEAK RAM
        \(intent.diagnostics?.peakRAMMegabytes.map { String($0) } ?? "unavailable")

        VALIDATION RESULT
        \(intent.diagnostics?.validationResult ?? "unavailable")

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
