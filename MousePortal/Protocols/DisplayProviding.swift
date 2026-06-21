import Foundation
import CoreGraphics

/// 显示器信息提供协议 - 用于依赖注入和测试
protocol DisplayProviding {
    func getActiveDisplays() -> [DisplayInfo]
    func getDisplayBounds(displayID: CGDirectDisplayID) -> CGRect
    func getMainDisplayID() -> CGDirectDisplayID
}

/// 真实实现 - 调用系统 API
final class SystemDisplayProvider: DisplayProviding {
    func getActiveDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        let countError = CGGetActiveDisplayList(0, nil, &displayCount)
        guard countError == .success, displayCount > 0 else { return [] }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let listError = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        guard listError == .success else { return [] }

        let mainDisplayID = CGMainDisplayID()
        var externalIndex = 0

        return (0..<Int(displayCount)).map { index in
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
    }

    func getDisplayBounds(displayID: CGDirectDisplayID) -> CGRect {
        return CGDisplayBounds(displayID)
    }

    func getMainDisplayID() -> CGDirectDisplayID {
        return CGMainDisplayID()
    }
}
