import Foundation
import CoreGraphics
@testable import MousePortal

final class MockMouseWarper: MouseWarping {
    var lastWarpedPoint: CGPoint?
    var warpCallCount = 0
    var postedEvents: [(type: CGEventType, point: CGPoint, deltaX: Double, deltaY: Double)] = []

    func warpCursor(to point: CGPoint) {
        lastWarpedPoint = point
        warpCallCount += 1
    }

    func postMouseEvent(type: CGEventType, at point: CGPoint, deltaX: Double, deltaY: Double) {
        postedEvents.append((type, point, deltaX, deltaY))
    }

    func reset() {
        lastWarpedPoint = nil
        warpCallCount = 0
        postedEvents.removeAll()
    }
}
