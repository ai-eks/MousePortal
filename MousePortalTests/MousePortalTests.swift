import XCTest
@testable import MousePortal

final class MousePortalTests: XCTestCase {
    func testAppVersionWindowTitleIsNotEmpty() {
        XCTAssertFalse(AppVersion.windowTitle.isEmpty)
    }

    func testAppVersionIsOneOneOne() {
        XCTAssertEqual(AppVersion.current, "1.1.1")
        XCTAssertEqual(AppVersion.build, "21")
    }
}
