// IntentIntelligenceConfiguration.swift
// OpenClip
//
// IntentOS owns the intelligence layer — the user never chooses a provider or model. This is the
// single internal location for that configuration, so it can change without touching product UI:
//
//   - Which provider is active (production is always Gemini; a DEBUG-only environment variable
//     exists strictly for engineering experiments — see `resolveEngine`).
//   - Which Gemini model is used (`defaultGeminiModel` — change this one constant to move models).
//   - Where the Gemini API key comes from for this prototype stage: the GEMINI_API_KEY
//     environment variable only. Never hardcoded, never written to UserDefaults/plist/Keychain/
//     SecretStore/disk/logs. See docs/intentos/intelligence-deployment.md for why this is a
//     development-only arrangement and what production looks like instead.
import Foundation

public enum IntentIntelligenceConfiguration {
    /// The current stable Flash-class Gemini model IntentOS uses. An internal implementation
    /// choice, never exposed to users. Change this single constant to move to a newer model.
    public static let defaultGeminiModel = "gemini-3.8-flash"

    /// Developer-set environment variable carrying the Gemini API key for this prototype stage.
    public static let geminiAPIKeyEnvironmentVariable = "GEMINI_API_KEY"

    /// DEBUG-only escape hatch for engineering experiments (e.g. `INTENTOS_INTELLIGENCE_PROVIDER=needle`).
    /// Never read in a non-DEBUG build, and never exposed in product UI.
    public static let providerOverrideEnvironmentVariable = "INTENTOS_INTELLIGENCE_PROVIDER"

    /// Reads the Gemini API key directly from the process environment on every call — never
    /// cached, never persisted anywhere. `environment` is injectable for tests; production callers
    /// always use the live process environment.
    public static func geminiAPIKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let value = environment[geminiAPIKeyEnvironmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Which engine powers Intent Intelligence. The production/default answer is always
    /// `.gemini` — only a DEBUG build honors an explicit override, and only for the exact
    /// recognized value, so the default path can never silently switch to Needle.
    public static func resolveEngine(environment: [String: String] = ProcessInfo.processInfo.environment) -> IntentIntelligenceEngine {
        #if DEBUG
        if let raw = environment[providerOverrideEnvironmentVariable],
           let engine = IntentIntelligenceEngine(rawValue: raw.lowercased()) {
            return engine
        }
        #endif
        return .gemini
    }
}

/// Which provider is active. Provider-neutral `IntentParsing` conformers exist for both; selection
/// itself is an internal IntentOS decision (`IntentIntelligenceConfiguration.resolveEngine`), never
/// a user-facing choice.
public enum IntentIntelligenceEngine: String, CaseIterable, Sendable {
    case gemini
    case needle
}
