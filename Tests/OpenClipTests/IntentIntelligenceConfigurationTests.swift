import XCTest
@testable import Core
@testable import OpenClip

/// IntentOS owns the intelligence layer: the user never chooses a provider or model, and the
/// Gemini API key comes only from the process environment (never written to disk). These tests
/// exercise `IntentIntelligenceConfiguration` with an injected environment dictionary rather than
/// mutating the real process environment, so they're deterministic regardless of what's actually
/// exported in the CI/dev shell running the suite.
final class IntentIntelligenceConfigurationTests: XCTestCase {
    func testGeminiAPIKeyPresent() {
        let key = IntentIntelligenceConfiguration.geminiAPIKey(environment: ["GEMINI_API_KEY": "sk-test-123"])
        XCTAssertEqual(key, "sk-test-123")
    }

    func testGeminiAPIKeyMissing() {
        XCTAssertNil(IntentIntelligenceConfiguration.geminiAPIKey(environment: [:]))
    }

    func testGeminiAPIKeyBlankIsTreatedAsMissing() {
        XCTAssertNil(IntentIntelligenceConfiguration.geminiAPIKey(environment: ["GEMINI_API_KEY": "   "]))
    }

    /// The key must never be persisted anywhere — reading it from the environment must not leave
    /// any trace in the same file-backed store other secrets use.
    func testKeyIsNeverWrittenToDisk() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("secrets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        SecretStore.setFileURLForTesting(tempFile)
        SecretStore.resetForTesting(with: [:])
        let contentsBeforeReadingEnv = try Data(contentsOf: tempFile)

        _ = IntentIntelligenceConfiguration.geminiAPIKey(environment: ["GEMINI_API_KEY": "sk-should-not-persist"])

        XCTAssertNil(SecretStore.get(account: "intentGeminiAPIKey"))
        let contentsAfterReadingEnv = try Data(contentsOf: tempFile)
        XCTAssertEqual(contentsBeforeReadingEnv, contentsAfterReadingEnv, "reading GEMINI_API_KEY must never write to the secrets store")
        XCTAssertFalse(String(data: contentsAfterReadingEnv, encoding: .utf8)!.contains("sk-should-not-persist"))
    }

    func testDefaultParserResolvesToGemini() {
        // No override present at all.
        XCTAssertEqual(IntentIntelligenceConfiguration.resolveEngine(environment: [:]), .gemini)
    }

    func testDebugOverrideCanChooseNeedle() {
        let resolved = IntentIntelligenceConfiguration.resolveEngine(environment: ["INTENTOS_INTELLIGENCE_PROVIDER": "needle"])
        #if DEBUG
        XCTAssertEqual(resolved, .needle, "DEBUG builds must honor the engineering override")
        #else
        XCTAssertEqual(resolved, .gemini, "non-DEBUG builds must never honor the override")
        #endif
    }

    func testDebugOverrideIsCaseInsensitive() {
        let resolved = IntentIntelligenceConfiguration.resolveEngine(environment: ["INTENTOS_INTELLIGENCE_PROVIDER": "NEEDLE"])
        #if DEBUG
        XCTAssertEqual(resolved, .needle)
        #else
        XCTAssertEqual(resolved, .gemini)
        #endif
    }

    /// An unrecognized override value must never silently switch away from the production default.
    func testUnrecognizedOverrideFallsBackToGemini() {
        XCTAssertEqual(
            IntentIntelligenceConfiguration.resolveEngine(environment: ["INTENTOS_INTELLIGENCE_PROVIDER": "bogus"]),
            .gemini
        )
    }

    /// The empty-environment production path can never silently become Needle.
    func testProductionPathCannotSilentlySwitchToNeedle() {
        for environment: [String: String] in [[:], ["SOME_OTHER_VAR": "needle"], ["intentos_intelligence_provider": "needle"]] {
            XCTAssertEqual(IntentIntelligenceConfiguration.resolveEngine(environment: environment), .gemini)
        }
    }

    func testDefaultGeminiModelIsCentralizedNotDuplicated() {
        XCTAssertFalse(IntentIntelligenceConfiguration.defaultGeminiModel.isEmpty)
    }
}
