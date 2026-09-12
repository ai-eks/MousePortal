import XCTest
@testable import MousePortal

final class SystemWindowLayoutProviderTests: XCTestCase {
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

    func testCaptureWithoutSnapshotIDDoesNotReplaceExistingIdentities() {
        let provider = SystemWindowLayoutProvider(applications: { [] })
        let snapshotID = UUID()
        _ = provider.captureWindows(displays: [], ignoring: [], runtimeSnapshotID: snapshotID)
        _ = provider.captureWindows(displays: [], ignoring: [], runtimeSnapshotID: nil)

        XCTAssertNotNil(provider.retainedWindows(for: snapshotID))
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
