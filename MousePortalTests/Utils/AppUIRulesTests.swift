import XCTest
@testable import MousePortal

final class AppUIRulesTests: XCTestCase {
    func testCanDeleteLayoutReturnsFalseForCurrentLayout() {
        let currentID = UUID()

        let canDelete = LayoutSidebarRules.canDeleteLayout(
            layoutCount: 3,
            currentLayoutID: currentID,
            targetLayoutID: currentID,
            isLocked: false
        )

        XCTAssertFalse(canDelete)
    }

    func testCanDeleteLayoutReturnsFalseWhenOnlyOneLayoutExists() {
        let canDelete = LayoutSidebarRules.canDeleteLayout(
            layoutCount: 1,
            currentLayoutID: UUID(),
            targetLayoutID: UUID(),
            isLocked: false
        )

        XCTAssertFalse(canDelete)
    }

    func testDeletionActionRequiresConfirmationWhenLayoutHasPortals() {
        let action = LayoutSidebarRules.deletionAction(
            layoutCount: 2,
            currentLayoutID: UUID(),
            targetLayoutID: UUID(),
            portalCount: 2,
            isLocked: false
        )

        XCTAssertEqual(action, .requireConfirmation)
    }

    func testDeletionActionDeletesImmediatelyWhenLayoutHasNoPortals() {
        let action = LayoutSidebarRules.deletionAction(
            layoutCount: 2,
            currentLayoutID: UUID(),
            targetLayoutID: UUID(),
            portalCount: 0,
            isLocked: false
        )

        XCTAssertEqual(action, .deleteImmediately)
    }

    func testCanDeleteLayoutReturnsFalseForLockedLayout() {
        let canDelete = LayoutSidebarRules.canDeleteLayout(
            layoutCount: 2,
            currentLayoutID: UUID(),
            targetLayoutID: UUID(),
            isLocked: true
        )

        XCTAssertFalse(canDelete)
    }

    func testDeleteDisabledHelpTextPrefersLockedReason() {
        let targetID = UUID()

        XCTAssertEqual(
            LayoutSidebarRules.deleteDisabledHelpText(
                layoutCount: 2,
                currentLayoutID: UUID(),
                targetLayoutID: targetID,
                isLocked: true
            ),
            L("layout.delete_disabled_locked")
        )
    }

    func testNextSelectedLayoutReturnsFallbackWhenDeletingCurrentSelection() {
        let first = UUID()
        let second = UUID()

        let nextSelection = LayoutSidebarRules.nextSelectedLayoutID(
            afterDeleting: first,
            currentSelectionID: first,
            orderedLayoutIDs: [first, second]
        )

        XCTAssertEqual(nextSelection, second)
    }

    func testNextSelectedLayoutPreservesSelectionWhenDeletingDifferentLayout() {
        let selected = UUID()
        let deleted = UUID()

        let nextSelection = LayoutSidebarRules.nextSelectedLayoutID(
            afterDeleting: deleted,
            currentSelectionID: selected,
            orderedLayoutIDs: [selected, deleted]
        )

        XCTAssertEqual(nextSelection, selected)
    }

    func testDeleteConfirmationMessageUsesSingularCopy() {
        XCTAssertEqual(
            LayoutSidebarRules.deleteConfirmationMessage(portalCount: 1),
            L("layout.delete_confirm_message_one")
        )
    }

    func testDeleteConfirmationMessageUsesPluralCopy() {
        XCTAssertEqual(
            LayoutSidebarRules.deleteConfirmationMessage(portalCount: 3),
            L("layout.delete_confirm_message_many %lld", 3)
        )
    }

    func testAccessibilityPermissionStatusKeyBranchesCorrectly() {
        XCTAssertEqual(
            AccessibilityPermissionPresentation.statusLocalizationKey(isGranted: true),
            "settings.permission_granted"
        )
        XCTAssertEqual(
            AccessibilityPermissionPresentation.statusLocalizationKey(isGranted: false),
            "settings.permission_not_granted"
        )
    }

    func testAccessibilityPermissionMenuTitleUsesStatusText() {
        XCTAssertEqual(
            AccessibilityPermissionPresentation.menuStatusTitle(isGranted: true),
            L("menu.accessibility_status %@", L("settings.permission_granted"))
        )
        XCTAssertEqual(
            AccessibilityPermissionPresentation.menuStatusTitle(isGranted: false),
            L("menu.accessibility_status %@", L("settings.permission_not_granted"))
        )
    }

    func testWindowApplicationSearchMatchesNameAndBundleIdentifier() {
        let applications = [
            WindowApplicationOption(bundleIdentifier: "com.example.Editor", name: "Code Editor"),
            WindowApplicationOption(bundleIdentifier: "com.example.Chat", name: "Messenger")
        ]

        XCTAssertEqual(
            WindowApplicationSearch.filtered(applications, query: "EDITOR"),
            [applications[0]]
        )
        XCTAssertEqual(
            WindowApplicationSearch.filtered(applications, query: "example.chat"),
            [applications[1]]
        )
    }

    func testWindowApplicationSearchTreatsWhitespaceAsEmpty() {
        let applications = [
            WindowApplicationOption(bundleIdentifier: "com.example.Editor", name: "Editor")
        ]

        XCTAssertEqual(
            WindowApplicationSearch.filtered(applications, query: "   "),
            applications
        )
    }
}
