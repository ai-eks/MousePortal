import XCTest
import AppKit
@testable import MousePortal

final class SystemWindowLayoutProviderTests: XCTestCase {
    func testLockCaptureUsesOriginalBoundsInsteadOfAnimationGeometry() throws {
        let original = CGRect(x: 0, y: 33, width: 1512, height: 884)
        var requestedIDs: [CGWindowID] = []
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41)] },
            windowBounds: { id in requestedIDs.append(id); return original }
        )

        let saved = try XCTUnwrap(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).first)

        XCTAssertEqual(requestedIDs, [41])
        XCTAssertEqual(saved.width, 1512)
        XCTAssertEqual(saved.height, 884)
        XCTAssertEqual(saved.relativeX, 0)
        XCTAssertEqual(saved.relativeY, 33.0 / 982.0, accuracy: 0.000001)
        XCTAssertEqual(saved.bundleIdentifier, "com.example.TestEditor")
    }

    func testOriginalBoundsDetermineDisplayAndNonMaximizedGeometry() throws {
        let external = WindowDisplaySnapshot(
            identity: WindowDisplayIdentity(rawValue: "external"),
            frame: WindowRect(CGRect(x: -1600, y: -900, width: 1600, height: 900)),
            visibleFrame: WindowRect(CGRect(x: -1600, y: -875, width: 1600, height: 875)),
            isMain: false
        )
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41)] },
            windowBounds: { _ in CGRect(x: -1200, y: -700, width: 900, height: 650) }
        )

        let saved = try XCTUnwrap(provider.captureVisibleWindows(displays: [mainDisplay, external], ignoring: []).first)

        XCTAssertEqual(saved.displayIdentity, external.identity)
        XCTAssertEqual(saved.width, 900)
        XCTAssertEqual(saved.height, 650)
        XCTAssertEqual(saved.relativeX, 400.0 / 1600.0, accuracy: 0.000001)
        XCTAssertEqual(saved.relativeY, 200.0 / 900.0, accuracy: 0.000001)
    }

    func testUnavailableOriginalBoundsDoNotFallBackToAnimatedBounds() {
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41)] },
            windowBounds: { _ in nil }
        )

        XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).isEmpty)
    }

    func testOneFailedBoundsReadDiscardsPartialCapture() {
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41), self.windowInfo(id: 42)] },
            windowBounds: { id in id == 41 ? CGRect(x: 0, y: 33, width: 1512, height: 884) : nil }
        )

        XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).isEmpty)
    }

    func testInvalidOriginalBoundsAreRejected() {
        for frame in [CGRect.zero, CGRect.null, CGRect.infinite,
                      CGRect(x: CGFloat.nan, y: 33, width: 800, height: 600),
                      CGRect(x: 0, y: 33, width: -800, height: 600)] {
            let provider = SystemWindowLayoutProvider(
                applications: { [TestWindowApplication()] },
                visibleWindowInfo: { [self.windowInfo(id: 41)] },
                windowBounds: { _ in frame }
            )
            XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).isEmpty)
        }
    }

    func testIgnoredAndInvisibleWindowsDoNotTriggerBoundsReads() {
        var info = windowInfo(id: 41)
        info[kCGWindowAlpha] = NSNumber(value: 0)
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [info] },
            windowBounds: { _ in XCTFail("不可见或忽略的窗口不应读取边框"); return nil }
        )

        XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).isEmpty)
        XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: ["com.example.TestEditor"]).isEmpty)
    }

    func testMenuBarAndFullscreenFilteringUsesOriginalBounds() {
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41), self.windowInfo(id: 42)] },
            windowBounds: { id in CGRect(x: 0, y: 0, width: 1512, height: id == 41 ? 33 : 982) }
        )

        XCTAssertTrue(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).isEmpty)
    }

    func testOriginalBoundsAreRefreshedForEachCapture() throws {
        var frame = CGRect(x: 100, y: 100, width: 900, height: 600)
        let provider = SystemWindowLayoutProvider(
            applications: { [TestWindowApplication()] },
            visibleWindowInfo: { [self.windowInfo(id: 41)] },
            windowBounds: { _ in frame }
        )
        let first = try XCTUnwrap(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).first)
        frame = CGRect(x: 200, y: 150, width: 800, height: 700)
        let second = try XCTUnwrap(provider.captureVisibleWindows(displays: [mainDisplay], ignoring: []).first)

        XCTAssertEqual(first.width, 900)
        XCTAssertEqual(second.width, 800)
        XCTAssertEqual(second.height, 700)
        XCTAssertEqual(second.relativeX, 200.0 / 1512.0, accuracy: 0.000001)
        XCTAssertEqual(second.relativeY, 150.0 / 982.0, accuracy: 0.000001)
    }

    func testPrivateBoundsLookupRejectsNullWindowID() {
        XCTAssertNil(WindowServerGeometry.bounds(for: kCGNullWindowID))
    }

    private var mainDisplay: WindowDisplaySnapshot {
        WindowDisplaySnapshot(
            identity: WindowDisplayIdentity(rawValue: "main"),
            frame: WindowRect(CGRect(x: 0, y: 0, width: 1512, height: 982)),
            visibleFrame: WindowRect(CGRect(x: 0, y: 33, width: 1512, height: 884)),
            isMain: true
        )
    }

    private func windowInfo(id: CGWindowID) -> [CFString: Any] {
        [
            kCGWindowNumber: NSNumber(value: id),
            kCGWindowOwnerPID: NSNumber(value: 123),
            kCGWindowLayer: NSNumber(value: 0),
            kCGWindowAlpha: NSNumber(value: 1),
            kCGWindowBounds: CGRect(x: 75, y: 78, width: 1362, height: 797).dictionaryRepresentation
        ]
    }

    func testCapturingAnotherSnapshotPreservesEarlierRuntimeIdentities() {
        let provider = SystemWindowLayoutProvider(applications: { [] })
        let automaticID = UUID()
        let manualID = UUID()
        let nextManualID = UUID()

        for id in [automaticID, manualID, nextManualID] {
            _ = provider.captureWindows(displays: [], ignoring: [], runtimeSnapshotID: id)
        }

        XCTAssertNotNil(provider.retainedWindows(for: automaticID))
        XCTAssertNotNil(provider.retainedWindows(for: manualID))
        XCTAssertNotNil(provider.retainedWindows(for: nextManualID))
    }

    func testPruningRemovesOnlyDeletedSnapshotIdentities() {
        let provider = SystemWindowLayoutProvider(applications: { [] })
        let firstID = UUID()
        let secondID = UUID()
        _ = provider.captureWindows(displays: [], ignoring: [], runtimeSnapshotID: firstID)
        _ = provider.captureWindows(displays: [], ignoring: [], runtimeSnapshotID: secondID)

        provider.discardWindowIdentities(except: [secondID])
        XCTAssertNil(provider.retainedWindows(for: firstID))
        XCTAssertNotNil(provider.retainedWindows(for: secondID))

        provider.discardWindowIdentities(except: [])
        XCTAssertNil(provider.retainedWindows(for: secondID))
    }
}

private final class TestWindowApplication: NSRunningApplication, @unchecked Sendable {
    override var bundleIdentifier: String? { "com.example.TestEditor" }
    override var processIdentifier: pid_t { 123 }
    override var isTerminated: Bool { false }
    override var activationPolicy: NSApplication.ActivationPolicy { .regular }
    override var localizedName: String? { "Test Editor" }
    override var launchDate: Date? { Date(timeIntervalSince1970: 1000) }
}
