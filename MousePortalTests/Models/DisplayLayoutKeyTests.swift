import XCTest
import CoreGraphics
@testable import MousePortal

final class DisplayLayoutKeyTests: XCTestCase {

    func testInitFromFrame() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let key = DisplayLayoutKey(frame: frame)

        XCTAssertEqual(key.x, 0)
        XCTAssertEqual(key.y, 0)
        XCTAssertEqual(key.width, 2560)
        XCTAssertEqual(key.height, 1440)
    }

    func testEquality() {
        let key1 = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
        let key2 = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
        let key3 = DisplayLayoutKey(x: 1920, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }

    func testCodable() throws {
        let key = DisplayLayoutKey(x: 100, y: 200, width: 1920, height: 1080)

        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(DisplayLayoutKey.self, from: data)

        XCTAssertEqual(key, decoded)
    }

    func testHashable() {
        let key1 = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
        let key2 = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)

        var set = Set<DisplayLayoutKey>()
        set.insert(key1)
        set.insert(key2)

        XCTAssertEqual(set.count, 1, "相同布局的 key 应该去重")
    }

    func testDisplayInfoLayoutKey() {
        let display = DisplayInfo(
            id: 12345,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            isMain: true,
            name: "主显示器"
        )

        let expectedKey = DisplayLayoutKey(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(display.layoutKey, expectedKey)
    }
}
