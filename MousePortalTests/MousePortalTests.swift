import XCTest
@testable import MousePortal

final class MousePortalTests: XCTestCase {
    func testAppVersionWindowTitleIsNotEmpty() {
        XCTAssertFalse(AppVersion.windowTitle.isEmpty)
    }
}
