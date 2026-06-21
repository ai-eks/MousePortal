import Foundation
import CoreGraphics

/// 显示器布局解析器：将 DisplayLayoutKey 映射到当前的 CGDirectDisplayID
class DisplayLayoutResolver {
    private(set) var layoutToDisplayID: [DisplayLayoutKey: CGDirectDisplayID] = [:]
    private(set) var layoutToBounds: [DisplayLayoutKey: CGRect] = [:]

    init(displays: [DisplayInfo]) {
        for display in displays {
            let key = display.layoutKey
            if layoutToDisplayID[key] != nil {
                // 镜像屏场景下 key 可能重复，保留首次映射并记录日志。
                print("检测到重复 DisplayLayoutKey，已保留首次映射: \(key)")
                continue
            }
            layoutToDisplayID[key] = display.id
            layoutToBounds[key] = display.frame
        }
    }

    /// 根据布局标识解析当前的 displayID
    func resolve(_ key: DisplayLayoutKey) -> CGDirectDisplayID? {
        layoutToDisplayID[key]
    }

    /// 根据布局标识解析显示器边界
    func resolveBounds(_ key: DisplayLayoutKey) -> CGRect? {
        layoutToBounds[key]
    }

    /// 批量解析多个布局标识
    func resolve(_ keys: [DisplayLayoutKey]) -> [DisplayLayoutKey: CGDirectDisplayID] {
        var result: [DisplayLayoutKey: CGDirectDisplayID] = [:]
        for key in keys {
            if let id = resolve(key) {
                result[key] = id
            }
        }
        return result
    }
}
