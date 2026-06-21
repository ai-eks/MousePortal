import Foundation
import CoreGraphics
import Combine

private final class HotkeyEventTapState {
    private let lock = NSLock()
    private var configs: [HotkeyConfig] = []
    private var globalEnabled = true
    private var eventTap: CFMachPort?
    private var tapReenableBackoff: TimeInterval = 0.25
    private var nextTapReenableDate: Date = .distantPast

    func update(configs: [HotkeyConfig], globalEnabled: Bool) {
        lock.lock()
        self.configs = configs
        self.globalEnabled = globalEnabled
        lock.unlock()
    }

    func snapshot() -> (configs: [HotkeyConfig], globalEnabled: Bool) {
        lock.lock()
        let snapshot = (configs, globalEnabled)
        lock.unlock()
        return snapshot
    }

    func setEventTap(_ tap: CFMachPort?) {
        lock.lock()
        eventTap = tap
        if tap == nil {
            tapReenableBackoff = 0.25
            nextTapReenableDate = .distantPast
        }
        lock.unlock()
    }

    func reenableTapIfNeeded() {
        lock.lock()
        let now = Date()
        guard now >= nextTapReenableDate, let tap = eventTap else {
            lock.unlock()
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        nextTapReenableDate = now.addingTimeInterval(tapReenableBackoff)
        tapReenableBackoff = min(tapReenableBackoff * 2, 4.0)
        lock.unlock()
    }

    func resetTapReenableBackoff() {
        lock.lock()
        tapReenableBackoff = 0.25
        nextTapReenableDate = .distantPast
        lock.unlock()
    }
}

/// 全局快捷键监听服务
@MainActor
class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published var isRunning = false

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let configStore = HotkeyConfigStore.shared
    private let permissionService = PermissionService.shared
    private var cancellables: Set<AnyCancellable> = []
    nonisolated(unsafe) private let callbackState = HotkeyEventTapState()

    private init() {
        NotificationCenter.default.publisher(for: .hotkeyConfigStoreDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncCallbackState()
            }
            .store(in: &cancellables)

        syncCallbackState()
    }

    /// 启动快捷键监听
    func start() {
        guard !isRunning else { return }
        guard permissionService.checkAccessibility() else {
            print("辅助功能权限未授予，无法启动快捷键监听")
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("无法创建事件监听器")
            return
        }

        eventTap = tap
        callbackState.setEventTap(tap)
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isRunning = true
            print("快捷键监听已启动")
        }
    }

    /// 停止快捷键监听
    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        callbackState.setEventTap(nil)
        runLoopSource = nil
        isRunning = false
        print("快捷键监听已停止")
    }

    private func syncCallbackState() {
        callbackState.update(
            configs: configStore.configs,
            globalEnabled: configStore.globalEnabled
        )
    }

    nonisolated fileprivate func handleTapDisabled() {
        callbackState.reenableTapIfNeeded()
    }

    nonisolated fileprivate func resetTapReenableBackoffForTap() {
        callbackState.resetTapReenableBackoff()
    }

    /// 处理快捷键事件
    nonisolated fileprivate func handleKeyEventForTap(_ event: CGEvent) -> Bool {
        let snapshot = callbackState.snapshot()
        guard snapshot.globalEnabled else { return false }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue

        let modifierMask: UInt64 = UInt64(CGEventFlags.maskControl.rawValue) |
            UInt64(CGEventFlags.maskAlternate.rawValue) |
            UInt64(CGEventFlags.maskShift.rawValue) |
            UInt64(CGEventFlags.maskCommand.rawValue)
        let eventModifiers = flags & modifierMask

        for config in snapshot.configs {
            guard config.isEnabled else { continue }
            guard config.keyCode == keyCode else { continue }

            if config.modifiers == eventModifiers,
               let displayID = resolveDisplayID(for: config) {
                moveCursorToDisplay(displayID)
                return true
            }
        }

        return false
    }

    /// 移动鼠标到指定显示器中心
    nonisolated private func moveCursorToDisplay(_ displayID: UInt32) {
        let bounds = CGDisplayBounds(displayID)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        CGWarpMouseCursorPosition(center)

        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }

        print("鼠标已移动到显示器 \(displayID) 中心: \(center)")
    }

    nonisolated private func resolveDisplayID(for config: HotkeyConfig) -> UInt32? {
        if let layoutKey = config.displayLayoutKey,
           let resolved = resolveDisplayID(for: layoutKey) {
            return resolved
        }
        return config.legacyDisplayID
    }

    nonisolated private func resolveDisplayID(for key: DisplayLayoutKey) -> UInt32? {
        var displayCount: UInt32 = 0
        let countError = CGGetActiveDisplayList(0, nil, &displayCount)
        guard countError == .success, displayCount > 0 else { return nil }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let listError = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        guard listError == .success else { return nil }

        for displayID in displayIDs.prefix(Int(displayCount)) {
            let bounds = CGDisplayBounds(displayID)
            let candidate = DisplayLayoutKey(frame: bounds)
            if candidate == key {
                return displayID
            }
        }

        return nil
    }
}

/// 快捷键事件回调函数
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // 如果事件 tap 被禁用，重新启用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
            service.handleTapDisabled()
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
    service.resetTapReenableBackoffForTap()
    let consumed = service.handleKeyEventForTap(event)

    if consumed {
        // 消费该事件，不传递给其他应用
        return nil
    }

    return Unmanaged.passUnretained(event)
}
