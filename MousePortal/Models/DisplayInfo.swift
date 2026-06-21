import Foundation
import CoreGraphics

/// 显示器布局标识（用于持久化，替代不稳定的 CGDirectDisplayID）
struct DisplayLayoutKey: Codable, Hashable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(frame: CGRect) {
        self.x = Int(frame.origin.x)
        self.y = Int(frame.origin.y)
        self.width = Int(frame.width)
        self.height = Int(frame.height)
    }
}

/// 显示器信息模型
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let isMain: Bool
    let name: String

    var width: Int { Int(frame.width) }
    var height: Int { Int(frame.height) }
    var x: Int { Int(frame.origin.x) }
    var y: Int { Int(frame.origin.y) }

    /// 显示器的四条边
    var leftEdge: CGFloat { frame.minX }
    var rightEdge: CGFloat { frame.maxX }
    var topEdge: CGFloat { frame.minY }
    var bottomEdge: CGFloat { frame.maxY }

    /// 布局标识（用于持久化匹配）
    var layoutKey: DisplayLayoutKey {
        DisplayLayoutKey(frame: frame)
    }
}

/// 可滑动的共享边界
struct SharedEdge: Identifiable, Equatable {
    let id: UUID
    let fromDisplayID: CGDirectDisplayID
    let toDisplayID: CGDirectDisplayID
    let start: CGPoint
    let end: CGPoint

    init(from: CGDirectDisplayID, to: CGDirectDisplayID, start: CGPoint, end: CGPoint) {
        self.id = UUID()
        self.fromDisplayID = from
        self.toDisplayID = to
        self.start = start
        self.end = end
    }

    static func == (lhs: SharedEdge, rhs: SharedEdge) -> Bool {
        lhs.fromDisplayID == rhs.fromDisplayID &&
        lhs.toDisplayID == rhs.toDisplayID &&
        lhs.start == rhs.start &&
        lhs.end == rhs.end
    }
}
