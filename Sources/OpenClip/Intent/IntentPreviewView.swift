import AppKit
import SwiftUI
import Core

@MainActor
public struct IntentPreviewView: View {
    @ObservedObject var model: IntentPreviewModel
    @AppStorage(SettingKey.intentDebugModeEnabled.name) private var debugMode = SettingKey.intentDebugModeEnabled.defaultValue

    public init(model: IntentPreviewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isUncertain ? "IntentOS isn't sure about this." : typeLabel(model.draft.type))
                        .font(.headline)
                    if model.isUncertain {
                        Text("Treat this as a possible intent. Edit it before tracking or explicitly try Cloud AI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: model.dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
            }

            if model.isEditing {
                Picker("Type", selection: binding(\.type)) {
                    Text("ACTION").tag(IntentType.action)
                    Text("REQUEST").tag(IntentType.request)
                    Text("WAITING").tag(IntentType.waiting)
                    Text("REMEMBER").tag(IntentType.remember)
                }
                .pickerStyle(.segmented)
            }

            field(model.draft.type == .remember ? "Summary" : "Next action", text: binding(\.summary))
            if model.draft.type == .remember {
                optionalField("Subject", keyPath: \.subject)
            } else {
                if model.draft.eventAt != nil || (model.draft.unresolvedTimeText != nil && IntentTemporalResolver.containsMeetingWording(model.draft.sourceText)) {
                    // A grounded meeting/event time outranks the waiting-type default below —
                    // "Connect with Cherry" should show "When: Tomorrow, 8:00 AM", not bury that
                    // under "Follow up".
                    IntentWhenControl(value: binding(\.eventAt), kind: .event, unresolvedTimeText: model.draft.unresolvedTimeText)
                } else if model.draft.type == .waiting {
                    IntentWhenControl(value: binding(\.followUpAt), kind: .followUp, unresolvedTimeText: model.draft.unresolvedTimeText)
                } else {
                    IntentWhenControl(value: binding(\.dueAt), kind: .due, unresolvedTimeText: model.draft.unresolvedTimeText)
                }
                if model.draft.type == .waiting || model.draft.type == .request || model.draft.waitingFor != nil {
                    optionalField("Waiting for", keyPath: \.waitingFor)
                }
                if let requestedBy = model.draft.requestedBy, !requestedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labeledRow("Requested by", value: requestedBy)
                }
                if model.isEditing {
                    optionalField("Subject", keyPath: \.subject)
                    optionalField("To", keyPath: \.target)
                }
            }

            if !model.draft.resources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.draft.resources.enumerated()), id: \.offset) { _, resource in
                        Link(destination: URL(string: resource.url) ?? URL(string: "about:blank")!) {
                            Label(resourceButtonTitle(resource), systemImage: "arrow.up.forward.app")
                        }
                        .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Source").font(.caption).foregroundStyle(.secondary)
                Text(model.draft.sourceApplicationName ?? "Unknown app")
                    .font(.caption.bold())
                if model.isEditing {
                    Text(model.draft.sourceText)
                        .font(.caption)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                if debugMode {
                    Text(parserFooter)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ignore", action: model.ignore)
                    .keyboardShortcut(.cancelAction)
                if model.isUncertain {
                    Button("Try Cloud AI", action: model.tryCloud)
                        .disabled(model.isBusy)
                }
                Button(model.isEditing ? "Done Editing" : "Edit") {
                    model.isEditing.toggle()
                    model.markEdited()
                }
                Button("Track", action: model.track)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || model.draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if debugMode, let diagnostics = model.draft.diagnostics {
                DisclosureGroup("Debug") {
                    IntentDebugView(draft: model.draft, diagnostics: diagnostics)
                }
                .font(.caption)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .onExitCommand(perform: model.dismiss)
    }

    private func typeLabel(_ type: IntentType) -> String {
        switch type {
        case .action: return "ACTION"
        case .request: return "REQUEST"
        case .waiting: return "WAITING"
        case .remember: return "REMEMBER"
        }
    }

    private func resourceButtonTitle(_ resource: IntentResource) -> String {
        let name: String
        switch resource.type {
        case .figma: name = "Figma"
        case .github: name = "GitHub"
        case .googleDocs: name = "Google Docs"
        case .googleDrive: name = "Google Drive"
        case .jira: name = "Jira"
        case .notion: name = "Notion"
        case .genericURL: name = "Link"
        }
        return "Open \(resource.label ?? name)"
    }

    private func labeledRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var parserFooter: String {
        let confidence = model.draft.parserConfidence.map { " • \(Int(($0 * 100).rounded()))%" } ?? ""
        let isCloud = model.draft.parser.hasPrefix("cloud.") || model.draft.parser.hasPrefix("\(GeminiIntentParser.parserPrefix).")
        let location = isCloud ? "Cloud" : "Local"
        return "\(location) • \(model.draft.parser)\(confidence)"
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            TextField(placeholder ?? title, text: text)
                .textFieldStyle(.plain)
                .disabled(!model.isEditing)
        }
    }

    /// Placeholder is deliberately "None", never the field's own label ("Waiting for") — an empty
    /// optional field must never look identical to a genuinely leaked placeholder value.
    private func optionalField(_ title: String, keyPath: WritableKeyPath<IntentDraft, String?>) -> some View {
        field(title, text: Binding(
            get: { model.draft[keyPath: keyPath] ?? "" },
            set: { value in
                model.draft[keyPath: keyPath] = value.isEmpty ? nil : value
                model.markEdited()
            }
        ), placeholder: "None")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<IntentDraft, Value>) -> Binding<Value> {
        Binding(
            get: { model.draft[keyPath: keyPath] },
            set: { value in
                model.draft[keyPath: keyPath] = value
                model.markEdited()
            }
        )
    }
}

@MainActor
private struct IntentDebugView: View {
    let draft: IntentDraft
    let diagnostics: IntentParserDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            debugRow("SOURCE TEXT", draft.sourceText)
            debugRow("SOURCE APP", [draft.sourceApplicationName, draft.sourceApplicationBundleIdentifier].compactMap { $0 }.joined(separator: " • "))
            debugRow("PARSER", draft.parser)
            debugRow("MODEL", modelIdentifier)
            debugRow("RAW STRUCTURED OUTPUT", diagnostics.rawResponse ?? "unavailable")
            debugRow("GROUNDING EVIDENCE", diagnostics.rawArguments ?? "none")
            debugRow("FIELDS REMOVED BY VALIDATOR", diagnostics.validationResult ?? "unavailable")
            debugRow("CONFIDENCE", diagnostics.confidence.map { String($0) } ?? "unavailable")
            debugRow("LATENCY", diagnostics.latencyMilliseconds.map { String(format: "%.1f ms", $0) } ?? "unavailable")
            if let peakRAM = diagnostics.peakRAMMegabytes {
                debugRow("PEAK RAM", String(format: "%.1f MB", peakRAM))
            }
            debugRow("NORMALIZED INTENT", normalizedDraft)
            Button("Copy Debug Information") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(debugText, forType: .string)
            }
        }
        .textSelection(.enabled)
    }

    /// Everything after the first "." in `parser` (e.g. "gemini.gemini-3.8-flash" → the model id;
    /// Needle's "needle2-base" has no dot, so it stands for itself).
    private var modelIdentifier: String {
        guard let dotIndex = draft.parser.firstIndex(of: ".") else { return draft.parser }
        return String(draft.parser[draft.parser.index(after: dotIndex)...])
    }

    private func debugRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption2, design: .monospaced))
        }
    }

    private var debugText: String {
        """
        SOURCE TEXT
        \(draft.sourceText)

        SOURCE APP
        \(draft.sourceApplicationName ?? "unknown") (\(draft.sourceApplicationBundleIdentifier ?? "unknown"))

        PARSER
        \(draft.parser)

        MODEL
        \(modelIdentifier)

        RAW STRUCTURED OUTPUT
        \(diagnostics.rawResponse ?? "unavailable")

        GROUNDING EVIDENCE
        \(diagnostics.rawArguments ?? "none")

        FIELDS REMOVED BY VALIDATOR
        \(diagnostics.validationResult ?? "unavailable")

        CONFIDENCE
        \(diagnostics.confidence.map { String($0) } ?? "unavailable")

        LATENCY
        \(diagnostics.latencyMilliseconds.map { String($0) } ?? "unavailable")

        NORMALIZED INTENT
        \(normalizedDraft)
        """
    }

    private var normalizedDraft: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(draft), let value = String(data: data, encoding: .utf8) else {
            return "unavailable"
        }
        return value
    }
}
