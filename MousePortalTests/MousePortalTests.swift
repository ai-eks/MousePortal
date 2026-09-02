import XCTest
@testable import MousePortal

final class MousePortalTests: XCTestCase {
    func testAppVersionWindowTitleIsNotEmpty() {
        XCTAssertFalse(AppVersion.windowTitle.isEmpty)
    }

    func testAppVersionIsOneOneZero() {
        XCTAssertEqual(AppVersion.current, "1.1.0")
        XCTAssertEqual(AppVersion.build, "20")
    }
}
