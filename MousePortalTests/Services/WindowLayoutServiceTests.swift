import XCTest
import AppKit
@testable import MousePortal

@MainActor
final class WindowLayoutServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let screenNotificationCenter = NotificationCenter()

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
        var window = placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))
        window.runtimeIdentity = runtimeIdentity()
        system.windows = [window]
        let service = makeService(system: system)

        let snapshot = service.saveCurrentLayout()
        let reloadedService = makeService(system: MockWindowLayoutSystemProvider())

        XCTAssertEqual(snapshot?.windows.count, 1)
        XCTAssertEqual(reloadedService.snapshot, snapshot)
        XCTAssertEqual(reloadedService.snapshot?.windows.first?.runtimeIdentity, window.runtimeIdentity)
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

    func testManualSaveInvalidatesPendingRecoveryTimer() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.setAutomaticRestoreEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        system.displays = []
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .waitingForDisplays)
        let recoveryTimer = privateTimer(named: "stabilityTimer", in: service)
        XCTAssertEqual(recoveryTimer?.isValid, true)

        system.displays = [display(identity: "main")]
        _ = service.saveCurrentLayout()

        XCTAssertEqual(service.state, .normal)
        XCTAssertEqual(recoveryTimer?.isValid, false)
    }

    func testExplicitRestoreInvalidatesPendingRecoveryTimer() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.setAutomaticRestoreEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        let snapshotID = service.snapshot!.id
        system.displays = []
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertEqual(service.state, .waitingForDisplays)
        let recoveryTimer = privateTimer(named: "stabilityTimer", in: service)
        XCTAssertEqual(recoveryTimer?.isValid, true)

        system.displays = [display(identity: "main")]
        XCTAssertNotNil(service.restoreSavedLayout(snapshotID: snapshotID))

        XCTAssertEqual(service.state, .normal)
        XCTAssertEqual(recoveryTimer?.isValid, false)
    }

    func testAutomaticSnapshotReplacesPreviousSnapshotForSameDisplayLayout() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
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
        XCTAssertEqual(system.lastRetainedSnapshotIDs, Set(service.snapshots.map(\.id)))
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

    func testManualSnapshotRetainsRuntimeWindowIdentity() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let service = makeService(system: system)

        let snapshot = service.saveCurrentLayout()

        XCTAssertEqual(system.captureRuntimeSnapshotIDs.last!, snapshot?.id)
    }

    func testManualSnapshotDoesNotDiscardAutomaticRuntimeIdentities() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        let automaticID = service.snapshots.first!.id
        let manualID = service.saveCurrentLayout()!.id

        XCTAssertEqual(system.lastRetainedSnapshotIDs, [automaticID, manualID])
    }

    func testMatchingSnapshotsSortAutomaticBeforeManualSnapshots() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
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
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
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
        XCTAssertEqual(system.lastRetainedSnapshotIDs, [second.id])
        XCTAssertEqual(makeService(system: system).snapshots.map(\.id), [second.id])
    }

    func testDeletingAutomaticSnapshotWaitsForNextScreenLockBeforeRecreatingIt() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        var window = placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))
        window.runtimeIdentity = runtimeIdentity()
        system.windows = [window]
        system.visibleWindows = [window]
        let service = makeService(system: system)
        service.setEnabled(true)
        let automaticSnapshotID = service.snapshots.first!.id

        XCTAssertTrue(service.deleteSnapshot(id: automaticSnapshotID))
        system.windows = []
        service.startMonitoring()
        defer { service.stopMonitoring() }

        XCTAssertTrue(service.snapshots.isEmpty)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        XCTAssertTrue(service.snapshots.isEmpty)
        XCTAssertEqual(service.state, .normal)

        screenNotificationCenter.post(
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        XCTAssertEqual(service.snapshots.count, 1)
        XCTAssertEqual(service.snapshots.first?.kind, .automatic)
        XCTAssertEqual(service.snapshots.first?.windows.count, 1)
        XCTAssertNotEqual(service.snapshots.first?.id, automaticSnapshotID)
        XCTAssertEqual(service.state, .snapshotFrozen)
        XCTAssertEqual(system.captureVisibleWindowCallCount, 1)
        let reloadedService = makeService(system: MockWindowLayoutSystemProvider())
        XCTAssertEqual(reloadedService.snapshot?.windows.first?.runtimeIdentity, window.runtimeIdentity)
    }

    func testFailedLockCapturePreservesSavedLayoutAndAllowsNextLockToRetry() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [identifiedWindow(41)]
        let service = makeService(system: system)
        service.setEnabled(true)
        let original = service.snapshot!
        let persisted = defaults.data(forKey: "windowLayoutSnapshots")
        system.windows = []
        service.startMonitoring()
        defer { service.stopMonitoring() }

        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            XCTAssertEqual(service.snapshot, original)
            XCTAssertEqual(service.state, .normal)
        }
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot, original)
        XCTAssertEqual(defaults.data(forKey: "windowLayoutSnapshots"), persisted)
        XCTAssertEqual(system.lastRetainedSnapshotIDs, [original.id])
        XCTAssertEqual(system.captureVisibleWindowCallCount, 1)
        XCTAssertEqual(service.state, .normal)

        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        system.visibleWindows = original.windows
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot?.windows, original.windows)
        XCTAssertNotEqual(service.snapshot?.id, original.id)
        XCTAssertEqual(system.captureVisibleWindowCallCount, 2)
        XCTAssertEqual(service.state, .snapshotFrozen)
    }

    func testStartingWithNoAutomaticLayoutDoesNotCreateOneUntilLock() {
        defaults.set(true, forKey: "windowRecoveryEnabled")
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.visibleWindows = [identifiedWindow(41)]
        let service = makeService(system: system)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        XCTAssertTrue(service.snapshots.isEmpty)
        XCTAssertEqual(system.captureCallCount, 0)
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot?.windows, system.visibleWindows)
        XCTAssertEqual(service.state, .snapshotFrozen)
    }

    func testSuccessfulAXLockCaptureAlsoChecksWindowServerForMissingWindows() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot?.windows, system.windows)
        XCTAssertEqual(system.captureVisibleWindowCallCount, 1)
    }

    func testScreenLockKeepsSuccessfulPreLockSnapshot() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        let frozen = service.snapshot
        system.windows = []

        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot, frozen)
        XCTAssertEqual(service.state, .snapshotFrozen)
        XCTAssertEqual(system.captureVisibleWindowCallCount, 1)
    }

    func testScreenLockMergesPartialAXCaptureByExactIdentity() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let first = identifiedWindow(41)
        let missing = identifiedWindow(42)
        system.windows = [first]
        system.visibleWindows = [first, missing, missing]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }

        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot?.windows, [first, missing])
        XCTAssertEqual(system.captureVisibleWindowCallCount, 1)
        XCTAssertEqual(makeService(system: system).snapshot?.windows, [first, missing])
    }

    func testScreenLockCompletesFrozenPartialSnapshotWithoutReplacingItsAXGeometryOrCache() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let first = identifiedWindow(41)
        let missing = identifiedWindow(42)
        system.windows = [first]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        let frozen = service.snapshot!
        let captureCalls = system.captureCallCount
        system.windows = []
        system.visibleWindows = [identifiedWindow(41, width: 600), missing]

        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot?.windows, [first, missing])
        XCTAssertEqual(service.snapshot?.id, frozen.id)
        XCTAssertEqual(service.snapshot?.capturedAt, frozen.capturedAt)
        XCTAssertEqual(system.captureCallCount, captureCalls)
        XCTAssertEqual(system.lastRetainedSnapshotIDs, [frozen.id])
        XCTAssertEqual(service.state, .snapshotFrozen)
        let completed = service.snapshot
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot, completed)
        system.visibleWindows = []
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot, completed)
        system.visibleCaptureFails = true
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot, completed)
    }

    func testLockSupplementDoesNotGuessDuplicatesWhenAXIdentityIsUnavailable() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [placement(displayIdentity: WindowDisplayIdentity(rawValue: "main"))]
        system.visibleWindows = [identifiedWindow(41), identifiedWindow(42, bundle: "com.example.Other")]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        XCTAssertEqual(service.snapshot?.windows, system.windows + [system.visibleWindows[1]])
    }

    func testFailedLockSupplementDoesNotReplaceOldLayoutWithPartialAXCapture() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [identifiedWindow(41), identifiedWindow(42)]
        let service = makeService(system: system)
        service.setEnabled(true)
        let saved = service.snapshot!
        let persisted = defaults.data(forKey: "windowLayoutSnapshots")
        system.windows = [identifiedWindow(41)]
        system.visibleCaptureFails = true
        service.startMonitoring()
        defer { service.stopMonitoring() }
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot, saved)
        XCTAssertEqual(defaults.data(forKey: "windowLayoutSnapshots"), persisted)
        XCTAssertEqual(system.lastRetainedSnapshotIDs, [saved.id])
        XCTAssertEqual(service.state, .normal)
    }

    func testLockSupplementDoesNotDeduplicateDifferentProcessesWithTheSameWindowNumber() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        let first = identifiedWindow(41)
        var otherProcess = first
        otherProcess.runtimeIdentity = WindowRuntimeIdentity(
            bundleIdentifier: first.bundleIdentifier, processIdentifier: 200,
            processLaunchDate: Date(timeIntervalSince1970: 2000), sessionIdentifier: "boot:login", windowID: 41
        )
        system.windows = [first]
        system.visibleWindows = [otherProcess]
        let service = makeService(system: system)
        service.setEnabled(true)
        service.startMonitoring()
        defer { service.stopMonitoring() }
        screenNotificationCenter.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertEqual(service.snapshot?.windows, [first, otherProcess])
    }

    func testSleepAndManualCaptureDoNotUseLockOnlySupplement() {
        let system = MockWindowLayoutSystemProvider()
        system.displays = [display(identity: "main")]
        system.windows = [identifiedWindow(41)]
        system.visibleWindows = [identifiedWindow(42)]
        let service = makeService(system: system)
        service.setEnabled(true)
        _ = service.saveCurrentLayout()
        service.startMonitoring()
        defer { service.stopMonitoring() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(service.snapshot?.windows, system.windows)
        XCTAssertEqual(system.captureVisibleWindowCallCount, 0)
    }

    private func identifiedWindow(_ id: UInt32, bundle: String = "com.example.Editor", width: Double = 800) -> WindowPlacement {
        WindowPlacement(
            bundleIdentifier: bundle, applicationName: "Editor", windowTitle: "README",
            documentURL: nil, windowIdentifier: nil, role: "AXWindow", subrole: "AXStandardWindow",
            windowIndex: 0, displayIdentity: WindowDisplayIdentity(rawValue: "main"),
            relativeX: 0.1, relativeY: 0.1, width: width, height: 600,
            runtimeIdentity: WindowRuntimeIdentity(
                bundleIdentifier: bundle, processIdentifier: 100,
                processLaunchDate: Date(timeIntervalSince1970: 1000), sessionIdentifier: "boot:login", windowID: id
            )
        )
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

    func testRefreshAvailableApplicationsIncludesUnavailableIgnoredApplications() {
        defaults.set(["com.example.Chat"], forKey: "windowRecoveryIgnoredApplications")
        let system = MockWindowLayoutSystemProvider()
        let service = makeService(system: system)

        service.refreshAvailableApplications()

        XCTAssertEqual(
            service.availableApplications,
            [WindowApplicationOption(bundleIdentifier: "com.example.Chat", name: "com.example.Chat")]
        )
    }

    func testUnignoringUnavailableApplicationRemovesItFromOptions() {
        defaults.set(["com.example.Chat"], forKey: "windowRecoveryIgnoredApplications")
        let system = MockWindowLayoutSystemProvider()
        let service = makeService(system: system)
        service.refreshAvailableApplications()

        service.setApplicationIgnored("com.example.Chat", ignored: false)

        XCTAssertTrue(service.availableApplications.isEmpty)
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
            screenNotificationCenter: screenNotificationCenter,
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

    private func runtimeIdentity() -> WindowRuntimeIdentity {
        WindowRuntimeIdentity(
            bundleIdentifier: "com.example.Editor", processIdentifier: 100,
            processLaunchDate: Date(timeIntervalSince1970: 1_000.123456),
            sessionIdentifier: "boot:login", windowID: 41
        )
    }

    private func privateTimer(named name: String, in service: WindowLayoutService) -> Timer? {
        Mirror(reflecting: service).children
            .first { $0.label == name }?
            .value as? Timer
    }
}

private final class MockWindowLayoutSystemProvider: WindowLayoutSystemProviding {
    var displays: [WindowDisplaySnapshot] = []
    var windows: [WindowPlacement] = []
    var visibleWindows: [WindowPlacement] = []
    var visibleCaptureFails = false
    var applications: [WindowApplicationOption] = []
    var restoreResult = WindowRestoreResult(restoredCount: 0, skippedCount: 0, failedCount: 0)
    private(set) var lastIgnoredBundleIdentifiers: Set<String> = []
    private(set) var restoreCallCount = 0
    private(set) var captureCallCount = 0
    private(set) var captureVisibleWindowCallCount = 0
    private(set) var currentDisplayCallCount = 0
    private(set) var restoredSnapshotID: UUID?
    private(set) var captureRuntimeSnapshotIDs: [UUID] = []
    private(set) var lastRetainedSnapshotIDs: Set<UUID> = []

    func currentDisplays() -> [WindowDisplaySnapshot] {
        currentDisplayCallCount += 1
        return displays
    }

    func captureWindows(
        displays: [WindowDisplaySnapshot],
        ignoring bundleIdentifiers: Set<String>,
        runtimeSnapshotID: UUID
    ) -> [WindowPlacement] {
        captureCallCount += 1
        lastIgnoredBundleIdentifiers = bundleIdentifiers
        captureRuntimeSnapshotIDs.append(runtimeSnapshotID)
        return windows
    }

    func captureVisibleWindows(
        displays: [WindowDisplaySnapshot],
        ignoring bundleIdentifiers: Set<String>
    ) -> [WindowPlacement]? {
        captureVisibleWindowCallCount += 1
        return visibleCaptureFails ? nil : visibleWindows
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

    func discardWindowIdentities(except snapshotIDs: Set<UUID>) {
        lastRetainedSnapshotIDs = snapshotIDs
    }

    func logDisplayState(event: String) {}
}

private struct LegacyWindowLayoutSnapshot: Codable {
    let capturedAt: Date
    let displays: [WindowDisplaySnapshot]
    let windows: [WindowPlacement]
}
