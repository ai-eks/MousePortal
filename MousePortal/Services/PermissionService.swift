import Foundation
import ApplicationServices
import Cocoa

/// 权限服务：检测和引导辅助功能权限
class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published var isAccessibilityGranted: Bool = false
    private var permissionPollTimer: Timer?

    private init() {
        _ = checkAccessibility()
    }

    /// 检查辅助功能权限
    func checkAccessibility() -> Bool {
        isAccessibilityGranted = AXIsProcessTrusted()
        return isAccessibilityGranted
    }

    /// 请求辅助功能权限（先触发系统提示，再兜底打开系统设置）
    func requestAccessibility() {
        guard !checkAccessibility() else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        startPermissionPolling()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.checkAccessibility() else { return }
            self.openAccessibilitySettings()
        }
    }

    /// 打开系统辅助功能设置
    func openAccessibilitySettings() {
        let urlString: String
        if #available(macOS 14.0, *) {
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()

        let startTime = Date()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            if self.checkAccessibility() {
                timer.invalidate()
                self.permissionPollTimer = nil
                return
            }

            // 最长轮询 30 秒，避免永久定时器
            if Date().timeIntervalSince(startTime) > 30 {
                timer.invalidate()
                self.permissionPollTimer = nil
            }
        }
    }
}
