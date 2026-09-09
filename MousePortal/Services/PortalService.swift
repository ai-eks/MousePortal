import Foundation
import CoreGraphics
import Cocoa

private final class PortalEventTapState {
    private let lock = NSLock()
    private var portals: [PortalPair] = []
    private var triggerMode: PortalTriggerMode = .automatic
    private var triggerKeyMask = PortalTriggerKey.option.flagsMask
    private var displayBoundsCache: [UInt32: CGRect] = [:]
    private var layoutResolver: DisplayLayoutResolver?
    private var isKeyPressed = false
    private var eventTap: CFMachPort?

    func updateConfiguration(
        portals: [PortalPair],
        triggerMode: PortalTriggerMode,
        triggerKeyMask: UInt64
    ) {
        lock.lock()
        self.portals = portals
        self.triggerMode = triggerMode
        self.triggerKeyMask = triggerKeyMask
        lock.unlock()
    }

    func applyDisplayConfiguration(
        portals: [PortalPair],
        triggerMode: PortalTriggerMode,
        triggerKeyMask: UInt64,
        displayBoundsCache: [UInt32: CGRect],
        layoutResolver: DisplayLayoutResolver?
    ) {
        lock.lock()
        self.portals = portals
        self.triggerMode = triggerMode
        self.triggerKeyMask = triggerKeyMask
        self.displayBoundsCache = displayBoundsCache
        self.layoutResolver = layoutResolver
        lock.unlock()
    }

    func setEventTap(_ tap: CFMachPort?) {
        lock.lock()
        eventTap = tap
        if tap == nil {
            isKeyPressed = false
        }
        lock.unlock()
    }

    func reenableTapIfNeeded() {
        lock.lock()
        let tap = eventTap
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func updateKeyPressed(with flags: UInt64) {
        lock.lock()
        isKeyPressed = (flags & triggerKeyMask) == triggerKeyMask
        lock.unlock()
    }

    func snapshot() -> (
        portals: [PortalPair],
        triggerMode: PortalTriggerMode,
        displayBoundsCache: [UInt32: CGRect],
        layoutResolver: DisplayLayoutResolver?,
        isKeyPressed: Bool
    ) {
        lock.lock()
        let snapshot = (portals, triggerMode, displayBoundsCache, layoutResolver, isKeyPressed)
        lock.unlock()
        return snapshot
    }
}

/// 传送门服务：监听鼠标并处理传送
@MainActor
class PortalService: ObservableObject {
    static let shared = PortalService()

    @Published var isRunning = false
    @Published var portals: [PortalPair] = [] {
        didSet {
            syncCallbackConfiguration()
        }
    }
    @Published var triggerMode: PortalTriggerMode = .automatic {
        didSet {
            syncCallbackConfiguration()
        }
    }
    @Published var triggerKey: PortalTriggerKey = .option {
        didSet {
            defaults.set(triggerKey.rawValue, forKey: triggerKeyKey)
            syncCallbackConfiguration()
        }
    }

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let permissionService = PermissionService.shared

    private let userDefaultsKey = "portalPairs"
    private let triggerModeKey = "portalTriggerMode"
    private let triggerKeyKey = "portalTriggerKey"
    private let defaults: UserDefaults
    private var isApplyingDisplayConfiguration = false
    private var hasBackedUpPreviousPortals = false

    private var displayBoundsCache: [UInt32: CGRect] = [:]
    private var layoutResolver: DisplayLayoutResolver?
    nonisolated(unsafe) private let callbackState = PortalEventTapState()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func syncCallbackConfiguration() {
        guard !isApplyingDisplayConfiguration else { return }
        callbackState.updateConfiguration(
            portals: portals,
            triggerMode: triggerMode,
            triggerKeyMask: triggerKey.flagsMask
        )
    }

    // MARK: - Persistence

    func load() {
        if let data = defaults.data(forKey: userDefaultsKey),
           let portals = try? JSONDecoder().decode([PortalPair].self, from: data) {
            self.portals = portals

            // 检查是否需要迁移
            migrateIfNeeded()
        }

        if let modeString = defaults.string(forKey: triggerModeKey),
           let mode = PortalTriggerMode(rawValue: modeString) {
            self.triggerMode = mode
        }

        if let triggerKeyString = defaults.string(forKey: triggerKeyKey),
           let triggerKey = PortalTriggerKey(rawValue: triggerKeyString) {
            self.triggerKey = triggerKey
        }
    }

    /// 迁移旧格式的配置（从 displayID 到 displayLayoutKey）
    private func migrateIfNeeded() {
        var needsMigration = false

        // 检查是否有使用旧格式的 portal
        for portal in portals {
            if portal.lineA.displayLayoutKey == nil || portal.lineB.displayLayoutKey == nil {
                needsMigration = true
                break
            }
        }

        guard needsMigration else { return }

        // 获取当前显示器列表用于迁移
        let displayIDs = queryActiveDisplayIDs()
        let displayCount = displayIDs.count

        var idToLayoutKey: [UInt32: DisplayLayoutKey] = [:]
        for i in 0..<displayCount {
            let displayID = displayIDs[i]
            let bounds = CGDisplayBounds(displayID)
            idToLayoutKey[displayID] = DisplayLayoutKey(frame: bounds)
        }

        // 迁移每个 portal
        var migratedPortals: [PortalPair] = []
        for var portal in portals {
            // 迁移 lineA
            if portal.lineA.displayLayoutKey == nil,
               let legacyID = portal.lineA.legacyDisplayID,
               let layoutKey = idToLayoutKey[legacyID] {
                portal.lineA = PortalLine(
                    displayLayoutKey: layoutKey,
                    edge: portal.lineA.edge,
                    startOffset: portal.lineA.startOffset,
                    endOffset: portal.lineA.endOffset
                )
            }

            // 迁移 lineB
            if portal.lineB.displayLayoutKey == nil,
               let legacyID = portal.lineB.legacyDisplayID,
               let layoutKey = idToLayoutKey[legacyID] {
                portal.lineB = PortalLine(
                    displayLayoutKey: layoutKey,
                    edge: portal.lineB.edge,
                    startOffset: portal.lineB.startOffset,
                    endOffset: portal.lineB.endOffset
                )
            }

            migratedPortals.append(portal)
        }

        self.portals = migratedPortals
        save()  // 保存迁移后的配置

        print("已迁移 \(migratedPortals.count) 个传送门配置到新格式")
    }

    func save() {
        if let data = try? JSONEncoder().encode(portals) {
            defaults.set(data, forKey: userDefaultsKey)
        }
        defaults.set(triggerMode.rawValue, forKey: triggerModeKey)
        defaults.set(triggerKey.rawValue, forKey: triggerKeyKey)
        syncCallbackConfiguration()
    }

    // MARK: - Portal Management

    func addPortal(_ portal: PortalPair) {
        portals.append(portal)
        save()
    }

    func updatePortal(_ portal: PortalPair) {
        if let index = portals.firstIndex(where: { $0.id == portal.id }) {
            portals[index] = portal
            save()
        }
    }

    func removePortal(id: UUID) {
        portals.removeAll { $0.id == id }
        save()
    }

    func togglePortal(id: UUID) {
        if let index = portals.firstIndex(where: { $0.id == id }) {
            portals[index].isEnabled.toggle()
            save()
        }
    }

    // MARK: - Event Monitoring

    func start() {
        guard !isRunning else { return }
        guard permissionService.checkAccessibility() else {
            print("辅助功能权限未授予，无法启动传送门监听")
            return
        }

        let eventMask = (1 << CGEventType.mouseMoved.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: portalEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("无法创建传送门事件监听器")
            return
        }

        eventTap = tap
        callbackState.setEventTap(tap)
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isRunning = true
            print("传送门监听已启动")
        }
    }

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

        print("传送门监听已停止")
    }

    /// Replace portal geometry and display resolution together for the event callback.
    /// This does not start or stop input monitoring.
    func applyDisplayConfiguration(portals: [PortalPair], displays: [DisplayInfo]) {
        if !hasBackedUpPreviousPortals {
            let backupKey = "portalPairsBeforeLayoutSync"
            if defaults.object(forKey: backupKey) == nil,
               let previousData = defaults.data(forKey: userDefaultsKey) {
                defaults.set(previousData, forKey: backupKey)
            }
            hasBackedUpPreviousPortals = true
        }

        isApplyingDisplayConfiguration = true
        defer { isApplyingDisplayConfiguration = false }
        self.portals = portals
        displayBoundsCache = Dictionary(displays.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        layoutResolver = DisplayLayoutResolver(displays: displays)
        callbackState.applyDisplayConfiguration(
            portals: portals,
            triggerMode: triggerMode,
            triggerKeyMask: triggerKey.flagsMask,
            displayBoundsCache: displayBoundsCache,
            layoutResolver: layoutResolver
        )
        save()
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

    // MARK: - Event Handling

    nonisolated fileprivate func handleTapDisabledForTap() {
        callbackState.reenableTapIfNeeded()
    }

    nonisolated fileprivate func handleFlagsChangedForTap(_ event: CGEvent) {
        callbackState.updateKeyPressed(with: event.flags.rawValue)
    }

    nonisolated func handleMouseMovedForTap(_ event: CGEvent) -> CGPoint? {
        let snapshot = callbackState.snapshot()

        if snapshot.triggerMode == .withKey && !snapshot.isKeyPressed {
            return nil
        }

        guard let resolver = snapshot.layoutResolver else { return nil }

        let mouseLocation = event.location

        for portal in snapshot.portals where portal.isEnabled {
            // 通过布局标识解析显示器边界
            guard let keyA = portal.lineA.displayLayoutKey,
                  let keyB = portal.lineB.displayLayoutKey,
                  let boundsA = resolver.resolveBounds(keyA),
                  let boundsB = resolver.resolveBounds(keyB) else {
                // 回退到旧的 displayID 方式（迁移期间）
                if let boundsA = snapshot.displayBoundsCache[portal.lineA.legacyDisplayID ?? 0],
                   let boundsB = snapshot.displayBoundsCache[portal.lineB.legacyDisplayID ?? 0] {
                    if isPointOnLine(mouseLocation, line: portal.lineA, bounds: boundsA) {
                        if let target = portal.calculateTargetPosition(from: mouseLocation, lineABounds: boundsA, lineBBounds: boundsB) {
                            return target
                        }
                    }

                    if portal.isBidirectional && isPointOnLine(mouseLocation, line: portal.lineB, bounds: boundsB) {
                        let reversedPortal = PortalPair(
                            name: portal.name,
                            lineA: portal.lineB,
                            lineB: portal.lineA,
                            isEnabled: portal.isEnabled,
                            isBidirectional: portal.isBidirectional,
                            color: portal.color
                        )
                        if let target = reversedPortal.calculateTargetPosition(from: mouseLocation, lineABounds: boundsB, lineBBounds: boundsA) {
                            return target
                        }
                    }
                }
                continue
            }

            if isPointOnLine(mouseLocation, line: portal.lineA, bounds: boundsA) {
                if let target = portal.calculateTargetPosition(from: mouseLocation, lineABounds: boundsA, lineBBounds: boundsB) {
                    return target
                }
            }

            // 如果是双向，也检查线B
            if portal.isBidirectional {
                if isPointOnLine(mouseLocation, line: portal.lineB, bounds: boundsB) {
                    let reversedPortal = PortalPair(
                        name: portal.name,
                        lineA: portal.lineB,
                        lineB: portal.lineA,
                        isEnabled: portal.isEnabled,
                        isBidirectional: portal.isBidirectional,
                        color: portal.color
                    )
                    if let target = reversedPortal.calculateTargetPosition(from: mouseLocation, lineABounds: boundsB, lineBBounds: boundsA) {
                        return target
                    }
                }
            }
        }

        return nil
    }

    nonisolated private func isPointOnLine(_ point: CGPoint, line: PortalLine, bounds: CGRect) -> Bool {
        let start = line.startPoint(in: bounds)
        let end = line.endPoint(in: bounds)
        let tolerance: CGFloat = 3.0  // 3像素容差

        switch line.edge {
        case .left:
            return abs(point.x - bounds.minX) < tolerance &&
                   point.y >= min(start.y, end.y) &&
                   point.y <= max(start.y, end.y)
        case .right:
            return abs(point.x - bounds.maxX) < tolerance &&
                   point.y >= min(start.y, end.y) &&
                   point.y <= max(start.y, end.y)
        case .top:
            return abs(point.y - bounds.minY) < tolerance &&
                   point.x >= min(start.x, end.x) &&
                   point.x <= max(start.x, end.x)
        case .bottom:
            return abs(point.y - bounds.maxY) < tolerance &&
                   point.x >= min(start.x, end.x) &&
                   point.x <= max(start.x, end.x)
        }
    }

    func teleportMouse(to point: CGPoint, withDeltaX deltaX: Double, deltaY: Double) {
        CGWarpMouseCursorPosition(point)

        // 创建带有原始速度和方向的移动事件
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            // 保持原始的移动速度和方向
            moveEvent.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
            moveEvent.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}

/// 传送门事件回调
private func portalEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<PortalService>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        print("传送门监听被系统禁用，尝试重新启动...")
        service.handleTapDisabledForTap()
        return Unmanaged.passUnretained(event)

    case .flagsChanged:
        service.handleFlagsChangedForTap(event)

    case .mouseMoved, .leftMouseDragged:
        if let target = service.handleMouseMovedForTap(event) {
            // 保留原有的 HID 事件传送手感，但不再切换全局鼠标关联状态。
            if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: target, mouseButton: .left) {
                moveEvent.setDoubleValueField(.mouseEventDeltaX, value: event.getDoubleValueField(.mouseEventDeltaX))
                moveEvent.setDoubleValueField(.mouseEventDeltaY, value: event.getDoubleValueField(.mouseEventDeltaY))
                moveEvent.post(tap: .cghidEventTap)
            }

            return nil
        }

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
