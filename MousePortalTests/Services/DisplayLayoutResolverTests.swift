import XCTest
import CoreGraphics
@testable import MousePortal

final class DisplayLayoutResolverTests: XCTestCase {

    func testResolveExactMatch() {
        let displays: [DisplayInfo] = [
            DisplayInfo(id: 111, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "主显示器"),
            DisplayInfo(id: 222, frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080), isMain: false, name: "外接显示器 1")
        ]

        let resolver = DisplayLayoutResolver(displays: displays)

        let key1 = DisplayLayoutKey(x: 0, y: 0, width: 2560, height: 1440)
        let key2 = DisplayLayoutKey(x: 2560, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(resolver.resolve(key1), 111)
        XCTAssertEqual(resolver.resolve(key2), 222)
    }

    func testResolveNoMatch() {
        let displays: [DisplayInfo] = [
            DisplayInfo(id: 111, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "主显示器")
        ]

        let resolver = DisplayLayoutResolver(displays: displays)
        let unknownKey = DisplayLayoutKey(x: 5000, y: 0, width: 1920, height: 1080)

        XCTAssertNil(resolver.resolve(unknownKey))
    }

    func testBuildLookupTable() {
        let displays: [DisplayInfo] = [
            DisplayInfo(id: 111, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "主显示器"),
            DisplayInfo(id: 222, frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080), isMain: false, name: "外接显示器 1")
        ]

        let resolver = DisplayLayoutResolver(displays: displays)
        let table = resolver.layoutToDisplayID

        XCTAssertEqual(table.count, 2)
    }

    func testResolveDisplayBounds() {
        let displays: [DisplayInfo] = [
            DisplayInfo(id: 111, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: true, name: "主显示器"),
            DisplayInfo(id: 222, frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080), isMain: false, name: "外接显示器 1")
        ]

        let resolver = DisplayLayoutResolver(displays: displays)
        let key = DisplayLayoutKey(x: 0, y: 0, width: 2560, height: 1440)

        let bounds = resolver.resolveBounds(key)

        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds!.width, 2560)
        XCTAssertEqual(bounds!.height, 1440)
    }

    func testDuplicateLayoutKeyKeepsFirstMapping() {
        let sharedFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let displays: [DisplayInfo] = [
            DisplayInfo(id: 111, frame: sharedFrame, isMain: true, name: "主显示器"),
            DisplayInfo(id: 222, frame: sharedFrame, isMain: false, name: "镜像显示器")
        ]

        let resolver = DisplayLayoutResolver(displays: displays)
        let key = DisplayLayoutKey(frame: sharedFrame)

        XCTAssertEqual(resolver.layoutToDisplayID.count, 1)
        XCTAssertEqual(resolver.resolve(key), 111)
    }
}
