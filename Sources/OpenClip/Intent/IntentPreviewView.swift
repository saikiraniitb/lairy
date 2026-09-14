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
                    Text(model.isUncertain ? "IntentOS isn't sure about this." : model.draft.type.rawValue.uppercased())
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
                    Text("REMEMBER").tag(IntentType.remember)
                    Text("DO").tag(IntentType.doAction)
                    Text("FOLLOW UP").tag(IntentType.followUp)
                }
                .pickerStyle(.segmented)
            }

            field("Summary", text: binding(\.summary))
            if model.draft.type == .remember {
                optionalField("Subject", keyPath: \.subject)
            } else {
                optionalField("Action", keyPath: \.action)
                optionalField("Object", keyPath: \.object)
                optionalField("To", keyPath: \.target)
                optionalField("Deadline", keyPath: \.deadlineText)
                if model.draft.type == .followUp {
                    optionalField("Waiting for", keyPath: \.trigger)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Source").font(.caption).foregroundStyle(.secondary)
                Text(model.draft.sourceText)
                    .font(.caption)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Text(parserFooter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private var parserFooter: String {
        let confidence = model.draft.parserConfidence.map { " • \(Int(($0 * 100).rounded()))%" } ?? ""
        let location = model.draft.parser.hasPrefix("cloud.") ? "Cloud" : "Local"
        return "\(location) • \(model.draft.parser)\(confidence)"
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .disabled(!model.isEditing)
        }
    }

    private func optionalField(_ title: String, keyPath: WritableKeyPath<IntentDraft, String?>) -> some View {
        field(title, text: Binding(
            get: { model.draft[keyPath: keyPath] ?? "" },
            set: { value in
                model.draft[keyPath: keyPath] = value.isEmpty ? nil : value
                model.markEdited()
            }
        ))
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
            debugRow("SOURCE APP", [draft.sourceApplicationName, draft.sourceApplicationBundleIdentifier].compactMap { $0 }.joined(separator: " • "))
            debugRow("PARSER", draft.parser)
            debugRow("TOOL SELECTED", diagnostics.toolSelected ?? "none")
            debugRow("RAW ARGUMENTS", diagnostics.rawArguments ?? "none")
            debugRow("CONFIDENCE", diagnostics.confidence.map { String($0) } ?? "unavailable")
            debugRow("LATENCY", diagnostics.latencyMilliseconds.map { String(format: "%.1f ms", $0) } ?? "unavailable")
            debugRow("PEAK RAM", diagnostics.peakRAMMegabytes.map { String(format: "%.1f MB", $0) } ?? "unavailable")
            debugRow("VALIDATION RESULT", diagnostics.validationResult ?? "unavailable")
            debugRow("NORMALIZED INTENT", normalizedDraft)
            Button("Copy Debug Information") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(debugText, forType: .string)
            }
        }
        .textSelection(.enabled)
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

        NEEDLE RAW RESPONSE
        \(diagnostics.rawResponse ?? "unavailable")

        TOOL SELECTED
        \(diagnostics.toolSelected ?? "none")

        RAW ARGUMENTS
        \(diagnostics.rawArguments ?? "none")

        CONFIDENCE
        \(diagnostics.confidence.map { String($0) } ?? "unavailable")

        LATENCY
        \(diagnostics.latencyMilliseconds.map { String($0) } ?? "unavailable")

        PEAK RAM
        \(diagnostics.peakRAMMegabytes.map { String($0) } ?? "unavailable")

        VALIDATION RESULT
        \(diagnostics.validationResult ?? "unavailable")

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
