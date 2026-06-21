import Foundation

enum LayoutDeletionAction: Equatable {
    case unavailable
    case deleteImmediately
    case requireConfirmation
}

enum LayoutSidebarRules {
    static func deletionAction(
        layoutCount: Int,
        currentLayoutID: UUID?,
        targetLayoutID: UUID,
        portalCount: Int,
        isLocked: Bool
    ) -> LayoutDeletionAction {
        guard layoutCount > 1 else { return .unavailable }
        guard currentLayoutID != targetLayoutID else { return .unavailable }
        guard !isLocked else { return .unavailable }
        return portalCount == 0 ? .deleteImmediately : .requireConfirmation
    }

    static func canDeleteLayout(
        layoutCount: Int,
        currentLayoutID: UUID?,
        targetLayoutID: UUID,
        isLocked: Bool
    ) -> Bool {
        deletionAction(
            layoutCount: layoutCount,
            currentLayoutID: currentLayoutID,
            targetLayoutID: targetLayoutID,
            portalCount: 0,
            isLocked: isLocked
        ) != .unavailable
    }

    static func deleteDisabledHelpText(
        layoutCount: Int,
        currentLayoutID: UUID?,
        targetLayoutID: UUID,
        isLocked: Bool
    ) -> String {
        if isLocked {
            return L("layout.delete_disabled_locked")
        }
        if currentLayoutID == targetLayoutID {
            return L("layout.delete_disabled_current")
        }
        if layoutCount <= 1 {
            return L("layout.delete_disabled_last_remaining")
        }
        return L("layout.delete")
    }

    static func nextSelectedLayoutID(
        afterDeleting targetLayoutID: UUID,
        currentSelectionID: UUID?,
        orderedLayoutIDs: [UUID]
    ) -> UUID? {
        guard currentSelectionID == targetLayoutID else { return currentSelectionID }
        return orderedLayoutIDs.first { $0 != targetLayoutID }
    }

    static func deleteConfirmationMessage(portalCount: Int) -> String {
        if portalCount == 1 {
            return L("layout.delete_confirm_message_one")
        }
        return L("layout.delete_confirm_message_many %lld", portalCount)
    }
}

enum AccessibilityPermissionPresentation {
    static func statusLocalizationKey(isGranted: Bool) -> String {
        isGranted ? "settings.permission_granted" : "settings.permission_not_granted"
    }

    static func statusText(isGranted: Bool) -> String {
        L(statusLocalizationKey(isGranted: isGranted))
    }

    static func menuStatusTitle(isGranted: Bool) -> String {
        L("menu.accessibility_status %@", statusText(isGranted: isGranted))
    }
}
