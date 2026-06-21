import Foundation
import Carbon

extension Notification.Name {
    static let hotkeyConfigStoreDidChange = Notification.Name("HotkeyConfigStoreDidChange")
}

/// 快捷键配置模型
struct HotkeyConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var displayLayoutKey: DisplayLayoutKey?  // 新格式：稳定布局标识
    var legacyDisplayID: UInt32?             // 旧格式：显示器 ID（兼容迁移）
    var keyCode: UInt16
    var modifiers: UInt64  // CGEventFlags.rawValue
    var isEnabled: Bool
    var displayName: String

    init(displayLayoutKey: DisplayLayoutKey, displayID: UInt32, keyCode: UInt16 = 0, modifiers: UInt64 = 0, isEnabled: Bool = true, displayName: String = "") {
        self.id = UUID()
        self.displayLayoutKey = displayLayoutKey
        self.legacyDisplayID = displayID
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.displayName = displayName
    }

    // 兼容旧配置的初始化方法
    init(displayID: UInt32, keyCode: UInt16 = 0, modifiers: UInt64 = 0, isEnabled: Bool = true, displayName: String = "") {
        self.id = UUID()
        self.displayLayoutKey = nil
        self.legacyDisplayID = displayID
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.displayName = displayName
    }

    /// 兼容属性：当前绑定的 displayID
    var displayID: UInt32 {
        get { legacyDisplayID ?? 0 }
        set { legacyDisplayID = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayLayoutKey
        case displayID
        case keyCode
        case modifiers
        case isEnabled
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.displayLayoutKey = try container.decodeIfPresent(DisplayLayoutKey.self, forKey: .displayLayoutKey)
        self.legacyDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID)
        self.keyCode = try container.decode(UInt16.self, forKey: .keyCode)

        if let modifiers64 = try container.decodeIfPresent(UInt64.self, forKey: .modifiers) {
            self.modifiers = modifiers64
        } else if let modifiers32 = try container.decodeIfPresent(UInt32.self, forKey: .modifiers) {
            self.modifiers = UInt64(modifiers32)
        } else {
            self.modifiers = 0
        }

        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.displayName = try container.decode(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayLayoutKey, forKey: .displayLayoutKey)
        try container.encodeIfPresent(legacyDisplayID, forKey: .displayID)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(displayName, forKey: .displayName)
    }

    /// 默认快捷键：Control + 数字键
    static func defaultHotkey(for index: Int, display: DisplayInfo) -> HotkeyConfig {
        // 数字键 1-9 的 keyCode
        let numberKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1-9
        let keyCode = index < numberKeyCodes.count ? numberKeyCodes[index] : 0
        let controlModifier = UInt64(CGEventFlags.maskControl.rawValue)

        return HotkeyConfig(
            displayLayoutKey: display.layoutKey,
            displayID: display.id,
            keyCode: keyCode,
            modifiers: controlModifier,
            isEnabled: true,
            displayName: display.name
        )
    }

    /// 获取快捷键的显示字符串
    var shortcutString: String {
        var parts: [String] = []

        if modifiers & UInt64(CGEventFlags.maskControl.rawValue) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt64(CGEventFlags.maskAlternate.rawValue) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt64(CGEventFlags.maskShift.rawValue) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt64(CGEventFlags.maskCommand.rawValue) != 0 {
            parts.append("⌘")
        }

        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyCodeMap: [UInt16: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E",
            3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
            35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y",
            6: "Z",

            // Function Keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",

            // Special Keys
            49: "Space", 48: "Tab", 36: "Return",
            123: "←", 124: "→", 125: "↓", 126: "↑",

            // Punctuation
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 43: ",", 47: ".", 44: "/"
        ]
        return keyCodeMap[keyCode]
    }
}

/// 快捷键配置存储
class HotkeyConfigStore: ObservableObject {
    static let shared = HotkeyConfigStore()

    @Published var configs: [HotkeyConfig] = []
    @Published var globalEnabled: Bool = true

    private let userDefaultsKey = "hotkeyConfigs"
    private let globalEnabledKey = "hotkeyGlobalEnabled"

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let configs = try? JSONDecoder().decode([HotkeyConfig].self, from: data) {
            self.configs = configs
        }
        if UserDefaults.standard.object(forKey: globalEnabledKey) != nil {
            globalEnabled = UserDefaults.standard.bool(forKey: globalEnabledKey)
        }
        notifyDidChange()
    }

    func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(globalEnabled, forKey: globalEnabledKey)
        notifyDidChange()
    }

    func updateConfig(for displayID: UInt32, keyCode: UInt16, modifiers: UInt64) {
        if let index = configs.firstIndex(where: { $0.displayID == displayID }) {
            configs[index].keyCode = keyCode
            configs[index].modifiers = modifiers
            save()
        }
    }

    func toggleConfig(for displayID: UInt32) {
        if let index = configs.firstIndex(where: { $0.displayID == displayID }) {
            configs[index].isEnabled.toggle()
            save()
        }
    }

    func initializeDefaults(from displays: [DisplayInfo]) {
        var newConfigs: [HotkeyConfig] = []
        var usedConfigIDs: Set<UUID> = []

        for (index, display) in displays.enumerated() {
            let matchedIndex = configs.firstIndex { config in
                guard !usedConfigIDs.contains(config.id) else { return false }
                if let key = config.displayLayoutKey {
                    return key == display.layoutKey
                }
                return config.displayID == display.id
            }

            if let matchedIndex {
                var existing = configs[matchedIndex]
                existing.displayLayoutKey = display.layoutKey
                existing.displayID = display.id
                existing.displayName = display.name
                usedConfigIDs.insert(existing.id)
                newConfigs.append(existing)
            } else {
                newConfigs.append(HotkeyConfig.defaultHotkey(for: index, display: display))
            }
        }

        configs = newConfigs
        save()
    }

    func renameDisplay(displayLayoutKey: DisplayLayoutKey, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var didUpdate = false
        for index in configs.indices where configs[index].displayLayoutKey == displayLayoutKey {
            configs[index].displayName = trimmedName
            didUpdate = true
        }

        if didUpdate {
            save()
        }
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .hotkeyConfigStoreDidChange, object: self)
    }
}
