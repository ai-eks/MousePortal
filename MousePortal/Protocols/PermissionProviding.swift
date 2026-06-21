import Foundation
import ApplicationServices

/// 权限检查协议 - 用于依赖注入和测试
protocol PermissionProviding {
    func isAccessibilityGranted() -> Bool
    func requestAccessibility()
}

/// 真实实现 - 调用系统 API
final class SystemPermissionProvider: PermissionProviding {
    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
