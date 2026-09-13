import CoreGraphics
import Darwin

enum WindowServerGeometry {
    private typealias GetConnectionID = @convention(c) () -> Int32
    private typealias GetWindowBounds = @convention(c) (
        Int32, CGWindowID, UnsafeMutablePointer<CGRect>
    ) -> CGError

    // 私有只读接口：锁屏动画期间 CGWindowList 的边框会缩小，SLS 边框保留原始几何。
    // 动态加载失败时返回 nil，不退回可能包含动画尺寸的 CG 边框。
    private static let functions: (connection: GetConnectionID, bounds: GetWindowBounds)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        guard let connection = dlsym(handle, "SLSMainConnectionID"),
              let bounds = dlsym(handle, "SLSGetWindowBounds") else {
            dlclose(handle)
            return nil
        }
        // 保留库句柄，确保函数指针在进程存续期间有效。
        return (
            unsafeBitCast(connection, to: GetConnectionID.self),
            unsafeBitCast(bounds, to: GetWindowBounds.self)
        )
    }()

    static func bounds(for windowID: CGWindowID) -> CGRect? {
        guard windowID != kCGNullWindowID, let functions else { return nil }
        var frame = CGRect.zero
        guard functions.bounds(functions.connection(), windowID, &frame) == .success else { return nil }
        return frame
    }
}
