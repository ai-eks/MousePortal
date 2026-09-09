import XCTest
import CoreGraphics
@testable import MousePortal

final class DisplayLayoutTests: XCTestCase {
    private let storageKey = "displayLayouts"
    private let currentLayoutKey = "currentLayoutID"
    private var originalLayoutsData: Data?
    private var originalCurrentLayoutID: String?

    override func setUp() {
        super.setUp()
        originalLayoutsData = UserDefaults.standard.data(forKey: storageKey)
        originalCurrentLayoutID = UserDefaults.standard.string(forKey: currentLayoutKey)
        resetLayoutServiceState()
    }

    override func tearDown() {
        restoreLayoutServiceState()
        super.tearDown()
    }

    // MARK: - matches() Tests

    func testMatchesExactSameDisplays() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        XCTAssertTrue(layout.matches(displays: displays))
    }

    func testMatchesDifferentDisplayIDs() {
        let originalDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: originalDisplays)

        // 相同布局但不同 ID（重新连接显示器后 ID 可能变化）
        let newDisplays = [
            DisplayInfo(id: 100, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 200, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        XCTAssertTrue(layout.matches(displays: newDisplays), "Should match based on geometry, not display ID")
    }

    func testMatchesFailsDifferentCount() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        let newDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        XCTAssertFalse(layout.matches(displays: newDisplays))
    }

    func testMatchesFailsDifferentResolution() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        let newDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "Main")
        ]

        XCTAssertFalse(layout.matches(displays: newDisplays))
    }

    func testMatchesFailsDifferentPosition() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        // 外接显示器在下方而不是右侧
        let newDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        XCTAssertFalse(layout.matches(displays: newDisplays))
    }

    func testMatchesFailsDifferentMainDisplay() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        // 主显示器和外接显示器标识互换
        let newDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: false, name: "External"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        XCTAssertFalse(layout.matches(displays: newDisplays))
    }

    func testMatchesFailsWhenMultipleDisplaysCouldMatchSameSnapshot() {
        let layoutDisplays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]
        let layout = DisplayLayout(name: "Test", displays: layoutDisplays)

        // 两个显示器几何完全相同，都只能匹配到同一个 snapshot
        let duplicatedDisplays = [
            DisplayInfo(id: 10, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main A"),
            DisplayInfo(id: 11, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main B")
        ]

        XCTAssertFalse(layout.matches(displays: duplicatedDisplays))
    }

    // MARK: - signature Tests

    func testSignatureConsistency() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout1 = DisplayLayout(name: "Test1", displays: displays)
        let layout2 = DisplayLayout(name: "Test2", displays: displays)

        XCTAssertEqual(layout1.signature, layout2.signature)
    }

    func testSignatureDifferentForDifferentLayouts() {
        let displays1 = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]
        let displays2 = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "Main")
        ]

        let layout1 = DisplayLayout(name: "Test1", displays: displays1)
        let layout2 = DisplayLayout(name: "Test2", displays: displays2)

        XCTAssertNotEqual(layout1.signature, layout2.signature)
    }

    // MARK: - snapshotTotalBounds Tests

    func testSnapshotTotalBoundsSingleDisplay() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        XCTAssertEqual(layout.snapshotTotalBounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testSnapshotTotalBoundsDualDisplayHorizontal() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        XCTAssertEqual(layout.snapshotTotalBounds, CGRect(x: 0, y: 0, width: 3840, height: 1080))
    }

    func testSnapshotTotalBoundsWithNegativeOrigin() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let layout = DisplayLayout(name: "Test", displays: displays)

        XCTAssertEqual(layout.snapshotTotalBounds, CGRect(x: -1920, y: 0, width: 3840, height: 1080))
    }

    func testSnapshotDisplaysUsesCustomDisplayName() {
        let snapshot = DisplaySnapshot(
            displayID: 2,
            width: 1920,
            height: 1080,
            x: 1920,
            y: 0,
            isMain: false,
            customName: "Code Screen"
        )

        XCTAssertEqual(snapshot.toDisplayInfo().name, "Code Screen")
    }

    func testDisplaysApplyingCustomNamesPreservesLiveDisplayID() {
        let displays = sampleDualDisplays()
        var layout = DisplayLayout(name: "Test", displays: displays)
        let externalKey = displays[1].layoutKey
        layout.displaySnapshots[1].customName = "Preview Screen"

        let reconnectedDisplays = [
            DisplayInfo(id: 100, frame: displays[0].frame, isMain: true, name: "Main"),
            DisplayInfo(id: 200, frame: displays[1].frame, isMain: false, name: "External")
        ]

        let renamedDisplays = layout.displaysApplyingCustomNames(to: reconnectedDisplays)

        XCTAssertEqual(renamedDisplays.first { $0.layoutKey == externalKey }?.id, 200)
        XCTAssertEqual(renamedDisplays.first { $0.layoutKey == externalKey }?.name, "Preview Screen")
    }

    func testDisplaysApplyingCustomNamesLocalizesDefaultDisplayNames() {
        let displays = sampleDualDisplays()
        let layout = DisplayLayout(name: "Test", displays: displays)
        let staleDisplays = [
            DisplayInfo(id: 100, frame: displays[0].frame, isMain: true, name: "Stale Main"),
            DisplayInfo(id: 200, frame: displays[1].frame, isMain: false, name: "Stale External")
        ]

        let localizedDisplays = layout.displaysApplyingCustomNames(to: staleDisplays)

        XCTAssertEqual(localizedDisplays[0].name, L("display.main"))
        XCTAssertEqual(localizedDisplays[1].name, L("display.external %lld", 1))
    }

    func testSnapshotDisplaysLocalizesDefaultDisplayNamesByOrder() {
        let layout = DisplayLayout(name: "Test", displays: sampleDualDisplays())

        XCTAssertEqual(layout.snapshotDisplays[0].name, L("display.main"))
        XCTAssertEqual(layout.snapshotDisplays[1].name, L("display.external %lld", 1))
    }

    // MARK: - generateSignature Tests

    func testGenerateSignatureForDisplays() {
        let service = DisplayLayoutService.shared
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let signature = service.generateSignature(for: displays)

        XCTAssertEqual(signature, "1920x1080@0,0M|1920x1080@1920,0")
    }

    func testGenerateSignatureOrderIndependent() {
        let service = DisplayLayoutService.shared

        let displays1 = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        let displays2 = [
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External"),
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        XCTAssertEqual(
            service.generateSignature(for: displays1),
            service.generateSignature(for: displays2),
            "Signature should be the same regardless of display order"
        )
    }

    func testGenerateSignatureDifferentForDifferentLayouts() {
        let service = DisplayLayoutService.shared

        let singleDisplay = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]

        let dualDisplay = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]

        XCTAssertNotEqual(
            service.generateSignature(for: singleDisplay),
            service.generateSignature(for: dualDisplay),
            "Different layouts should have different signatures"
        )
    }

    // MARK: - DisplayLayoutService Management Tests

    func testMatchOrCreateLayoutCreatesAndSelectsNewLayout() {
        let service = DisplayLayoutService.shared
        let displays = sampleDualDisplays()

        let layout = service.matchOrCreateLayout(for: displays)

        XCTAssertEqual(service.layouts.count, 1)
        XCTAssertEqual(service.currentLayoutID, layout.id)
        XCTAssertEqual(layout.name, L("layout.dual_display"))
        XCTAssertEqual(layout.displayName, L("layout.dual_display"))
        XCTAssertNil(layout.customName)
        XCTAssertEqual(layout.displaySnapshots.count, displays.count)
    }

    func testMatchOrCreateLayoutReusesExistingLayoutWithoutDuplicating() {
        let service = DisplayLayoutService.shared
        let displays = sampleDualDisplays()
        let existing = DisplayLayout(name: "Existing", displays: displays)
        service.layouts = [existing]
        service.currentLayoutID = nil
        service.save()

        let matched = service.matchOrCreateLayout(for: displays)

        XCTAssertEqual(matched.id, existing.id)
        XCTAssertEqual(service.layouts.count, 1)
        XCTAssertEqual(service.currentLayoutID, existing.id)
    }

    func testMatchReturnsTargetAfterPruningEarlierLayout() {
        let service = DisplayLayoutService.shared
        let unused = DisplayLayout(name: "Unused", displays: sampleSingleDisplay())
        let target = DisplayLayout(name: "Target", displays: sampleDualDisplays())
        service.layouts = [unused, target]
        service.currentLayoutID = unused.id

        let matched = service.matchOrCreateLayout(for: sampleDualDisplays())

        XCTAssertEqual(matched.id, target.id)
        XCTAssertEqual(service.currentLayoutID, target.id)
    }

    func testMatchDoesNotReturnFollowingLayoutAfterPruning() {
        let service = DisplayLayoutService.shared
        let unused = DisplayLayout(name: "Unused", displays: sampleSingleDisplay())
        let target = DisplayLayout(name: "Target", displays: sampleDualDisplays())
        var other = DisplayLayout(name: "Other locked", displays: sampleSingleDisplay())
        other.isLocked = true
        service.layouts = [unused, target, other]
        service.currentLayoutID = unused.id

        let matched = service.matchOrCreateLayout(for: sampleDualDisplays())

        XCTAssertEqual(matched.id, target.id)
        XCTAssertEqual(service.currentLayoutID, target.id)
    }

    func testMatchReturnsTargetAfterPruningMultipleEarlierLayouts() {
        let service = DisplayLayoutService.shared
        let target = DisplayLayout(name: "Target", displays: sampleDualDisplays())
        service.layouts = [
            DisplayLayout(name: "Unused A", displays: sampleSingleDisplay()),
            DisplayLayout(name: "Unused B", displays: sampleSingleDisplay()),
            target
        ]
        service.currentLayoutID = service.layouts[0].id

        XCTAssertEqual(service.matchOrCreateLayout(for: sampleDualDisplays()).id, target.id)
    }

    func testRenameLayoutUpdatesNameAndModifiedDate() {
        let service = DisplayLayoutService.shared
        let layout = DisplayLayout(name: "Before", displays: sampleSingleDisplay())
        service.layouts = [layout]
        service.save()

        let originalModifiedAt = layout.modifiedAt
        usleep(1_000)
        service.renameLayout(layout, to: "After")

        XCTAssertEqual(service.layouts.first?.name, "After")
        XCTAssertEqual(service.layouts.first?.customName, "After")
        XCTAssertEqual(service.layouts.first?.displayName, "After")
        XCTAssertTrue((service.layouts.first?.modifiedAt ?? originalModifiedAt) >= originalModifiedAt)
    }

    func testDeleteCurrentLayoutIsIgnored() {
        let service = DisplayLayoutService.shared
        let layout = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        let other = DisplayLayout(name: "Other", displays: sampleDualDisplays())
        service.layouts = [layout, other]
        service.currentLayoutID = layout.id
        service.save()

        service.deleteLayout(layout)

        XCTAssertEqual(service.layouts.count, 2)
        XCTAssertEqual(service.currentLayoutID, layout.id)
    }

    func testDeleteNonCurrentLayoutKeepsCurrentLayoutID() {
        let service = DisplayLayoutService.shared
        let current = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        let other = DisplayLayout(name: "Other", displays: sampleDualDisplays())
        service.layouts = [current, other]
        service.currentLayoutID = current.id
        service.save()

        service.deleteLayout(other)

        XCTAssertEqual(service.layouts.map(\.id), [current.id])
        XCTAssertEqual(service.currentLayoutID, current.id)
    }

    func testDeleteLayoutPreservesLayoutWithWindowSnapshots() {
        let service = DisplayLayoutService.shared
        let current = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        let withWindowSnapshot = DisplayLayout(name: "Saved Windows", displays: sampleDualDisplays())
        service.layouts = [current, withWindowSnapshot]
        service.currentLayoutID = current.id
        service.save()

        service.deleteLayout(
            withWindowSnapshot,
            preserving: Set([withWindowSnapshot.signature])
        )

        XCTAssertEqual(service.layouts.map(\.id), [current.id, withWindowSnapshot.id])
    }

    func testDeleteLockedLayoutIsIgnored() {
        let service = DisplayLayoutService.shared
        var locked = DisplayLayout(name: "Locked", displays: sampleSingleDisplay())
        locked.isLocked = true
        service.layouts = [locked, DisplayLayout(name: "Other", displays: sampleDualDisplays())]
        service.currentLayoutID = nil
        service.save()

        service.deleteLayout(locked)

        XCTAssertEqual(service.layouts.count, 2)
        XCTAssertTrue(service.layouts.contains(where: { $0.id == locked.id }))
    }

    func testToggleLayoutLockUpdatesStoredLayout() {
        let service = DisplayLayoutService.shared
        let layout = DisplayLayout(name: "Toggle", displays: sampleSingleDisplay())
        service.layouts = [layout]
        service.save()

        service.toggleLayoutLock(layout)

        XCTAssertTrue(service.layouts[0].isLocked)
    }

    func testRenameDisplayUpdatesMatchingSnapshotName() {
        let service = DisplayLayoutService.shared
        let displays = sampleDualDisplays()
        let layout = DisplayLayout(name: "Rename Displays", displays: displays)
        let externalKey = displays[1].layoutKey
        service.layouts = [layout]
        service.currentLayoutID = layout.id
        service.save()

        service.renameDisplay(in: layout.id, displayLayoutKey: externalKey, to: "  Reference  ")

        let renamedSnapshot = service.layouts[0].displaySnapshots.first { $0.layoutKey == externalKey }
        XCTAssertEqual(renamedSnapshot?.customName, "Reference")
        XCTAssertEqual(service.layouts[0].snapshotDisplays.first { $0.layoutKey == externalKey }?.name, "Reference")
    }

    func testRenameDisplayIgnoresBlankName() {
        let service = DisplayLayoutService.shared
        let displays = sampleSingleDisplay()
        let layout = DisplayLayout(name: "Rename Displays", displays: displays)
        service.layouts = [layout]
        service.currentLayoutID = layout.id
        service.save()

        service.renameDisplay(in: layout.id, displayLayoutKey: displays[0].layoutKey, to: "   ")

        XCTAssertNil(service.layouts[0].displaySnapshots[0].customName)
    }

    func testCleanUpUnusedLayoutsRemovesOnlyUnusedLayouts() {
        let service = DisplayLayoutService.shared
        let current = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        let unused = DisplayLayout(name: "Unused", displays: sampleDualDisplays())
        var locked = DisplayLayout(name: "Locked", displays: sampleSingleDisplay())
        var withPortal = DisplayLayout(name: "With Portal", displays: sampleDualDisplays())
        locked.isLocked = true
        withPortal.portals = [samplePortal()]
        service.layouts = [current, unused, locked, withPortal]
        service.currentLayoutID = current.id
        service.save()

        let removedIDs = service.cleanUpUnusedLayouts()

        XCTAssertEqual(Set(removedIDs), Set([unused.id]))
        XCTAssertEqual(service.layouts.map(\.id), [current.id, locked.id, withPortal.id])
        XCTAssertFalse(service.hasUnusedLayouts)
    }

    func testCleanUpUnusedLayoutsReturnsEmptyWhenNothingCanBeRemoved() {
        let service = DisplayLayoutService.shared
        let current = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        service.layouts = [current]
        service.currentLayoutID = current.id
        service.save()

        let removedIDs = service.cleanUpUnusedLayouts()

        XCTAssertEqual(removedIDs, [])
        XCTAssertEqual(service.layouts.map(\.id), [current.id])
    }

    func testCleanUpUnusedLayoutsPreservesLayoutsWithWindowSnapshots() {
        let service = DisplayLayoutService.shared
        let current = DisplayLayout(name: "Current", displays: sampleSingleDisplay())
        let withWindowSnapshot = DisplayLayout(name: "Saved Windows", displays: sampleDualDisplays())
        let unused = DisplayLayout(
            name: "Unused",
            displays: [
                DisplayInfo(
                    id: 3,
                    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                    isMain: true,
                    name: "Other"
                )
            ]
        )
        let preservedSignatures = Set([withWindowSnapshot.signature])
        service.layouts = [current, withWindowSnapshot, unused]
        service.currentLayoutID = current.id
        service.save()

        XCTAssertTrue(service.hasUnusedLayouts(preserving: preservedSignatures))

        let removedIDs = service.cleanUpUnusedLayouts(preserving: preservedSignatures)

        XCTAssertEqual(removedIDs, [unused.id])
        XCTAssertEqual(service.layouts.map(\.id), [current.id, withWindowSnapshot.id])
        XCTAssertFalse(service.hasUnusedLayouts(preserving: preservedSignatures))
    }

    func testMatchOrCreateLayoutPreservesPreviousLayoutWithWindowSnapshots() {
        let service = DisplayLayoutService.shared
        let withWindowSnapshot = DisplayLayout(name: "Saved Windows", displays: sampleDualDisplays())
        service.layouts = [withWindowSnapshot]
        service.currentLayoutID = withWindowSnapshot.id
        service.save()

        let current = service.matchOrCreateLayout(
            for: sampleSingleDisplay(),
            preserving: Set([withWindowSnapshot.signature])
        )

        XCTAssertNotEqual(current.id, withWindowSnapshot.id)
        XCTAssertEqual(service.layouts.map(\.id), [withWindowSnapshot.id, current.id])
    }

    func testDecodeLegacyLayoutWithoutLockStateDefaultsToUnlocked() throws {
        let json = """
        {
          "id": "\(UUID())",
          "name": "Legacy",
          "displaySnapshots": [],
          "portals": [],
          "createdAt": "2026-03-01T00:00:00Z",
          "modifiedAt": "2026-03-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let layout = try decoder.decode(DisplayLayout.self, from: Data(json.utf8))

        XCTAssertFalse(layout.isLocked)
    }

    func testDecodeLegacyDefaultLayoutNameStaysLocalizable() throws {
        let json = """
        {
          "id": "\(UUID())",
          "name": "\(L("layout.single_display"))",
          "displaySnapshots": [
            {
              "id": "\(UUID())",
              "displayID": 1,
              "width": 1512,
              "height": 982,
              "x": 0,
              "y": 0,
              "isMain": true
            }
          ],
          "portals": [],
          "isLocked": false,
          "createdAt": "2026-03-01T00:00:00Z",
          "modifiedAt": "2026-03-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let layout = try decoder.decode(DisplayLayout.self, from: Data(json.utf8))

        XCTAssertNil(layout.customName)
        XCTAssertEqual(layout.displayName, L("layout.single_display"))
    }

    func testDecodeLegacyCustomLayoutNamePreservesUserName() throws {
        let json = """
        {
          "id": "\(UUID())",
          "name": "Desk Setup",
          "displaySnapshots": [
            {
              "id": "\(UUID())",
              "displayID": 1,
              "width": 1512,
              "height": 982,
              "x": 0,
              "y": 0,
              "isMain": true
            }
          ],
          "portals": [],
          "isLocked": false,
          "createdAt": "2026-03-01T00:00:00Z",
          "modifiedAt": "2026-03-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let layout = try decoder.decode(DisplayLayout.self, from: Data(json.utf8))

        XCTAssertEqual(layout.customName, "Desk Setup")
        XCTAssertEqual(layout.displayName, "Desk Setup")
    }

    private func sampleSingleDisplay() -> [DisplayInfo] {
        [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main")
        ]
    }

    private func sampleDualDisplays() -> [DisplayInfo] {
        [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "External")
        ]
    }

    private func samplePortal() -> PortalPair {
        let keyA = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
        let keyB = DisplayLayoutKey(x: 1920, y: 0, width: 1920, height: 1080)
        return PortalPair(
            name: "Portal",
            lineA: PortalLine(displayLayoutKey: keyA, edge: .right, startOffset: 0, endOffset: 1080),
            lineB: PortalLine(displayLayoutKey: keyB, edge: .left, startOffset: 0, endOffset: 1080)
        )
    }

    private func resetLayoutServiceState() {
        let service = DisplayLayoutService.shared
        service.layouts = []
        service.currentLayoutID = nil
        service.save()
    }

    private func restoreLayoutServiceState() {
        if let originalLayoutsData {
            UserDefaults.standard.set(originalLayoutsData, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }

        if let originalCurrentLayoutID {
            UserDefaults.standard.set(originalCurrentLayoutID, forKey: currentLayoutKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentLayoutKey)
        }

        DisplayLayoutService.shared.load()
    }
}
