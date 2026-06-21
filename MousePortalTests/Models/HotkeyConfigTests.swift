import XCTest
import CoreGraphics
@testable import MousePortal

final class HotkeyConfigTests: XCTestCase {

    func testHotkeyConfigCreation() {
        let config = HotkeyConfig(
            displayID: 1,
            keyCode: 18, // "1" key
            modifiers: UInt64(CGEventFlags.maskControl.rawValue),
            displayName: "Main Display"
        )

        XCTAssertEqual(config.displayID, 1)
        XCTAssertEqual(config.displayName, "Main Display")
        XCTAssertEqual(config.keyCode, 18)
        XCTAssertTrue(config.isEnabled)
    }

    func testShortcutStringWithControlModifier() {
        let config = HotkeyConfig(
            displayID: 1,
            keyCode: 18, // "1" key
            modifiers: UInt64(CGEventFlags.maskControl.rawValue),
            displayName: "Test"
        )

        XCTAssertTrue(config.shortcutString.contains("⌃"), "Should contain Control symbol")
    }

    func testShortcutStringWithMultipleModifiers() {
        let config = HotkeyConfig(
            displayID: 1,
            keyCode: 18,
            modifiers: UInt64(CGEventFlags.maskControl.rawValue) | UInt64(CGEventFlags.maskAlternate.rawValue),
            displayName: "Test"
        )

        XCTAssertTrue(config.shortcutString.contains("⌃"), "Should contain Control symbol")
        XCTAssertTrue(config.shortcutString.contains("⌥"), "Should contain Option symbol")
    }

    func testHotkeyConfigEquality() {
        let config1 = HotkeyConfig(displayID: 1, keyCode: 18, modifiers: 0, displayName: "Test")
        let config2 = config1

        XCTAssertEqual(config1.id, config2.id, "Copied config should have same id")
    }

    func testHotkeyConfigCodable() throws {
        let original = HotkeyConfig(
            displayID: 1,
            keyCode: 18,
            modifiers: UInt64(CGEventFlags.maskControl.rawValue),
            displayName: "Main"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: encoded)

        XCTAssertEqual(original.displayID, decoded.displayID)
        XCTAssertEqual(original.keyCode, decoded.keyCode)
        XCTAssertEqual(original.modifiers, decoded.modifiers)
    }
}
