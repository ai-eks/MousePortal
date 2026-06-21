import Foundation

/// 配置方案模型
struct ConfigProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var hotkeyConfigs: [HotkeyConfig]
    var portals: [PortalPair]
    var triggerMode: PortalTriggerMode
    var triggerKey: PortalTriggerKey
    var hotkeyGlobalEnabled: Bool
    var portalGlobalEnabled: Bool
    var showMenuBarIcon: Bool
    var createdAt: Date
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hotkeyConfigs
        case portals
        case triggerMode
        case triggerKey
        case hotkeyGlobalEnabled
        case portalGlobalEnabled
        case showMenuBarIcon
        case createdAt
        case modifiedAt
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.hotkeyConfigs = []
        self.portals = []
        self.triggerMode = .automatic
        self.triggerKey = .option
        self.hotkeyGlobalEnabled = true
        self.portalGlobalEnabled = true
        self.showMenuBarIcon = true
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.hotkeyConfigs = try container.decode([HotkeyConfig].self, forKey: .hotkeyConfigs)
        self.portals = try container.decode([PortalPair].self, forKey: .portals)
        self.triggerMode = try container.decode(PortalTriggerMode.self, forKey: .triggerMode)
        self.triggerKey = try container.decodeIfPresent(PortalTriggerKey.self, forKey: .triggerKey) ?? .option
        self.hotkeyGlobalEnabled = try container.decode(Bool.self, forKey: .hotkeyGlobalEnabled)
        self.portalGlobalEnabled = try container.decode(Bool.self, forKey: .portalGlobalEnabled)
        self.showMenuBarIcon = try container.decode(Bool.self, forKey: .showMenuBarIcon)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(hotkeyConfigs, forKey: .hotkeyConfigs)
        try container.encode(portals, forKey: .portals)
        try container.encode(triggerMode, forKey: .triggerMode)
        try container.encode(triggerKey, forKey: .triggerKey)
        try container.encode(hotkeyGlobalEnabled, forKey: .hotkeyGlobalEnabled)
        try container.encode(portalGlobalEnabled, forKey: .portalGlobalEnabled)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }

    /// 从当前设置创建方案
    @MainActor
    static func fromCurrentSettings(name: String) -> ConfigProfile {
        var profile = ConfigProfile(name: name)
        profile.hotkeyConfigs = HotkeyConfigStore.shared.configs
        profile.portals = PortalService.shared.portals
        profile.triggerMode = PortalService.shared.triggerMode
        profile.triggerKey = PortalService.shared.triggerKey
        profile.hotkeyGlobalEnabled = HotkeyConfigStore.shared.globalEnabled
        if UserDefaults.standard.object(forKey: "portalEnabled") != nil {
            profile.portalGlobalEnabled = UserDefaults.standard.bool(forKey: "portalEnabled")
        } else {
            profile.portalGlobalEnabled = true
        }

        if UserDefaults.standard.object(forKey: "showMenuBarIcon") != nil {
            profile.showMenuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        } else {
            profile.showMenuBarIcon = true
        }
        return profile
    }

    /// 应用此方案到当前设置
    @MainActor
    func apply() {
        HotkeyConfigStore.shared.configs = hotkeyConfigs
        HotkeyConfigStore.shared.globalEnabled = hotkeyGlobalEnabled
        HotkeyConfigStore.shared.save()

        PortalService.shared.portals = portals
        PortalService.shared.triggerMode = triggerMode
        PortalService.shared.triggerKey = triggerKey
        PortalService.shared.save()

        UserDefaults.standard.set(portalGlobalEnabled, forKey: "portalEnabled")
        UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
    }
}

/// 配置服务：管理多个配置方案
@MainActor
class ConfigService: ObservableObject {
    static let shared = ConfigService()

    @Published var profiles: [ConfigProfile] = []
    @Published var currentProfileID: UUID?
    @Published var iCloudSyncEnabled: Bool = false

    private let profilesKey = "configProfiles"
    private let currentProfileKey = "currentProfileID"
    private let iCloudSyncKey = "iCloudSyncEnabled"

    #if ENABLE_ICLOUD_SYNC
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    #endif

    private init() {
        load()
        #if ENABLE_ICLOUD_SYNC
        setupiCloudSync()
        #endif
    }

    // MARK: - Local Storage

    func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let profiles = try? JSONDecoder().decode([ConfigProfile].self, from: data) {
            self.profiles = profiles
        }

        if let idString = UserDefaults.standard.string(forKey: currentProfileKey),
           let id = UUID(uuidString: idString) {
            currentProfileID = id
        }

        #if ENABLE_ICLOUD_SYNC
        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: iCloudSyncKey)
        #else
        iCloudSyncEnabled = false
        #endif
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }

        if let id = currentProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: currentProfileKey)
        }

        UserDefaults.standard.set(iCloudSyncEnabled, forKey: iCloudSyncKey)

        #if ENABLE_ICLOUD_SYNC
        if iCloudSyncEnabled {
            syncToiCloud()
        }
        #endif
    }

    // MARK: - Profile Management

    var currentProfile: ConfigProfile? {
        profiles.first { $0.id == currentProfileID }
    }

    func createProfile(name: String) -> ConfigProfile {
        let profile = ConfigProfile.fromCurrentSettings(name: name)
        profiles.append(profile)
        currentProfileID = profile.id
        save()
        return profile
    }

    func updateCurrentProfile() {
        guard let id = currentProfileID,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let existing = profiles[index]
        var updated = ConfigProfile.fromCurrentSettings(name: existing.name)
        updated.id = existing.id
        updated.createdAt = existing.createdAt
        updated.modifiedAt = Date()
        profiles[index] = updated
        save()
    }

    func selectProfile(_ profile: ConfigProfile) {
        currentProfileID = profile.id
        profile.apply()
        save()
    }

    func deleteProfile(_ profile: ConfigProfile) {
        profiles.removeAll { $0.id == profile.id }
        if currentProfileID == profile.id {
            currentProfileID = profiles.first?.id
        }
        save()
    }

    func renameProfile(_ profile: ConfigProfile, to newName: String) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].name = newName
            profiles[index].modifiedAt = Date()
            save()
        }
    }

    // MARK: - iCloud Sync

    #if ENABLE_ICLOUD_SYNC
    private func setupiCloudSync() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleiCloudChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore
        )

        iCloudStore.synchronize()
    }

    func syncToiCloud() {
        guard iCloudSyncEnabled else { return }

        if let data = try? JSONEncoder().encode(profiles) {
            iCloudStore.set(data, forKey: profilesKey)
            iCloudStore.synchronize()
        }
    }

    @objc private func handleiCloudChange(_ notification: Notification) {
        guard iCloudSyncEnabled else { return }

        if let data = iCloudStore.data(forKey: profilesKey),
           let cloudProfiles = try? JSONDecoder().decode([ConfigProfile].self, from: data) {
            // 合并策略：以最后修改时间为准
            mergeProfiles(cloudProfiles)
        }
    }

    private func mergeProfiles(_ cloudProfiles: [ConfigProfile]) {
        var merged = profiles

        for cloudProfile in cloudProfiles {
            if let localIndex = merged.firstIndex(where: { $0.id == cloudProfile.id }) {
                // 比较修改时间
                if cloudProfile.modifiedAt > merged[localIndex].modifiedAt {
                    merged[localIndex] = cloudProfile
                }
            } else {
                merged.append(cloudProfile)
            }
        }

        profiles = merged
        save()
    }
    #endif
}
