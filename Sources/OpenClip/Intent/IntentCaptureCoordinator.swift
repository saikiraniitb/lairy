import Foundation
import Core

@MainActor
public final class IntentCaptureCoordinator: Sendable {
    public static let shared: IntentCaptureCoordinator = {
        let settings = DefaultSettingsStore.shared
        return IntentCaptureCoordinator(
            parser: NeedleIntentParser(confidenceThreshold: settings.get(.intentConfidenceThreshold)),
            cloudParser: CloudIntentParser(),
            repository: FileIntentRepository.shared,
            settingsStore: settings
        )
    }()

    private let parser: any IntentParsing
    private let cloudParser: (any IntentParsing)?
    private let repository: any IntentRepository
    private let settingsStore: any SettingsStore
    private let metrics: IntentMetricsRecorder
    private let previewController: IntentPreviewWindowController

    public init(
        parser: any IntentParsing,
        cloudParser: (any IntentParsing)? = nil,
        repository: any IntentRepository,
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        metrics: IntentMetricsRecorder = .shared,
        previewController: IntentPreviewWindowController = IntentPreviewWindowController()
    ) {
        self.parser = parser
        self.cloudParser = cloudParser
        self.repository = repository
        self.settingsStore = settingsStore
        self.metrics = metrics
        self.previewController = previewController
    }

    public func capture(selection: SelectionContext) async throws -> ActionResult {
        if let needleParser = parser as? NeedleIntentParser {
            await needleParser.setConfidenceThreshold(settingsStore.get(.intentConfidenceThreshold))
        }
        let context = IntentParsingContext(
            sourceApplicationName: selection.sourceApp.localizedName,
            sourceApplicationBundleIdentifier: selection.sourceApp.bundleIdentifier,
            currentDate: Date()
        )
        let result = try await parser.parseIntent(from: selection.text, context: context)

        switch result {
        case .noIntent(let diagnostics):
            await metrics.record(metric(diagnostics: diagnostics, type: nil, outcome: .noIntent))
            return .toast(StatusFeedback(
                message: String(localized: "No actionable intent detected."),
                style: .info
            ))
        case .intent(let draft):
            await metrics.record(metric(draft: draft, outcome: .parsed))
            present(draft: draft, isUncertain: false, context: context, anchor: selection.cursorPosition)
            return .none
        case .uncertain(let possible, let confidence, let diagnostics):
            let draft = possible ?? manualDraft(from: selection, confidence: confidence, diagnostics: diagnostics)
            await metrics.record(metric(draft: draft, outcome: .uncertain))
            present(draft: draft, isUncertain: true, context: context, anchor: selection.cursorPosition)
            return .none
        }
    }

    private func present(
        draft: IntentDraft,
        isUncertain: Bool,
        context: IntentParsingContext,
        anchor: CGPoint
    ) {
        previewController.show(
            draft: draft,
            isUncertain: isUncertain,
            cloudEnabled: settingsStore.get(.intentCloudFallbackEnabled),
            anchor: anchor,
            onTrack: { [weak self] draft, wasEdited in
                guard let self else { return }
                try await self.repository.save(CapturedIntent(draft: draft))
                await self.metrics.record(self.metric(
                    draft: draft,
                    outcome: wasEdited ? .edited : .accepted
                ))
                await IntentInboxStore.shared.reload()
            },
            onIgnore: { [weak self] draft in
                guard let self else { return }
                await self.metrics.record(self.metric(draft: draft, outcome: .ignored))
            },
            onCloud: { [weak self] draft in
                guard let self else { return }
                await self.tryCloud(draft: draft, context: context, anchor: anchor)
            }
        )
    }

    private func tryCloud(draft: IntentDraft, context: IntentParsingContext, anchor: CGPoint) async {
        await metrics.record(metric(draft: draft, outcome: .cloudFallbackRequested))
        guard settingsStore.get(.intentCloudFallbackEnabled) else {
            previewController.showMessage(String(localized: "Cloud fallback is off in developer settings."))
            return
        }
        guard let cloudParser else {
            previewController.showMessage(String(localized: "No cloud intent parser is configured."))
            return
        }

        do {
            let result = try await cloudParser.parseIntent(from: draft.sourceText, context: context)
            switch result {
            case .intent(let replacement):
                present(draft: replacement, isUncertain: false, context: context, anchor: anchor)
            case .uncertain(let replacement, _, _):
                present(draft: replacement ?? draft, isUncertain: true, context: context, anchor: anchor)
            case .noIntent:
                previewController.dismiss()
            }
        } catch {
            previewController.showMessage(error.localizedDescription)
        }
    }

    private func manualDraft(
        from selection: SelectionContext,
        confidence: Double?,
        diagnostics: IntentParserDiagnostics?
    ) -> IntentDraft {
        IntentDraft(
            type: .doAction,
            summary: selection.text.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceText: selection.text,
            sourceApplicationName: selection.sourceApp.localizedName,
            sourceApplicationBundleIdentifier: selection.sourceApp.bundleIdentifier,
            parser: NeedleIntentParser.parserName,
            parserConfidence: confidence,
            diagnostics: diagnostics
        )
    }

    private func metric(
        draft: IntentDraft,
        outcome: IntentMetricEvent.Outcome
    ) -> IntentMetricEvent {
        metric(diagnostics: draft.diagnostics, type: draft.type, outcome: outcome, parser: draft.parser)
    }

    private func metric(
        diagnostics: IntentParserDiagnostics?,
        type: IntentType?,
        outcome: IntentMetricEvent.Outcome,
        parser: String = NeedleIntentParser.parserName
    ) -> IntentMetricEvent {
        IntentMetricEvent(
            parser: parser,
            latencyMilliseconds: diagnostics?.latencyMilliseconds,
            confidence: diagnostics?.confidence,
            intentClass: type,
            outcome: outcome
        )
    }
}
