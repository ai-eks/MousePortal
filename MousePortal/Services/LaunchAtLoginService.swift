import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published private(set) var isEnabled: Bool = false

    private let storageKey = "launchAtLogin"

    private init() {
        refreshState()
    }

    func refreshState() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: storageKey)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("设置登录启动失败: \(error)")
            }

            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = enabled
        }

        UserDefaults.standard.set(isEnabled, forKey: storageKey)
    }
}
