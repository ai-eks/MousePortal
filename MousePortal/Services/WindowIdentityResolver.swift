import AppKit
import ApplicationServices
import Darwin

enum WindowIdentityResolver {
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // 私有接口：用于精确关联 AX 对象与 WindowServer 窗口，不能用标题/尺寸推测。
    // 动态加载失败时禁用这一层身份核验，继续原有匹配流程。
    private static let getWindowID: GetWindowID? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else {
            dlclose(handle)
            return nil
        }
        // 保留库句柄，确保函数指针在进程存续期间有效。
        return unsafeBitCast(symbol, to: GetWindowID.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let getWindowID else { return nil }
        var windowID = kCGNullWindowID
        guard getWindowID(element, &windowID) == .success,
              windowID != kCGNullWindowID else { return nil }
        return windowID
    }

    static func currentSessionIdentifier() -> String? {
        var length = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0,
              length > 0 else { return nil }
        var bootSession = [CChar](repeating: 0, count: length)
        guard sysctlbyname("kern.bootsessionuuid", &bootSession, &length, nil, 0) == 0 else { return nil }
        var auditInfo = auditinfo_addr_t()
        guard getaudit_addr(&auditInfo, Int32(MemoryLayout<auditinfo_addr_t>.size)) == 0 else { return nil }
        return "\(String(cString: bootSession)):\(geteuid()):\(auditInfo.ai_asid)"
    }

    static func identity(
        for application: NSRunningApplication,
        windowID: CGWindowID?,
        sessionIdentifier: String?
    ) -> WindowRuntimeIdentity? {
        guard let windowID, windowID != kCGNullWindowID,
              let sessionIdentifier, !sessionIdentifier.isEmpty,
              let bundleIdentifier = application.bundleIdentifier,
              let launchDate = application.launchDate,
              application.processIdentifier > 0,
              !application.isTerminated else { return nil }
        return WindowRuntimeIdentity(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: application.processIdentifier,
            processLaunchDate: launchDate,
            sessionIdentifier: sessionIdentifier,
            windowID: windowID
        )
    }
}
