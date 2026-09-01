import Foundation

enum AppVersion {
    static let current = "1.1.0"
    static let build = "20"

    static var displayVersion: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return current
    }

    static var windowTitle: String {
        "\(L("app.title")) v\(displayVersion)"
    }
}
