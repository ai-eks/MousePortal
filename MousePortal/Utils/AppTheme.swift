import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    static let storageKey = "appTheme"

    case system
    case light
    case dark

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            return L("theme.system")
        case .light:
            return L("theme.light")
        case .dark:
            return L("theme.dark")
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppTheme {
        guard let rawValue = defaults.string(forKey: storageKey),
              let theme = AppTheme(rawValue: rawValue) else {
            return .system
        }
        return theme
    }

    @MainActor
    func apply() {
        NSApplication.shared.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}
