import XCTest
@testable import MousePortal

final class LanguageServiceTests: XCTestCase {
    func testSystemLanguageResolutionUsesSimplifiedChineseVariant() {
        XCTAssertEqual(
            LanguageService.resolvedSystemLanguageCode(forPreferences: ["zh-Hans-CN"]),
            "zh-Hans"
        )
    }

    func testSystemLanguageResolutionUsesTraditionalChineseVariant() {
        XCTAssertEqual(
            LanguageService.resolvedSystemLanguageCode(forPreferences: ["zh-Hant-TW"]),
            "zh-Hant"
        )
    }

    func testSystemLanguageResolutionMapsGenericChineseToSimplifiedChinese() {
        XCTAssertEqual(
            LanguageService.resolvedSystemLanguageCode(forPreferences: ["zh-CN"]),
            "zh-Hans"
        )
    }

    func testSystemLanguageResolutionFallsBackToEnglish() {
        XCTAssertEqual(
            LanguageService.resolvedSystemLanguageCode(forPreferences: ["xx-YY"]),
            "en"
        )
    }
}
