import Foundation
import CoreGraphics

/// 传送门边缘位置
enum PortalEdge: String, Codable, CaseIterable {
    case top
    case bottom
    case left
    case right

    /// 本地化名称（用于 UI 显示）
    var localizedName: String {
        switch self {
        case .top: return L("edge.top")
        case .bottom: return L("edge.bottom")
        case .left: return L("edge.left")
        case .right: return L("edge.right")
        }
    }
}

/// 传送门线条
struct PortalLine: Codable, Identifiable, Equatable {
    let id: UUID
    var displayLayoutKey: DisplayLayoutKey?  // 新格式：布局标识
    var legacyDisplayID: UInt32?             // 旧格式：仅用于迁移
    var edge: PortalEdge
    var startOffset: CGFloat  // 沿边缘的起始偏移（像素）
    var endOffset: CGFloat    // 沿边缘的结束偏移（像素）

    // 新的初始化方法
    init(displayLayoutKey: DisplayLayoutKey, edge: PortalEdge, startOffset: CGFloat, endOffset: CGFloat) {
        self.id = UUID()
        self.displayLayoutKey = displayLayoutKey
        self.legacyDisplayID = nil
        self.edge = edge
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    // 兼容旧代码的初始化方法（标记为废弃）
    @available(*, deprecated, message: "Use init(displayLayoutKey:...) instead")
    init(displayID: UInt32, edge: PortalEdge, startOffset: CGFloat, endOffset: CGFloat) {
        self.id = UUID()
        self.displayLayoutKey = nil
        self.legacyDisplayID = displayID
        self.edge = edge
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    /// 线条长度
    var length: CGFloat {
        abs(endOffset - startOffset)
    }

    /// 向后兼容的 displayID 属性（废弃，仅用于过渡期）
    @available(*, deprecated, message: "Use displayLayoutKey instead")
    var displayID: UInt32 {
        get { legacyDisplayID ?? 0 }
        set { legacyDisplayID = newValue }
    }

    /// 获取线条在屏幕坐标系中的起点
    func startPoint(in bounds: CGRect) -> CGPoint {
        switch edge {
        case .top:
            return CGPoint(x: bounds.minX + startOffset, y: bounds.minY)
        case .bottom:
            return CGPoint(x: bounds.minX + startOffset, y: bounds.maxY)
        case .left:
            return CGPoint(x: bounds.minX, y: bounds.minY + startOffset)
        case .right:
            return CGPoint(x: bounds.maxX, y: bounds.minY + startOffset)
        }
    }

    /// 获取线条在屏幕坐标系中的终点
    func endPoint(in bounds: CGRect) -> CGPoint {
        switch edge {
        case .top:
            return CGPoint(x: bounds.minX + endOffset, y: bounds.minY)
        case .bottom:
            return CGPoint(x: bounds.minX + endOffset, y: bounds.maxY)
        case .left:
            return CGPoint(x: bounds.minX, y: bounds.minY + endOffset)
        case .right:
            return CGPoint(x: bounds.maxX, y: bounds.minY + endOffset)
        }
    }

    // MARK: - Codable（支持新旧格式）

    enum CodingKeys: String, CodingKey {
        case id
        case displayLayoutKey
        case displayID  // 旧格式
        case edge
        case startOffset
        case endOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.edge = try container.decode(PortalEdge.self, forKey: .edge)
        self.startOffset = try container.decode(CGFloat.self, forKey: .startOffset)
        self.endOffset = try container.decode(CGFloat.self, forKey: .endOffset)

        // 尝试解码新格式
        if let layoutKey = try container.decodeIfPresent(DisplayLayoutKey.self, forKey: .displayLayoutKey) {
            self.displayLayoutKey = layoutKey
            self.legacyDisplayID = nil
        }
        // 回退到旧格式
        else if let displayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID) {
            self.displayLayoutKey = nil
            self.legacyDisplayID = displayID
        }
        else {
            throw DecodingError.dataCorruptedError(forKey: .displayLayoutKey, in: container, debugDescription: "Neither displayLayoutKey nor displayID found")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(edge, forKey: .edge)
        try container.encode(startOffset, forKey: .startOffset)
        try container.encode(endOffset, forKey: .endOffset)

        // 只编码新格式
        if let layoutKey = displayLayoutKey {
            try container.encode(layoutKey, forKey: .displayLayoutKey)
        }
        // 如果只有旧格式（迁移期间），也要编码
        else if let displayID = legacyDisplayID {
            try container.encode(displayID, forKey: .displayID)
        }
    }

    static func == (lhs: PortalLine, rhs: PortalLine) -> Bool {
        lhs.displayLayoutKey == rhs.displayLayoutKey &&
        lhs.legacyDisplayID == rhs.legacyDisplayID &&
        lhs.edge == rhs.edge &&
        lhs.startOffset == rhs.startOffset &&
        lhs.endOffset == rhs.endOffset
    }
}

/// 传送门对
struct PortalPair: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var customName: String?
    var defaultNameIndex: Int?
    var lineA: PortalLine
    var lineB: PortalLine
    var isEnabled: Bool
    var isBidirectional: Bool  // 是否双向
    var color: PortalColor

    init(
        name: String,
        lineA: PortalLine,
        lineB: PortalLine,
        isEnabled: Bool = true,
        isBidirectional: Bool = true,
        color: PortalColor = .orange,
        isGeneratedName: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.customName = isGeneratedName ? nil : name
        self.defaultNameIndex = isGeneratedName ? Self.defaultNameIndex(from: name) : nil
        self.lineA = lineA
        self.lineB = lineB
        self.isEnabled = isEnabled
        self.isBidirectional = isBidirectional
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case customName
        case defaultNameIndex
        case lineA
        case lineB
        case isEnabled
        case isBidirectional
        case color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lineA = try container.decode(PortalLine.self, forKey: .lineA)
        lineB = try container.decode(PortalLine.self, forKey: .lineB)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isBidirectional = try container.decodeIfPresent(Bool.self, forKey: .isBidirectional) ?? true
        color = try container.decodeIfPresent(PortalColor.self, forKey: .color) ?? .orange

        if container.contains(.customName) {
            customName = try container.decodeIfPresent(String.self, forKey: .customName)
            defaultNameIndex = try container.decodeIfPresent(Int.self, forKey: .defaultNameIndex)
        } else if let index = Self.defaultNameIndex(from: name) {
            customName = nil
            defaultNameIndex = index
        } else {
            customName = name
            defaultNameIndex = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encodeIfPresent(defaultNameIndex, forKey: .defaultNameIndex)
        try container.encode(lineA, forKey: .lineA)
        try container.encode(lineB, forKey: .lineB)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isBidirectional, forKey: .isBidirectional)
        try container.encode(color, forKey: .color)
    }

    var displayName: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return Self.defaultName(index: defaultNameIndex ?? Self.defaultNameIndex(from: name) ?? 1)
    }

    mutating func rename(to newName: String, preservingGeneratedName: Bool) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName

        if preservingGeneratedName, let index = Self.defaultNameIndex(from: trimmedName) {
            customName = nil
            defaultNameIndex = index
        } else {
            customName = trimmedName
            defaultNameIndex = nil
        }
    }

    static func defaultName(index: Int) -> String {
        L("portal.default_name %lld", index)
    }

    static func defaultNameIndex(from name: String) -> Int? {
        for index in decimalNumbers(in: name) where localizedDefaultNames(index: index).contains(name) {
            return index
        }
        return nil
    }

    private static func localizedDefaultNames(index: Int) -> Set<String> {
        var names = Set<String>()
        names.insert(defaultName(index: index))

        let lprojURLs = AppResources.bundle.urls(forResourcesWithExtension: "lproj", subdirectory: nil) ?? []
        for url in lprojURLs {
            guard let bundle = Bundle(url: url) else { continue }
            names.insert(defaultName(index: index, bundle: bundle))
        }
        return names
    }

    private static func defaultName(index: Int, bundle: Bundle) -> String {
        let format = bundle.localizedString(forKey: "portal.default_name %lld", value: nil, table: nil)
        return String(format: format, index)
    }

    private static func decimalNumbers(in text: String) -> [Int] {
        var numbers: [Int] = []
        var current = ""

        for scalar in text.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                if let number = Int(current) {
                    numbers.append(number)
                }
                current = ""
            }
        }

        if !current.isEmpty, let number = Int(current) {
            numbers.append(number)
        }

        return numbers
    }

    /// 计算从线A穿越到线B的目标位置
    func calculateTargetPosition(from point: CGPoint, lineABounds: CGRect, lineBBounds: CGRect) -> CGPoint? {
        let startA = lineA.startPoint(in: lineABounds)
        let endA = lineA.endPoint(in: lineABounds)
        let lineADeltaY = endA.y - startA.y
        let lineADeltaX = endA.x - startA.x

        // 计算点在线A上的比例
        let ratio: CGFloat
        if lineA.edge == .left || lineA.edge == .right {
            // 垂直线
            guard lineADeltaY != 0 else { return nil }
            ratio = (point.y - startA.y) / lineADeltaY
        } else {
            // 水平线
            guard lineADeltaX != 0 else { return nil }
            ratio = (point.x - startA.x) / lineADeltaX
        }

        guard ratio >= 0 && ratio <= 1 else { return nil }

        // 计算线B上的对应位置
        let startB = lineB.startPoint(in: lineBBounds)
        let endB = lineB.endPoint(in: lineBBounds)

        let targetX: CGFloat
        let targetY: CGFloat

        if lineB.edge == .left || lineB.edge == .right {
            targetX = startB.x + (lineB.edge == .left ? 5 : -5)  // 偏移一点避免立即触发
            targetY = startB.y + ratio * (endB.y - startB.y)
        } else {
            targetX = startB.x + ratio * (endB.x - startB.x)
            targetY = startB.y + (lineB.edge == .top ? 5 : -5)
        }

        return CGPoint(x: targetX, y: targetY)
    }

    static func == (lhs: PortalPair, rhs: PortalPair) -> Bool {
        lhs.name == rhs.name &&
        lhs.customName == rhs.customName &&
        lhs.defaultNameIndex == rhs.defaultNameIndex &&
        lhs.lineA == rhs.lineA &&
        lhs.lineB == rhs.lineB &&
        lhs.isEnabled == rhs.isEnabled &&
        lhs.isBidirectional == rhs.isBidirectional &&
        lhs.color == rhs.color
    }
}

/// 传送门颜色（避免与 UI 颜色冲突：绿色=共享边缘，蓝色=主显示器，灰色=外接显示器）
enum PortalColor: String, Codable, CaseIterable {
    case orange
    case purple
    case pink
    case teal
    case yellow
    case red

    var color: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .orange: return (1.0, 0.5, 0.0)
        case .purple: return (0.6, 0.2, 0.8)
        case .pink: return (1.0, 0.4, 0.6)
        case .teal: return (0.0, 0.7, 0.7)
        case .yellow: return (0.9, 0.8, 0.0)
        case .red: return (0.9, 0.2, 0.2)
        }
    }

    /// 本地化名称
    var localizedName: String {
        switch self {
        case .orange: return L("color.orange")
        case .purple: return L("color.purple")
        case .pink: return L("color.pink")
        case .teal: return L("color.teal")
        case .yellow: return L("color.yellow")
        case .red: return L("color.red")
        }
    }
}

/// 传送门触发模式
enum PortalTriggerMode: String, Codable {
    case automatic  // 自动触发
    case withKey    // 按键触发

    var localizedName: String {
        switch self {
        case .automatic: return L("trigger.automatic")
        case .withKey: return L("trigger.with_key")
        }
    }
}

/// 传送门按键触发所需的修饰键
enum PortalTriggerKey: String, Codable, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift

    var id: String { rawValue }

    var flagsMask: UInt64 {
        switch self {
        case .option:
            return UInt64(CGEventFlags.maskAlternate.rawValue)
        case .command:
            return UInt64(CGEventFlags.maskCommand.rawValue)
        case .control:
            return UInt64(CGEventFlags.maskControl.rawValue)
        case .shift:
            return UInt64(CGEventFlags.maskShift.rawValue)
        }
    }

    var displayTitle: String {
        switch self {
        case .option:
            return "⌥ Option"
        case .command:
            return "⌘ Command"
        case .control:
            return "⌃ Control"
        case .shift:
            return "⇧ Shift"
        }
    }
}
