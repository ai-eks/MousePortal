import Foundation
import SwiftUI

/// 支持的语言
enum AppLanguage: String, CaseIterable, Identifiable {
    // 现有语言
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt-BR"
    case russian = "ru"
    // 新增语言
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case arabic = "ar"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case malay = "ms"

    var id: String { rawValue }

    /// 语言显示名称（用本地语言显示）
    var displayName: String {
        switch self {
        case .system: return LanguageService.shared.localizedString("language.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .portuguese: return "Português (Brasil)"
        case .russian: return "Русский"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .turkish: return "Türkçe"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        case .indonesian: return "Bahasa Indonesia"
        case .malay: return "Bahasa Melayu"
        }
    }

    /// 语言的英文名称（用于辅助显示）
    var englishName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .german: return "German"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese (Brazil)"
        case .russian: return "Russian"
        case .italian: return "Italian"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        }
    }
}

/// 语言服务：管理应用语言设置（支持即时切换）
class LanguageService: ObservableObject {
    static let shared = LanguageService()

    private let languageKey = "appLanguage"
    private static let fallbackLanguageCode = AppLanguage.english.rawValue
    private static let supportedLocalizationCodes = AppLanguage.allCases
        .filter { $0 != .system }
        .map(\.rawValue)

    /// 当前语言的 Bundle
    @Published private(set) var currentBundle: Bundle = AppResources.bundle

    /// 用于触发 UI 刷新的计数器
    @Published var refreshID: UUID = UUID()

    @Published var currentLanguage: AppLanguage {
        didSet {
            applyLanguage(currentLanguage)
        }
    }

    private init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
            self.currentBundle = Self.bundle(for: language)
        } else {
            self.currentLanguage = .system
            self.currentBundle = Self.bundle(for: .system)
        }
    }

    /// 获取指定语言的 Bundle
    private static func bundle(for language: AppLanguage) -> Bundle {
        let languageCode: String
        if language == .system {
            languageCode = resolvedSystemLanguageCode()
        } else {
            languageCode = language.rawValue
        }

        // 尝试多种可能的路径格式（SPM 会将文件夹名转为小写）
        let possibleCodes = [
            languageCode,
            languageCode.lowercased(),
            languageCode.replacingOccurrences(of: "-", with: "_"),
            languageCode.lowercased().replacingOccurrences(of: "-", with: "_")
        ]

        for code in possibleCodes {
            if let path = AppResources.bundle.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        // 回退到英语
        if let path = AppResources.bundle.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return AppResources.bundle
    }

    static func resolvedSystemLanguageCode(forPreferences preferences: [String] = Locale.preferredLanguages) -> String {
        Bundle.preferredLocalizations(
            from: supportedLocalizationCodes,
            forPreferences: preferences
        ).first ?? fallbackLanguageCode
    }

    /// 应用语言设置（即时生效）
    func applyLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)

        // 更新当前 Bundle
        currentBundle = Self.bundle(for: language)

        // 触发 UI 刷新
        refreshID = UUID()

        // 发送通知
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    /// 获取本地化字符串
    func localizedString(_ key: String) -> String {
        currentBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 获取带参数的本地化字符串
    func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let format = currentBundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, arguments: arguments)
    }

    /// 获取当前有效的语言代码
    var effectiveLanguageCode: String {
        if currentLanguage == .system {
            return Self.resolvedSystemLanguageCode()
        }
        return currentLanguage.rawValue
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}
