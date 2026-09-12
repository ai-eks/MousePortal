import XCTest
import ApplicationServices
@testable import MousePortal

final class WindowIdentityTests: XCTestCase {
    func testReloadedSnapshotFindsOriginalWindowAfterMetadataAndOrderChange() throws {
        let saved = placement(identity: identity(windowID: 41))
        let snapshot = WindowLayoutSnapshot(capturedAt: Date(), displays: [], windows: [saved])
        let reloaded = try JSONDecoder().decode(
            WindowLayoutSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        let candidates = [
            candidate(title: "Saved", index: 0, identity: identity(windowID: 99)),
            candidate(title: "Changed", index: 1, identity: identity(windowID: 41))
        ]

        XCTAssertEqual(reloaded, snapshot)
        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: reloaded.windows, candidates: candidates, preferredIndices: [nil]
        ), [1])
    }

    func testIdenticalDocumentsDoNotOverrideDistinctPersistedWindowIdentities() {
        let placements = [
            placement(index: 0, identity: identity(windowID: 41)),
            placement(index: 1, identity: identity(windowID: 42))
        ]
        let candidates = [
            candidate(title: "Saved", index: 0, identity: identity(windowID: 42)),
            candidate(title: "Saved", index: 1, identity: identity(windowID: 41))
        ]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: placements, candidates: candidates, preferredIndices: [nil, nil]
        ), [1, 0])
    }

    func testWindowIdentityRequiresSameApplicationProcessLaunchSessionAndWindow() {
        let saved = placement(identity: identity())
        let mismatches = [
            identity(bundle: "com.example.Other"),
            identity(pid: 200),
            identity(launch: Date(timeIntervalSince1970: 2_000)),
            identity(session: "different-boot-or-login"),
            identity(windowID: 42)
        ]

        for mismatch in mismatches {
            let current = candidate(title: "Changed", index: 1, identity: mismatch)
            XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
                for: [saved], candidates: [current], preferredIndices: [nil]
            ), [nil])
        }
    }

    func testIdentityMustBelongToSavedApplication() {
        let wrongAppIdentity = identity(bundle: "com.example.Other")
        let saved = placement(identity: wrongAppIdentity)
        let current = candidate(title: "Changed", index: 1, identity: wrongAppIdentity)

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [saved], candidates: [current], preferredIndices: [nil]
        ), [nil])
    }

    func testIdentityMismatchFallsBackToMetadata() {
        let saved = placement(identity: identity(windowID: 41))
        let current = candidate(title: "Saved", index: 1, identity: identity(windowID: 99))

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [saved], candidates: [current], preferredIndices: [nil]
        ), [0])
    }

    func testMissingCurrentIdentityFallsBackToIndex() {
        let saved = placement(identity: identity())
        let current = candidate(title: "Changed", index: 0, identity: nil)

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [saved], candidates: [current], preferredIndices: [nil]
        ), [0])
    }

    func testRetainedObjectTakesPriorityOverPersistedHint() {
        let saved = placement(identity: identity(windowID: 41))
        let candidates = [
            candidate(title: "Saved", index: 0, identity: identity(windowID: 41)),
            candidate(title: "Changed", index: 1, identity: identity(windowID: 99))
        ]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [saved], candidates: candidates, preferredIndices: [1]
        ), [1])
    }

    func testDuplicateCurrentIdentityDoesNotSelectAnArbitraryWindow() {
        let saved = placement(identity: identity())
        let candidates = [
            candidate(title: "Changed", index: 1, identity: identity()),
            candidate(title: "Changed", index: 2, identity: identity())
        ]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [saved], candidates: candidates, preferredIndices: [nil]
        ), [nil])
    }

    func testLegacyPlacementWithoutRuntimeIdentityStillDecodes() throws {
        let saved = placement(identity: nil)
        let data = try JSONEncoder().encode(saved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["runtimeIdentity"])

        let decoded = try JSONDecoder().decode(WindowPlacement.self, from: data)
        XCTAssertEqual(decoded, saved)
        XCTAssertNil(decoded.runtimeIdentity)
    }

    func testPrivateWindowLookupRejectsNonWindowElement() {
        let application = AXUIElementCreateApplication(getpid())
        XCTAssertNil(WindowIdentityResolver.windowID(for: application))
    }

    private func identity(
        bundle: String = "com.example.Editor",
        pid: Int32 = 100,
        launch: Date = Date(timeIntervalSince1970: 1_000.123456),
        session: String = "boot:login",
        windowID: CGWindowID = 41
    ) -> WindowRuntimeIdentity {
        WindowRuntimeIdentity(
            bundleIdentifier: bundle, processIdentifier: pid, processLaunchDate: launch,
            sessionIdentifier: session, windowID: windowID
        )
    }

    private func placement(index: Int = 0, identity: WindowRuntimeIdentity?) -> WindowPlacement {
        WindowPlacement(
            bundleIdentifier: "com.example.Editor", applicationName: "Editor",
            windowTitle: "Saved", documentURL: "file:///same-document", windowIdentifier: nil,
            role: "AXWindow", subrole: "AXStandardWindow", windowIndex: index,
            displayIdentity: WindowDisplayIdentity(rawValue: "main"),
            relativeX: 0, relativeY: 0, width: 800, height: 600, runtimeIdentity: identity
        )
    }

    private func candidate(title: String, index: Int, identity: WindowRuntimeIdentity?) -> WindowMatchCandidate {
        WindowMatchCandidate(
            windowTitle: title, documentURL: title == "Saved" ? "file:///same-document" : nil,
            windowIdentifier: nil, role: "AXWindow", subrole: "AXStandardWindow", windowIndex: index,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600), runtimeIdentity: identity
        )
    }
}
