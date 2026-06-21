import Foundation

enum AppVersion {
    static let current = "1.0.0"
    static let build = "1"

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
