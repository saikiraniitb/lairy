// CompositeSourceContextResolver.swift
// OpenClip
//
// Dispatches to a narrow, app-specific `SourceContextResolving` conformer by bundle identifier
// when one exists (currently just WhatsApp), falling back to the generic browser-only
// `AccessibilitySourceContextResolver` otherwise. Keeps IntentCaptureCoordinator's composition
// root oblivious to which apps have their own calibration — see AccessibilitySourceContextResolver
// and WhatsAppSourceContextResolver's header comments for why per-app resolvers stay separate
// files instead of broadening one shared heuristic.
import Core

public struct CompositeSourceContextResolver: SourceContextResolving {
    private let whatsApp: WhatsAppSourceContextResolver
    private let generic: AccessibilitySourceContextResolver

    public init(
        whatsApp: WhatsAppSourceContextResolver = WhatsAppSourceContextResolver(),
        generic: AccessibilitySourceContextResolver = AccessibilitySourceContextResolver()
    ) {
        self.whatsApp = whatsApp
        self.generic = generic
    }

    public func resolve(from selection: SelectionContext) async -> IntentSourceContext {
        if selection.sourceApp.bundleIdentifier == WhatsAppSourceContextResolver.bundleIdentifier {
            return await whatsApp.resolve(from: selection)
        }
        if let context = await GoogleChatSourceContextResolver.resolve(selection) { return context }
        return await generic.resolve(from: selection)
    }
}
