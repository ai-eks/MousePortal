import Foundation
@testable import MousePortal

final class MockPermissionProvider: PermissionProviding {
    var accessibilityGranted = true
    var requestAccessibilityCalled = false

    func isAccessibilityGranted() -> Bool {
        return accessibilityGranted
    }

    func requestAccessibility() {
        requestAccessibilityCalled = true
    }
}
