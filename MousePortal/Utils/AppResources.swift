import Foundation

enum AppResources {
    static let bundle: Bundle = {
        let bundleName = "MousePortal_MousePortal.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
            Bundle.main.bundleURL.appendingPathComponent(bundleName)
        ].compactMap { $0 }

        for url in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return Bundle.module
    }()
}
