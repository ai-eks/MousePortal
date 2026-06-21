import XCTest
import Foundation

final class LocalizationKeysTests: XCTestCase {
    func testEnglishLocalizationContainsAllCodeReferencedKeys() throws {
        let codeKeys = try referencedLocalizationKeys()
        let englishKeys = try localeKeys(for: "en")

        XCTAssertEqual(codeKeys.subtracting(englishKeys), [])
    }

    func testAllLocalesMatchEnglishKeySet() throws {
        let englishKeys = try localeKeys(for: "en")

        for locale in try availableLocales() where locale != "en" {
            XCTAssertEqual(
                try localeKeys(for: locale),
                englishKeys,
                "Locale \(locale) does not match english key set"
            )
        }
    }

    func testEnglishLocalizationDoesNotContainUnusedKeys() throws {
        let codeKeys = try referencedLocalizationKeys()
        let englishKeys = try localeKeys(for: "en")

        XCTAssertEqual(englishKeys.subtracting(codeKeys), [])
    }

    private func referencedLocalizationKeys() throws -> Set<String> {
        let englishKeys = try localeKeys(for: "en")
        let sourceFiles = try swiftSourceFiles()

        var keys: Set<String> = []
        for file in sourceFiles {
            let contents = try String(contentsOf: file)

            for key in firstCaptureMatches(in: contents, pattern: #"(?:L|localizedString)\("([^"]+)""#) {
                keys.insert(key)
            }

            for candidate in firstCaptureMatches(in: contents, pattern: #""([^"\n]+)""#) {
                if englishKeys.contains(candidate) {
                    keys.insert(candidate)
                }
            }
        }

        return keys
    }

    private func availableLocales() throws -> [String] {
        let localeRoot = projectRootURL()
            .appending(path: "MousePortal")
            .appending(path: "Resources")
        let directories = try FileManager.default.contentsOfDirectory(
            at: localeRoot,
            includingPropertiesForKeys: nil
        )

        return directories
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func localeKeys(for locale: String) throws -> Set<String> {
        let stringsURL = projectRootURL()
            .appending(path: "MousePortal")
            .appending(path: "Resources")
            .appending(path: "\(locale).lproj")
            .appending(path: "Localizable.strings")
        let contents = try String(contentsOf: stringsURL)
        return Set(firstCaptureMatches(in: contents, pattern: #"^\s*"([^"]+)"\s*=\s*""#, options: [.anchorsMatchLines]))
    }

    private func swiftSourceFiles() throws -> [URL] {
        let sourceRoot = projectRootURL().appending(path: "MousePortal")
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )

        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            guard !file.path.contains("/Resources/") else { continue }
            files.append(file)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func firstCaptureMatches(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: string) else {
                return nil
            }
            return String(string[captureRange])
        }
    }
}
