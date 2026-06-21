import Foundation
import CoreGraphics

/// 显示器服务：获取显示器信息并计算共享边界
class DisplayService: ObservableObject {
    static let shared = DisplayService()

    @Published var displays: [DisplayInfo] = []
    @Published var sharedEdges: [SharedEdge] = []

    /// 获取所有显示器信息
    func fetchDisplays() {
        let displayIDs = queryActiveDisplayIDs()
        guard !displayIDs.isEmpty else {
            print("获取显示器列表失败")
            return
        }
        let displayCount = displayIDs.count

        let mainDisplayID = CGMainDisplayID()

        // 先计算外接显示器的编号（跳过主显示器）
        var externalIndex = 0
        displays = (0..<Int(displayCount)).map { index in
            let displayID = displayIDs[index]
            let bounds = CGDisplayBounds(displayID)
            let isMain = displayID == mainDisplayID

            let name: String
            if isMain {
                name = L("display.main")
            } else {
                externalIndex += 1
                name = L("display.external %lld", externalIndex)
            }

            return DisplayInfo(
                id: displayID,
                frame: bounds,
                isMain: isMain,
                name: name
            )
        }

        // 计算共享边界
        sharedEdges = calculateSharedEdges()
    }

    private func queryActiveDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        let countError = CGGetActiveDisplayList(0, nil, &displayCount)
        guard countError == .success, displayCount > 0 else { return [] }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let listError = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        guard listError == .success else { return [] }
        return Array(displayIDs.prefix(Int(displayCount)))
    }

    /// 计算所有显示器之间的共享边界
    private func calculateSharedEdges() -> [SharedEdge] {
        var edges: [SharedEdge] = []

        for i in 0..<displays.count {
            for j in (i + 1)..<displays.count {
                let d1 = displays[i]
                let d2 = displays[j]

                // 检查左右相邻 (d1 在 d2 左边)
                if let edge = checkHorizontalAdjacency(left: d1, right: d2) {
                    edges.append(edge)
                }
                // 检查左右相邻 (d2 在 d1 左边)
                if let edge = checkHorizontalAdjacency(left: d2, right: d1) {
                    edges.append(edge)
                }
                // 检查上下相邻 (d1 在 d2 上面)
                if let edge = checkVerticalAdjacency(top: d1, bottom: d2) {
                    edges.append(edge)
                }
                // 检查上下相邻 (d2 在 d1 上面)
                if let edge = checkVerticalAdjacency(top: d2, bottom: d1) {
                    edges.append(edge)
                }
            }
        }

        return edges
    }

    /// 检查水平方向相邻（left 的右边缘 = right 的左边缘）
    private func checkHorizontalAdjacency(left: DisplayInfo, right: DisplayInfo) -> SharedEdge? {
        // 允许 1 像素的误差
        guard abs(left.rightEdge - right.leftEdge) <= 1 else { return nil }

        // 计算 Y 方向的重叠区间
        let overlapTop = max(left.topEdge, right.topEdge)
        let overlapBottom = min(left.bottomEdge, right.bottomEdge)

        guard overlapBottom > overlapTop else { return nil }

        let x = left.rightEdge
        return SharedEdge(
            from: left.id,
            to: right.id,
            start: CGPoint(x: x, y: overlapTop),
            end: CGPoint(x: x, y: overlapBottom)
        )
    }

    /// 检查垂直方向相邻（top 的下边缘 = bottom 的上边缘）
    private func checkVerticalAdjacency(top: DisplayInfo, bottom: DisplayInfo) -> SharedEdge? {
        // 允许 1 像素的误差
        guard abs(top.bottomEdge - bottom.topEdge) <= 1 else { return nil }

        // 计算 X 方向的重叠区间
        let overlapLeft = max(top.leftEdge, bottom.leftEdge)
        let overlapRight = min(top.rightEdge, bottom.rightEdge)

        guard overlapRight > overlapLeft else { return nil }

        let y = top.bottomEdge
        return SharedEdge(
            from: top.id,
            to: bottom.id,
            start: CGPoint(x: overlapLeft, y: y),
            end: CGPoint(x: overlapRight, y: y)
        )
    }

    /// 计算所有显示器的总边界框
    var totalBounds: CGRect {
        guard !displays.isEmpty else { return .zero }

        let minX = displays.map { $0.frame.minX }.min() ?? 0
        let minY = displays.map { $0.frame.minY }.min() ?? 0
        let maxX = displays.map { $0.frame.maxX }.max() ?? 0
        let maxY = displays.map { $0.frame.maxY }.max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
