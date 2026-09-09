import XCTest
import AppKit
@testable import MousePortal

@MainActor
final class DisplayConfigurationCoordinatorTests: XCTestCase {
    func testSwitchesSavedPortalsWithoutCreatingAView() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
        try assertTarget(f.portals, x: 3845)

        f.changeDisplays(to: f.twoDisplays)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutB.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalB.id])
        try assertTarget(f.portals, x: 1925)

        f.changeDisplays(to: f.threeDisplays)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutA.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
        try assertTarget(f.portals, x: 3845)
        XCTAssertEqual(f.displays.displays.map(\.id), f.threeDisplays.map(\.id))
        XCTAssertFalse(f.portals.isRunning, "Applying configuration must not enable the event tap")
    }

    func testEmptyNewLayoutClearsOldCallbackPortalsAndCanReturn() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.layouts.layouts = [f.layoutA]
        f.coordinator.start()
        f.changeDisplays(to: f.twoDisplays)
        XCTAssertTrue(f.layouts.currentPortals.isEmpty)
        XCTAssertTrue(f.portals.portals.isEmpty)
        XCTAssertNil(f.portals.handleMouseMovedForTap(try mouseEvent()))

        f.changeDisplays(to: f.threeDisplays)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
        try assertTarget(f.portals, x: 3845)
    }

    func testStartupReplacesStaleRuntimePortalsAndPreservesOriginalDataOnce() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        let originalData = try JSONEncoder().encode([f.portalB])
        f.defaults.set(originalData, forKey: "portalPairs")
        f.portals.load()
        f.coordinator.start()

        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
        XCTAssertEqual(f.defaults.data(forKey: "portalPairsBeforeLayoutSync"), originalData)
        f.changeDisplays(to: f.twoDisplays)
        f.changeDisplays(to: f.threeDisplays)
        let reloaded = PortalService(defaults: f.defaults)
        reloaded.applyDisplayConfiguration(portals: [], displays: f.twoDisplays)
        XCTAssertEqual(f.defaults.data(forKey: "portalPairsBeforeLayoutSync"), originalData)
    }

    func testDebounceRereadsLatestDisplaysAndRejectsCancelledCallbacks() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        f.provider.mockDisplays = f.twoDisplays
        f.notifyChange()
        f.notifyChange()
        f.notifyChange()
        XCTAssertEqual(f.output.updates.count, 1, "Three identical notifications must not bypass debounce")
        XCTAssertEqual(f.scheduler.jobs.map(\.delay), [0.5, 0.5, 0.5])

        // Change the provider after scheduling, without delivering another notification.
        f.provider.mockDisplays = f.threeDisplays
        f.scheduler.fire(0)
        f.scheduler.fire(1)
        XCTAssertEqual(f.output.updates.count, 1)
        f.scheduler.fire(2)
        XCTAssertEqual(f.output.updates.count, 2)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutA.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
    }

    func testEmptyQueryPreservesSavedLayoutsUntilAValidNotification() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        let stored = f.defaults.data(forKey: "displayLayouts")
        f.changeDisplays(to: [])
        XCTAssertEqual(f.defaults.data(forKey: "displayLayouts"), stored)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutA.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
        XCTAssertEqual(f.output.updates.count, 1)

        f.changeDisplays(to: f.twoDisplays)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutB.id)
    }

    func testEmptyStartupCanRecoverOnExplicitRefresh() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.provider.mockDisplays = []
        f.coordinator.start()
        XCTAssertTrue(f.output.updates.isEmpty)
        f.provider.mockDisplays = f.threeDisplays
        f.coordinator.refresh()
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
    }

    func testStopAndRestartInvalidateQueuedWorkAndDoNotDuplicateObservers() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        f.coordinator.start()
        f.notifyChange()
        XCTAssertEqual(f.scheduler.jobs.count, 1)
        f.coordinator.stop()
        XCTAssertTrue(f.scheduler.jobs[0].isCancelled)
        f.provider.mockDisplays = f.twoDisplays
        f.scheduler.fire(0)
        f.notifyChange()
        XCTAssertEqual(f.output.updates.count, 1)
        XCTAssertEqual(f.scheduler.jobs.count, 1)

        f.coordinator.start()
        XCTAssertEqual(f.output.updates.count, 2)
        f.scheduler.fire(0)
        XCTAssertEqual(f.output.updates.count, 2, "Old work must remain invalid after restart")
        f.notifyChange()
        XCTAssertEqual(f.scheduler.jobs.count, 2)
        f.scheduler.fire(1)
        XCTAssertEqual(f.output.updates.count, 3)
    }

    func testPendingWorkDoesNotRetainCoordinator() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        f.notifyChange()
        weak var coordinator: DisplayConfigurationCoordinator?
        coordinator = f.coordinator
        f.coordinator = nil
        XCTAssertNil(coordinator)
        XCTAssertTrue(f.scheduler.jobs[0].isCancelled)
        f.scheduler.fire(0)
        XCTAssertEqual(f.output.updates.count, 1)
    }

    func testReadingAnotherSavedLayoutDoesNotActivateItsPortals() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        let preview = f.layouts.layouts.first { $0.id == f.layoutB.id }
        XCTAssertEqual(preview?.portals.map(\.id), [f.portalB.id])
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutA.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalA.id])
    }

    func testSettingsDeleteAndTogglePersistAcrossSwitchAndReload() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        let deleted = f.portalA
        let toggled = f.makePortal(name: "Toggle", destination: f.threeDisplays[2])
        let alsoDeleted = f.makePortal(name: "Delete too", destination: f.threeDisplays[2])
        f.layouts.addPortal(toggled)
        f.layouts.addPortal(alsoDeleted)

        // Same model entry points used by the Settings scene; no PortalService writes.
        f.layouts.togglePortal(id: toggled.id)
        f.layouts.removePortals(ids: [deleted.id, alsoDeleted.id])
        XCTAssertEqual(f.portals.portals.map(\.id), [toggled.id])
        XCTAssertFalse(try XCTUnwrap(f.portals.portals.first).isEnabled)
        f.changeDisplays(to: f.twoDisplays)
        f.changeDisplays(to: f.threeDisplays)
        XCTAssertEqual(f.portals.portals.map(\.id), [toggled.id])
        XCTAssertNil(f.portals.handleMouseMovedForTap(try mouseEvent()))

        let reloaded = DisplayLayoutService(defaults: f.defaults, applyPortals: { _ in })
        XCTAssertEqual(reloaded.currentPortals.map(\.id), [toggled.id])
        XCTAssertFalse(try XCTUnwrap(reloaded.currentPortals.first).isEnabled)
        XCTAssertEqual(PortalService(defaults: f.defaults).portals.map(\.id), [toggled.id])
    }

    func testDeletingLastPortalDoesNotResurrectItOnReturn() {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        f.layouts.removePortal(id: f.portalA.id)
        f.changeDisplays(to: f.twoDisplays)
        f.changeDisplays(to: f.threeDisplays)
        XCTAssertTrue(f.portals.portals.isEmpty)
        XCTAssertTrue(f.layouts.currentPortals.isEmpty)
    }

    func testEditedPortalGeometryReachesCallbackAndSurvivesTransition() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        var edited = f.portalA
        edited.lineB = f.portalB.lineB
        f.layouts.updatePortal(edited)
        try assertTarget(f.portals, x: 1925)
        f.changeDisplays(to: f.twoDisplays)
        f.changeDisplays(to: f.threeDisplays)
        try assertTarget(f.portals, x: 1925)
    }

    func testDisplayIDChangesRefreshLegacyCacheWithCurrentConfiguration() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        var legacy = f.portalA
        legacy.lineA.displayLayoutKey = nil
        legacy.lineA.legacyDisplayID = 10
        legacy.lineB.displayLayoutKey = nil
        legacy.lineB.legacyDisplayID = 30
        let displays = f.threeDisplays.map {
            DisplayInfo(id: $0.id * 10, frame: $0.frame, isMain: $0.isMain, name: $0.name)
        }
        f.portals.applyDisplayConfiguration(portals: [legacy], displays: displays)
        try assertTarget(f.portals, x: 3845)
        f.portals.applyDisplayConfiguration(portals: [legacy], displays: f.threeDisplays)
        XCTAssertNil(f.portals.handleMouseMovedForTap(try mouseEvent()))
    }

    func testCoordinatorPreservesLayoutsWithWindowSnapshots() {
        let f = Fixture()
        defer { f.cleanUp() }
        var saved = f.layoutB
        saved.portals = []
        f.layouts.layouts = [saved]
        f.output.preserved = [saved.signature]
        f.coordinator.start()
        XCTAssertTrue(f.layouts.layouts.contains { $0.id == saved.id })
    }

    func testLegacyLayoutPortalsResolveUsingSavedDisplayIDsAfterReconnect() throws {
        let f = Fixture()
        defer { f.cleanUp() }
        var legacyLayout = f.layoutA
        var legacyPortal = f.portalA
        legacyPortal.lineA.displayLayoutKey = nil
        legacyPortal.lineA.legacyDisplayID = 1
        legacyPortal.lineB.displayLayoutKey = nil
        legacyPortal.lineB.legacyDisplayID = 3
        legacyLayout.portals = [legacyPortal]
        f.layouts.layouts = [legacyLayout]
        f.provider.mockDisplays = f.threeDisplays.map {
            DisplayInfo(id: $0.id * 10, frame: $0.frame, isMain: $0.isMain, name: $0.name)
        }
        f.coordinator.start()

        try assertTarget(f.portals, x: 3845)
        let migrated = try XCTUnwrap(f.layouts.currentPortals.first)
        XCTAssertEqual(migrated.id, legacyPortal.id)
        XCTAssertEqual(migrated.lineA.id, legacyPortal.lineA.id)
        XCTAssertEqual(migrated.lineB.id, legacyPortal.lineB.id)
        XCTAssertEqual(migrated.lineA.displayLayoutKey, f.threeDisplays[0].layoutKey)
        XCTAssertEqual(migrated.lineB.displayLayoutKey, f.threeDisplays[2].layoutKey)
        let reloaded = DisplayLayoutService(defaults: f.defaults, applyPortals: { _ in })
        XCTAssertEqual(reloaded.currentPortals.first?.lineB.displayLayoutKey, migrated.lineB.displayLayoutKey)
    }

    func testProductionSchedulerProcessesDisplayChange() async {
        let f = Fixture(useProductionScheduler: true)
        defer { f.cleanUp() }
        f.installSavedLayouts()
        f.coordinator.start()
        let applied = expectation(description: "Debounced display application")
        f.output.onUpdate = { applied.fulfill() }
        f.provider.mockDisplays = f.twoDisplays
        f.notifyChange()
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(f.layouts.currentLayoutID, f.layoutB.id)
        XCTAssertEqual(f.portals.portals.map(\.id), [f.portalB.id])
    }

    private func mouseEvent() throws -> CGEvent {
        try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: CGPoint(x: 1919, y: 50), mouseButton: .left))
    }

    private func assertTarget(_ portals: PortalService, x: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let target = try XCTUnwrap(portals.handleMouseMovedForTap(mouseEvent()), file: file, line: line)
        XCTAssertEqual(target.x, x, file: file, line: line)
        XCTAssertEqual(target.y, 50, file: file, line: line)
    }
}

@MainActor
private final class ManualDisplayScheduler: DisplayChangeScheduling {
    final class Job {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false
        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }
    }
    var jobs: [Job] = []
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
        let job = Job(delay: delay, action: action)
        jobs.append(job)
        return { job.isCancelled = true }
    }
    /// Deliberately fire cancelled jobs too, modelling already queued callbacks.
    func fire(_ index: Int) { jobs[index].action() }
}

@MainActor
private final class Fixture {
    final class Output {
        var updates: [[DisplayInfo]] = []
        var preserved: Set<String> = []
        var onUpdate: (() -> Void)?
    }
    let suiteName = "DisplayConfigurationTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let provider = MockDisplayProvider()
    let scheduler = ManualDisplayScheduler()
    let center = NotificationCenter()
    let output = Output()
    let displays = DisplayService()
    let portals: PortalService
    let layouts: DisplayLayoutService
    var coordinator: DisplayConfigurationCoordinator!

    let threeDisplays = [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
        DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "Landscape"),
        DisplayInfo(id: 3, frame: CGRect(x: 3840, y: 0, width: 1080, height: 1920), isMain: false, name: "Portrait")
    ]
    var twoDisplays: [DisplayInfo] { Array(threeDisplays.prefix(2)) }
    lazy var portalA = makePortal(name: "Three displays", destination: threeDisplays[2])
    lazy var portalB = makePortal(name: "Two displays", destination: threeDisplays[1])
    lazy var layoutA = makeLayout(name: "A", displays: threeDisplays, portal: portalA)
    lazy var layoutB = makeLayout(name: "B", displays: twoDisplays, portal: portalB)

    init(useProductionScheduler: Bool = false) {
        defaults = UserDefaults(suiteName: suiteName)!
        portals = PortalService(defaults: defaults)
        let portals = self.portals
        layouts = DisplayLayoutService(defaults: defaults, applyPortals: {
            portals.portals = $0
            portals.save()
        })
        let output = self.output
        coordinator = DisplayConfigurationCoordinator(
            provider: provider, layouts: layouts, portals: portals, displayService: displays,
            preservedSignatures: { output.preserved },
            updateHotkeys: { output.updates.append($0); output.onUpdate?() },
            notificationCenter: center, scheduler: useProductionScheduler ? nil : scheduler
        )
        provider.mockDisplays = threeDisplays
    }

    func installSavedLayouts() { layouts.layouts = [layoutA, layoutB] }
    func notifyChange() { center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil) }
    func changeDisplays(to displays: [DisplayInfo]) {
        provider.mockDisplays = displays
        notifyChange()
        scheduler.fire(scheduler.jobs.count - 1)
    }
    func cleanUp() {
        coordinator?.stop()
        coordinator = nil
        defaults.removePersistentDomain(forName: suiteName)
    }
    func makePortal(name: String, destination: DisplayInfo) -> PortalPair {
        PortalPair(name: name,
                   lineA: PortalLine(displayLayoutKey: threeDisplays[0].layoutKey, edge: .right, startOffset: 0, endOffset: 100),
                   lineB: PortalLine(displayLayoutKey: destination.layoutKey, edge: .left, startOffset: 0, endOffset: 100))
    }
    private func makeLayout(name: String, displays: [DisplayInfo], portal: PortalPair) -> DisplayLayout {
        var layout = DisplayLayout(name: name, displays: displays)
        layout.portals = [portal]
        return layout
    }
}
