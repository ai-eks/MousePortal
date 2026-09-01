import XCTest
import AppKit
@testable import MousePortal

@MainActor
final class WindowLayoutServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WindowLayoutServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveCurrentLayoutCapturesAndPersistsSnapshot() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)

        let snapshot = service.saveCurrentLayout()
        let reloadedService = makeService(system: system)

        XCTAssertEqual(snapshot?.windows.count, 1)
        XCTAssertEqual(reloadedService.snapshot, snapshot)
    }

    func testManualSavesAppendMultipleSnapshots() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)

        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let first = service.saveCurrentLayout()
        system.windows = []
        let second = service.saveCurrentLayout()
        let reloadedService = makeService(system: system)

        XCTAssertEqual(service.snapshots.map(\.id), [first?.id, second?.id].compactMap { $0 })
        XCTAssertEqual(reloadedService.snapshots, service.snapshots)
        XCTAssertEqual(service.snapshots.map(\.kind), [.manual, .manual])
    }

    func testAutomaticSnapshotReplacesPreviousSnapshotForSameDisplayLayout() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        service.setEnabled(true)
        let firstAutomaticID = service.snapshots.first?.id
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        let automaticSnapshots = service.snapshots.filter { $0.kind == .automatic }
        XCTAssertEqual(automaticSnapshots.count, 1)
        XCTAssertNotEqual(automaticSnapshots.first?.id, firstAutomaticID)
        XCTAssertEqual(system.captureRuntimeSnapshotIDs.last!, automaticSnapshots.first?.id)
    }

    func testRememberBeforeSleepOrLockPersistsIndependentlyFromGlobalSwitch() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)

        XCTAssertTrue(service.rememberBeforeSleepOrLockEnabled)
        service.setEnabled(true)
        service.setRememberBeforeSleepOrLockEnabled(false)

        let reloadedService = makeService(system: system)
        XCTAssertTrue(reloadedService.isEnabled)
        XCTAssertFalse(reloadedService.rememberBeforeSleepOrLockEnabled)
    }

    func testSessionResignDoesNotCaptureWhenRememberBeforeSleepOrLockIsDisabled() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.setRememberBeforeSleepOrLockEnabled(false)
        let captureCallCount = system.captureCallCount
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(service.state, .normal)
        XCTAssertEqual(system.captureCallCount, captureCallCount)
    }

    func testWakeDoesNothingWhenAutomaticRestoreIsDisabled() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        XCTAssertEqual(service.state, .snapshotFrozen)
        let displayCallCount = system.currentDisplayCallCount

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .normal)
        XCTAssertEqual(system.restoreCallCount, 0)
        XCTAssertEqual(system.currentDisplayCallCount, displayCallCount)
    }

    func testManualSnapshotDoesNotRetainRuntimeWindowIdentity() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)

        _ = service.saveCurrentLayout()

        XCTAssertNil(system.captureRuntimeSnapshotIDs.last!)
    }

    func testMatchingSnapshotsSortAutomaticBeforeManualSnapshots() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        service.setEnabled(true)
        _ = service.saveCurrentLayout()
        let signature = service.snapshots[0].displayLayoutSignature

        let matchingSnapshots = service.snapshots(matching: signature)

        XCTAssertEqual(matchingSnapshots.map(\.kind), [.automatic, .manual])
    }

    func testPromoteAutomaticSnapshotMakesItManualAndPersists() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        service.setEnabled(true)
        let snapshotID = service.snapshots.first!.id

        XCTAssertTrue(service.promoteAutomaticSnapshot(id: snapshotID))
        XCTAssertEqual(service.snapshots.first?.kind, .manual)
        XCTAssertEqual(makeService(system: system).snapshots.first?.kind, .manual)
    }

    func testRenameSnapshotTrimsNameAndPersists() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        let snapshot = service.saveCurrentLayout()!

        XCTAssertTrue(service.renameSnapshot(id: snapshot.id, to: "  Work  "))
        XCTAssertEqual(service.snapshots.first?.name, "Work")
        XCTAssertEqual(makeService(system: system).snapshots.first?.name, "Work")
        XCTAssertFalse(service.renameSnapshot(id: snapshot.id, to: "   "))
    }

    func testDeleteSnapshotRemovesItAndPersists() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        let first = service.saveCurrentLayout()!
        let second = service.saveCurrentLayout()!

        XCTAssertTrue(service.deleteSnapshot(id: first.id))
        XCTAssertEqual(service.snapshots.map(\.id), [second.id])
        XCTAssertEqual(makeService(system: system).snapshots.map(\.id), [second.id])
    }

    func testLegacySingleSnapshotMigratesToSnapshotCollection() throws {
        let system = MockWindowLayoutSystemProvider()
        let savedDisplay = display(identity: "main")
        let legacySnapshot = LegacyWindowLayoutSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1234),
            displays: [savedDisplay],
            windows: [placement(displayIdentity: savedDisplay.identity)]
        )
        defaults.set(try JSONEncoder().encode(legacySnapshot), forKey: "windowLayoutSnapshot")

        let service = makeService(system: system)
        let reloadedService = makeService(system: system)

        XCTAssertEqual(service.snapshots.count, 1)
        XCTAssertEqual(service.snapshots.first?.kind, .manual)
        XCTAssertEqual(service.snapshots.first?.capturedAt, legacySnapshot.capturedAt)
        XCTAssertEqual(reloadedService.snapshots, service.snapshots)
    }

    func testSaveCurrentLayoutPassesIgnoredApplicationsToProvider() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)
        service.setApplicationIgnored("com.example.Chat", ignored: true)

        _ = service.saveCurrentLayout()

        XCTAssertEqual(system.lastIgnoredBundleIdentifiers, ["com.example.Chat"])
    }

    func testRestoreUsesCurrentDisplayWithMatchingStableIdentity() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "external")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "external"))]
        system.restoreResult = WindowRestoreResult(restoredCount: 1, skippedCount: 0, failedCount: 0)
        let service = makeService(system: system)
        _ = service.saveCurrentLayout()

        let result = service.restoreSavedLayout()

        XCTAssertEqual(result, system.restoreResult)
        XCTAssertEqual(system.restoreCallCount, 1)
        XCTAssertEqual(service.state, .normal)
    }

    func testRestoreCanTargetSpecificSavedSnapshot() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        let first = service.saveCurrentLayout()
        _ = service.saveCurrentLayout()

        _ = service.restoreSavedLayout(snapshotID: first?.id)

        XCTAssertEqual(system.restoredSnapshotID, first?.id)
    }

    func testRestoreDoesNotRunUntilEverySavedDisplayReturns() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main"), display(identity: "external")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "external"))]
        let service = makeService(system: system)
        _ = service.saveCurrentLayout()
        system.displays = [display(identity: "main")]

        XCTAssertNil(service.restoreSavedLayout())
        XCTAssertEqual(system.restoreCallCount, 0)
    }

    func testSaveAndRestoreRequireAccessibilityTrust() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = WindowLayoutService(
            system: system,
            defaults: defaults,
            accessibilityIsTrusted: { false }
        )

        XCTAssertNil(service.saveCurrentLayout())
        XCTAssertNil(service.restoreSavedLayout())
    }

    func testDisplayOnlySleepAndWakeDoNotEnterRecoveryFlow() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.setAutomaticRestoreEnabled(true)
        let originalSnapshot = service.snapshot
        let captureCallCount = system.captureCallCount
        let displayCallCount = system.currentDisplayCallCount
        system.windows = []
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .normal)
        XCTAssertEqual(service.snapshot, originalSnapshot)
        XCTAssertEqual(system.captureCallCount, captureCallCount)
        XCTAssertEqual(system.currentDisplayCallCount, displayCallCount)
        XCTAssertEqual(system.restoreCallCount, 0)
    }

    func testSessionResignCapturesLatestSnapshotBeforeFreezing() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = []
        let service = makeService(system: system)
        service.setEnabled(true)
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .snapshotFrozen)
        XCTAssertEqual(service.snapshot?.windows.count, 1)
        XCTAssertEqual(system.captureCallCount, 2)
    }

    func testSystemSleepCapturesLatestSnapshotBeforeFreezing() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = []
        let service = makeService(system: system)
        service.setEnabled(true)
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .snapshotFrozen)
        XCTAssertEqual(service.snapshot?.windows.count, 1)
        XCTAssertEqual(system.captureCallCount, 2)
    }

    private func makeService(system: MockWindowLayoutSystemProvider) -> WindowLayoutService {
        WindowLayoutService(
            system: system,
            defaults: defaults,
            accessibilityIsTrusted: { true }
        )
    }

    private func display(identity: String) -> WindowDisplaySnapshot {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return WindowDisplaySnapshot(
            identity: WindowDisplayIdentity(rawValue: identity),
            frame: WindowRect(frame),
            visibleFrame: WindowRect(frame),
            isMain: identity == "main"
        )
    }

    private func placement(displayIdentity: WindowDisplayIdentity) -> WindowPlacement {
        WindowPlacement(
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            windowTitle: "README",
            documentURL: "file:///README.md",
            windowIdentifier: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            windowIndex: 0,
            displayIdentity: displayIdentity,
            relativeX: 0.1,
            relativeY: 0.1,
            width: 800,
            height: 600
        )
    }
}

private final class MockWindowLayoutSystemProvider: WindowLayoutSystemProviding {
    var displays: [WindowDisplaySnapshot] = []
    var windows: [WindowPlacement] = []
    var applications: [WindowApplicationOption] = []
    var restoreResult = WindowRestoreResult(restoredCount: 0, skippedCount: 0, failedCount: 0)
    private(set) var lastIgnoredBundleIdentifiers: Set<String> = []
    private(set) var restoreCallCount = 0
    private(set) var captureCallCount = 0
    private(set) var currentDisplayCallCount = 0
    private(set) var restoredSnapshotID: UUID?
    private(set) var captureRuntimeSnapshotIDs: [UUID?] = []

    func currentDisplays() -> [WindowDisplaySnapshot] {
        currentDisplayCallCount += 1
        return displays
    }

    func captureWindows(
        displays: [WindowDisplaySnapshot],
        ignoring bundleIdentifiers: Set<String>,
        runtimeSnapshotID: UUID?
    ) -> [WindowPlacement] {
        captureCallCount += 1
        lastIgnoredBundleIdentifiers = bundleIdentifiers
        captureRuntimeSnapshotIDs.append(runtimeSnapshotID)
        return windows
    }

    func restoreWindows(
        from snapshot: WindowLayoutSnapshot,
        currentDisplays: [WindowDisplaySnapshot]
    ) -> WindowRestoreResult {
        restoreCallCount += 1
        restoredSnapshotID = snapshot.id
        return restoreResult
    }

    func runningApplications() -> [WindowApplicationOption] {
        applications
    }

    func logDisplayState(event: String) {}
}

private struct LegacyWindowLayoutSnapshot: Codable {
    let capturedAt: Date
    let displays: [WindowDisplaySnapshot]
    let windows: [WindowPlacement]
}
