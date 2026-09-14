// PermissionManagerTests.swift
// OpenClipTests
//
// Regression coverage for the stale bundle-identifier bug: `tccutil reset` must always target the
// running app's actual bundle identifier, never a hardcoded pre-rename literal. A hardcoded
// "com.openclip.OpenClip" silently reset the wrong bundle's TCC entry after the app's
// PRODUCT_BUNDLE_IDENTIFIER moved to "com.openclip.intentos.experimental", leaving a stuck-disabled
// Accessibility grant for the real running binary untouched.
import XCTest
@testable import OpenClip

@MainActor
final class PermissionManagerTests: XCTestCase {
    func testRunningBundleIdentifierTracksBundleMain() {
        XCTAssertEqual(PermissionManager.runningBundleIdentifier, Bundle.main.bundleIdentifier)
    }

    func testRunningBundleIdentifierIsNotHardcodedToPreRenameLiteral() throws {
        guard let actual = Bundle.main.bundleIdentifier, actual != "com.openclip.OpenClip" else {
            throw XCTSkip("Host bundle happens to match the legacy literal; assertion would be meaningless here.")
        }
        XCTAssertNotEqual(PermissionManager.runningBundleIdentifier, "com.openclip.OpenClip")
    }
}
