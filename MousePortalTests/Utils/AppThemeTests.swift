import XCTest
import AppKit
@testable import MousePortal

final class AppThemeTests: XCTestCase {
    func testStoredThemeDefaultsToSystemForMissingOrInvalidValue() {
        let suiteName = "AppThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppTheme.stored(in: defaults), .system)

        defaults.set("unknown", forKey: AppTheme.storageKey)

        XCTAssertEqual(AppTheme.stored(in: defaults), .system)
    }

    func testStoredThemeRestoresSavedValue() {
        let suiteName = "AppThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AppTheme.light.rawValue, forKey: AppTheme.storageKey)

        XCTAssertEqual(AppTheme.stored(in: defaults), .light)
    }

    func testThemeMapsToNativeAppearance() {
        XCTAssertNil(AppTheme.system.appearanceName)
        XCTAssertEqual(AppTheme.light.appearanceName, .aqua)
        XCTAssertEqual(AppTheme.dark.appearanceName, .darkAqua)
    }

    @MainActor
    func testApplyUpdatesApplicationAppearance() {
        let originalAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = originalAppearance }

        AppTheme.light.apply()
        XCTAssertEqual(NSApplication.shared.appearance?.name, .aqua)

        AppTheme.dark.apply()
        XCTAssertEqual(NSApplication.shared.appearance?.name, .darkAqua)

        AppTheme.system.apply()
        XCTAssertNil(NSApplication.shared.appearance)
    }
}
