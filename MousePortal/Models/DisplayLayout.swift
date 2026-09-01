import Foundation
import CoreGraphics

/// 显示器快照 - 用于匹配当前显示器排列
struct DisplaySnapshot: Codable, Equatable, Identifiable {
    let id: UUID
    let displayID: UInt32      // 原始显示器ID（可能变化）
    let width: Int
    let height: Int
    let x: Int                 // 相对位置
    let y: Int
    let isMain: Bool
    var customName: String?

    init(from display: DisplayInfo) {
        self.id = UUID()
        self.displayID = display.id
        self.width = display.width
        self.height = display.height
        self.x = display.x
        self.y = display.y
        self.isMain = display.isMain
        self.customName = nil
    }

    init(displayID: UInt32, width: Int, height: Int, x: Int, y: Int, isMain: Bool, customName: String? = nil) {
        self.id = UUID()
        self.displayID = displayID
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.isMain = isMain
        self.customName = customName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayID
        case width
        case height
        case x
        case y
        case isMain
        case customName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayID = try container.decode(UInt32.self, forKey: .displayID)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        x = try container.decode(Int.self, forKey: .x)
        y = try container.decode(Int.self, forKey: .y)
        isMain = try container.decode(Bool.self, forKey: .isMain)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
    }

    var layoutKey: DisplayLayoutKey {
        DisplayLayoutKey(x: x, y: y, width: width, height: height)
    }

    /// 将快照转换为 DisplayInfo 用于显示
    func toDisplayInfo(externalIndex: Int? = nil) -> DisplayInfo {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return DisplayInfo(
            id: displayID,
            frame: frame,
            isMain: isMain,
            name: displayName(externalIndex: externalIndex)
        )
    }

    func displayName(externalIndex: Int? = nil) -> String {
        if let customName, !customName.isEmpty {
            return customName
        }
        if isMain {
            return L("display.main")
        }
        if let externalIndex {
            return L("display.external %lld", externalIndex)
        }
        return L("display.name %lld", Int(displayID))
    }
}

/// 显示器排列配置 - 传送门与显示器排列强绑定
struct DisplayLayout: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var customName: String?
    var displaySnapshots: [DisplaySnapshot]  // 显示器快照
    var portals: [PortalPair]                // 该排列下的传送门
    var isLocked: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, displays: [DisplayInfo], isGeneratedName: Bool = false) {
        self.id = UUID()
        self.name = name
        self.customName = isGeneratedName ? nil : name
        self.displaySnapshots = displays.map { DisplaySnapshot(from: $0) }
        self.portals = []
        self.isLocked = false
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case customName
        case displaySnapshots
        case portals
        case isLocked
        case createdAt
        case modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displaySnapshots = try container.decode([DisplaySnapshot].self, forKey: .displaySnapshots)
        if container.contains(.customName) {
            customName = try container.decodeIfPresent(String.self, forKey: .customName)
        } else {
            customName = Self.isDefaultLayoutName(name, displayCount: displaySnapshots.count) ? nil : name
        }
        portals = try container.decode([PortalPair].self, forKey: .portals)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    /// 检查当前显示器排列是否匹配此配置
    func matches(displays: [DisplayInfo]) -> Bool {
        // 显示器数量必须相同
        guard displays.count == displaySnapshots.count else { return false }

        // 双向一一匹配，避免多个 display 匹配到同一个 snapshot
        var usedSnapshotIndices = Set<Int>()

        for display in displays {
            let matchedIndex = displaySnapshots.indices.first { index in
                guard !usedSnapshotIndices.contains(index) else { return false }
                let snapshot = displaySnapshots[index]
                // 匹配条件：尺寸相同、相对位置相同、主显示器标识相同
                return snapshot.width == display.width &&
                snapshot.height == display.height &&
                snapshot.x == display.x &&
                snapshot.y == display.y &&
                snapshot.isMain == display.isMain
            }
            guard let matchedIndex else { return false }
            usedSnapshotIndices.insert(matchedIndex)
        }

        return true
    }

    /// 生成排列签名（用于快速比较）
    var signature: String {
        let sorted = displaySnapshots.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        return sorted.map { "\($0.width)x\($0.height)@\($0.x),\($0.y)\($0.isMain ? "M" : "")" }.joined(separator: "|")
    }

    /// 获取显示器排列的简短描述
    var layoutDescription: String {
        let count = displaySnapshots.count
        if count == 1 {
            let d = displaySnapshots[0]
            return "\(d.width)×\(d.height)"
        } else {
            return L("layout.display_count %lld", count)
        }
    }

    var displayName: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return Self.defaultLayoutName(displayCount: displaySnapshots.count)
    }

    /// 将快照转换为 DisplayInfo 数组用于显示
    var snapshotDisplays: [DisplayInfo] {
        var externalIndex = 0
        return displaySnapshots.map { snapshot in
            if !snapshot.isMain {
                externalIndex += 1
            }
            return snapshot.toDisplayInfo(externalIndex: snapshot.isMain ? nil : externalIndex)
        }
    }

    func displaysApplyingCustomNames(to displays: [DisplayInfo]) -> [DisplayInfo] {
        var externalIndex = 0
        return displays.map { display in
            if !display.isMain {
                externalIndex += 1
            }
            let snapshot = displaySnapshots.first { $0.layoutKey == display.layoutKey }
            let displayName = snapshot?.displayName(externalIndex: display.isMain ? nil : externalIndex)
                ?? defaultDisplayName(isMain: display.isMain, externalIndex: display.isMain ? nil : externalIndex)
            return DisplayInfo(
                id: display.id,
                frame: display.frame,
                isMain: display.isMain,
                name: displayName
            )
        }
    }

    private func defaultDisplayName(isMain: Bool, externalIndex: Int?) -> String {
        if isMain {
            return L("display.main")
        }
        return L("display.external %lld", externalIndex ?? 1)
    }

    static func defaultLayoutName(displayCount: Int) -> String {
        if displayCount == 1 {
            return L("layout.single_display")
        } else if displayCount == 2 {
            return L("layout.dual_display")
        } else {
            return L("layout.multi_display %lld", displayCount)
        }
    }

    private static func isDefaultLayoutName(_ name: String, displayCount: Int) -> Bool {
        localizedDefaultLayoutNames(displayCount: displayCount).contains(name)
    }

    private static func localizedDefaultLayoutNames(displayCount: Int) -> Set<String> {
        var names = Set<String>()
        names.insert(defaultLayoutName(displayCount: displayCount))

        let lprojURLs = AppResources.bundle.urls(forResourcesWithExtension: "lproj", subdirectory: nil) ?? []
        for url in lprojURLs {
            guard let bundle = Bundle(url: url) else { continue }
            names.insert(defaultLayoutName(displayCount: displayCount, bundle: bundle))
        }
        return names
    }

    private static func defaultLayoutName(displayCount: Int, bundle: Bundle) -> String {
        if displayCount == 1 {
            return bundle.localizedString(forKey: "layout.single_display", value: nil, table: nil)
        } else if displayCount == 2 {
            return bundle.localizedString(forKey: "layout.dual_display", value: nil, table: nil)
        } else {
            let format = bundle.localizedString(forKey: "layout.multi_display %lld", value: nil, table: nil)
            return String(format: format, displayCount)
        }
    }

    /// 计算快照的总边界
    var snapshotTotalBounds: CGRect {
        guard !displaySnapshots.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for snapshot in displaySnapshots {
            minX = min(minX, CGFloat(snapshot.x))
            minY = min(minY, CGFloat(snapshot.y))
            maxX = max(maxX, CGFloat(snapshot.x + snapshot.width))
            maxY = max(maxY, CGFloat(snapshot.y + snapshot.height))
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func == (lhs: DisplayLayout, rhs: DisplayLayout) -> Bool {
        lhs.id == rhs.id
    }
}

/// 显示器排列管理服务
class DisplayLayoutService: ObservableObject {
    static let shared = DisplayLayoutService()

    @Published var layouts: [DisplayLayout] = []
    @Published var currentLayoutID: UUID?

    private let storageKey = "displayLayouts"
    private let currentLayoutKey = "currentLayoutID"

    // MARK: - 稳定性检测

    /// 稳定性检测所需的连续匹配次数
    private let requiredStableCount = 3

    /// 稳定性检测的时间间隔（秒）
    private let stabilityCheckInterval: TimeInterval = 0.5

    /// 当前检测到的显示器签名
    private var pendingSignature: String?

    /// 连续检测到相同签名的次数
    private var stableCount = 0

    /// 稳定性检测定时器
    private var stabilityTimer: Timer?

    /// 待处理的显示器列表
    private var pendingDisplays: [DisplayInfo] = []

    private init() {
        load()
    }

    // MARK: - 存储

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let layouts = try? JSONDecoder().decode([DisplayLayout].self, from: data) {
            self.layouts = layouts
        }

        if let idString = UserDefaults.standard.string(forKey: currentLayoutKey),
           let id = UUID(uuidString: idString) {
            currentLayoutID = id
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }

        if let id = currentLayoutID {
            UserDefaults.standard.set(id.uuidString, forKey: currentLayoutKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentLayoutKey)
        }
    }

    var hasUnusedLayouts: Bool {
        hasUnusedLayouts(preserving: [])
    }

    func hasUnusedLayouts(preserving displayLayoutSignatures: Set<String>) -> Bool {
        layouts.contains { isUnusedLayout($0, preserving: displayLayoutSignatures) }
    }

    /// 仅保留用户明确需要的排列：当前排列、已锁定排列、含传送门或窗口快照的排列
    @discardableResult
    func cleanUpUnusedLayouts(preserving displayLayoutSignatures: Set<String> = []) -> [UUID] {
        let removedIDs = pruneLayouts(preserving: displayLayoutSignatures)
        if !removedIDs.isEmpty {
            save()
        }
        return removedIDs
    }

    private func isUnusedLayout(
        _ layout: DisplayLayout,
        preserving displayLayoutSignatures: Set<String>
    ) -> Bool {
        let isCurrent = layout.id == currentLayoutID
        let hasPortals = !layout.portals.isEmpty
        let hasWindowSnapshots = displayLayoutSignatures.contains(layout.signature)
        return !isCurrent && !layout.isLocked && !hasPortals && !hasWindowSnapshots
    }

    @discardableResult
    private func pruneLayouts(preserving displayLayoutSignatures: Set<String>) -> [UUID] {
        let removedIDs = layouts
            .filter { isUnusedLayout($0, preserving: displayLayoutSignatures) }
            .map(\.id)
        layouts.removeAll { removedIDs.contains($0.id) }
        return removedIDs
    }

    // MARK: - 排列管理

    /// 当前活跃的显示器排列配置
    var currentLayout: DisplayLayout? {
        guard let id = currentLayoutID else { return nil }
        return layouts.first { $0.id == id }
    }

    /// 生成显示器排列签名（用于稳定性检测）
    func generateSignature(for displays: [DisplayInfo]) -> String {
        let sorted = displays.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        return sorted.map { "\($0.width)x\($0.height)@\($0.x),\($0.y)\($0.isMain ? "M" : "")" }.joined(separator: "|")
    }

    /// 处理显示器变化（带稳定性检测）
    /// - Parameter displays: 当前检测到的显示器列表
    /// - Parameter completion: 当排列稳定后的回调，返回匹配或创建的 Layout
    func handleDisplayChange(
        displays: [DisplayInfo],
        preserving displayLayoutSignatures: Set<String> = [],
        completion: ((DisplayLayout) -> Void)? = nil
    ) {
        let newSignature = generateSignature(for: displays)

        // 如果签名与上次相同，增加稳定计数
        if newSignature == pendingSignature {
            stableCount += 1
        } else {
            // 签名变化，重置计数
            pendingSignature = newSignature
            pendingDisplays = displays
            stableCount = 1
        }

        // 取消之前的定时器
        stabilityTimer?.invalidate()

        // 检查是否达到稳定阈值
        if stableCount >= requiredStableCount {
            // 已稳定，执行匹配或创建
            let layout = matchOrCreateLayout(
                for: displays,
                preserving: displayLayoutSignatures
            )
            resetStabilityState()
            completion?(layout)
        } else {
            // 未稳定，设置定时器继续检测
            stabilityTimer = Timer.scheduledTimer(withTimeInterval: stabilityCheckInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                // 超时后，如果有待处理的显示器，强制处理
                if !self.pendingDisplays.isEmpty {
                    let layout = self.matchOrCreateLayout(
                        for: self.pendingDisplays,
                        preserving: displayLayoutSignatures
                    )
                    self.resetStabilityState()
                    completion?(layout)
                }
            }
        }
    }

    /// 重置稳定性检测状态
    private func resetStabilityState() {
        pendingSignature = nil
        stableCount = 0
        pendingDisplays = []
        stabilityTimer?.invalidate()
        stabilityTimer = nil
    }

    /// 根据当前显示器自动匹配或创建配置（内部方法，不带稳定性检测）
    func matchOrCreateLayout(
        for displays: [DisplayInfo],
        preserving displayLayoutSignatures: Set<String> = []
    ) -> DisplayLayout {
        // 尝试匹配现有配置
        if let matchedIndex = layouts.firstIndex(where: { $0.matches(displays: displays) }) {
            currentLayoutID = layouts[matchedIndex].id
            pruneLayouts(preserving: displayLayoutSignatures)
            save()
            return layouts[matchedIndex]
        }

        // 创建新配置
        let layout = DisplayLayout(
            name: generateLayoutName(for: displays),
            displays: displays,
            isGeneratedName: true
        )
        layouts.append(layout)
        currentLayoutID = layout.id
        pruneLayouts(preserving: displayLayoutSignatures)
        save()

        return layouts.first(where: { $0.id == layout.id }) ?? layout
    }

    /// 生成排列名称
    private func generateLayoutName(for displays: [DisplayInfo]) -> String {
        DisplayLayout.defaultLayoutName(displayCount: displays.count)
    }

    /// 重命名排列
    func renameLayout(_ layout: DisplayLayout, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = layouts.firstIndex(where: { $0.id == layout.id }) else {
            return
        }
        layouts[index].name = trimmedName
        layouts[index].customName = trimmedName
        layouts[index].modifiedAt = Date()
        save()
    }

    /// 删除排列
    func deleteLayout(_ layout: DisplayLayout) {
        guard let existingLayout = layouts.first(where: { $0.id == layout.id }) else { return }
        guard LayoutSidebarRules.canDeleteLayout(
            layoutCount: layouts.count,
            currentLayoutID: currentLayoutID,
            targetLayoutID: existingLayout.id,
            isLocked: existingLayout.isLocked
        ) else {
            return
        }

        layouts.removeAll { $0.id == layout.id }
        if currentLayoutID == layout.id {
            currentLayoutID = nil
        }
        save()
    }

    func setLayoutLocked(_ layout: DisplayLayout, isLocked: Bool) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[index].isLocked = isLocked
        layouts[index].modifiedAt = Date()
        save()
    }

    func toggleLayoutLock(_ layout: DisplayLayout) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[index].isLocked.toggle()
        layouts[index].modifiedAt = Date()
        save()
    }

    func renameDisplay(in layoutID: UUID, displayLayoutKey: DisplayLayoutKey, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let layoutIndex = layouts.firstIndex(where: { $0.id == layoutID }),
              let snapshotIndex = layouts[layoutIndex].displaySnapshots.firstIndex(where: { $0.layoutKey == displayLayoutKey }) else {
            return
        }

        layouts[layoutIndex].displaySnapshots[snapshotIndex].customName = trimmedName
        layouts[layoutIndex].modifiedAt = Date()
        save()
    }

    // MARK: - 传送门管理

    /// 为当前排列添加传送门
    @MainActor
    func addPortal(_ portal: PortalPair) {
        guard let id = currentLayoutID,
              let index = layouts.firstIndex(where: { $0.id == id }) else { return }

        layouts[index].portals.append(portal)
        layouts[index].modifiedAt = Date()
        save()

        // 同步到 PortalService
        syncToPortalService()
    }

    /// 更新传送门
    @MainActor
    func updatePortal(_ portal: PortalPair) {
        guard let id = currentLayoutID,
              let layoutIndex = layouts.firstIndex(where: { $0.id == id }),
              let portalIndex = layouts[layoutIndex].portals.firstIndex(where: { $0.id == portal.id }) else { return }

        layouts[layoutIndex].portals[portalIndex] = portal
        layouts[layoutIndex].modifiedAt = Date()
        save()

        syncToPortalService()
    }

    /// 删除传送门
    @MainActor
    func removePortal(id portalID: UUID) {
        guard let layoutID = currentLayoutID,
              let layoutIndex = layouts.firstIndex(where: { $0.id == layoutID }) else { return }

        layouts[layoutIndex].portals.removeAll { $0.id == portalID }
        layouts[layoutIndex].modifiedAt = Date()
        save()

        syncToPortalService()
    }

    /// 切换传送门启用状态
    @MainActor
    func togglePortal(id portalID: UUID) {
        guard let layoutID = currentLayoutID,
              let layoutIndex = layouts.firstIndex(where: { $0.id == layoutID }),
              let portalIndex = layouts[layoutIndex].portals.firstIndex(where: { $0.id == portalID }) else { return }

        layouts[layoutIndex].portals[portalIndex].isEnabled.toggle()
        layouts[layoutIndex].modifiedAt = Date()
        save()

        syncToPortalService()
    }

    /// 获取当前排列的传送门列表
    var currentPortals: [PortalPair] {
        currentLayout?.portals ?? []
    }

    /// 同步当前排列的传送门到 PortalService
    @MainActor
    func syncToPortalService() {
        PortalService.shared.portals = currentPortals
        PortalService.shared.save()
    }

    /// 从 PortalService 同步传送门到当前排列
    @MainActor
    func syncFromPortalService() {
        guard let id = currentLayoutID,
              let index = layouts.firstIndex(where: { $0.id == id }) else { return }

        layouts[index].portals = PortalService.shared.portals
        layouts[index].modifiedAt = Date()
        save()
    }
}
