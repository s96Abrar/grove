import XCTest
@testable import Grove

final class NerdFontFallbackTests: XCTestCase {
    private func scalar(_ value: Int) -> Unicode.Scalar { Unicode.Scalar(UInt32(value))! }

    func testBMPPrivateUseAreaIsCandidate() {
        let provider = NerdFontFallback.shared
        // Powerline separators fit and stretch; other icons fit and center.
        XCTAssertEqual(provider.placementPolicy(for: scalar(0xE0B0))?.placement, .stretch)
        XCTAssertEqual(provider.placementPolicy(for: scalar(0xE0DF))?.placement, .stretch)
        XCTAssertEqual(provider.placementPolicy(for: scalar(0xF015))?.placement, .icon)
        XCTAssertEqual(provider.placementPolicy(for: scalar(0xE000))?.placement, .icon)
        XCTAssertEqual(provider.placementPolicy(for: scalar(0xF8FF))?.placement, .icon)
    }

    func testOutsideBMPPrivateUseAreaIsNotCandidate() {
        let provider = NerdFontFallback.shared
        XCTAssertNil(provider.placementPolicy(for: scalar(0xE00)))     // variation selectors
        XCTAssertNil(provider.placementPolicy(for: scalar(0xF900)))
        XCTAssertNil(provider.placementPolicy(for: scalar(0x41)))
        XCTAssertNil(provider.placementPolicy(for: scalar(0x1F600)))
    }

    func testFallbackFontIdentityIsStable() {
        let provider = NerdFontFallback.shared
        guard let font = provider.fallbackFont(forPointSize: 13) else { return } // machine without patched fonts
        XCTAssertTrue(font === provider.fallbackFont(forPointSize: 13))
        XCTAssertFalse(font === provider.fallbackFont(forPointSize: 11))
    }
}
