import Foundation
import CoreGraphics

/// 鼠标移动协议 - 用于依赖注入和测试
protocol MouseWarping {
    func warpCursor(to point: CGPoint)
    func postMouseEvent(type: CGEventType, at point: CGPoint, deltaX: Double, deltaY: Double)
}

/// 真实实现 - 调用系统 API
final class SystemMouseWarper: MouseWarping {
    func warpCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    func postMouseEvent(type: CGEventType, at point: CGPoint, deltaX: Double, deltaY: Double) {
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            moveEvent.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
            moveEvent.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
