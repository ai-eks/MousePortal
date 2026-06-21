import XCTest
import CoreGraphics
@testable import MousePortal

final class PortalLineTests: XCTestCase {

    let testBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let testLayoutKey = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - startPoint Tests

    func testStartPointLeftEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .left, startOffset: 100, endOffset: 500)
        let point = line.startPoint(in: testBounds)

        XCTAssertEqual(point.x, 0, "Left edge startPoint X should be at bounds.minX")
        XCTAssertEqual(point.y, 100, "Left edge startPoint Y should be bounds.minY + startOffset")
    }

    func testStartPointRightEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .right, startOffset: 100, endOffset: 500)
        let point = line.startPoint(in: testBounds)

        XCTAssertEqual(point.x, 1920, "Right edge startPoint X should be at bounds.maxX")
        XCTAssertEqual(point.y, 100, "Right edge startPoint Y should be bounds.minY + startOffset")
    }

    func testStartPointTopEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .top, startOffset: 200, endOffset: 800)
        let point = line.startPoint(in: testBounds)

        XCTAssertEqual(point.x, 200, "Top edge startPoint X should be bounds.minX + startOffset")
        XCTAssertEqual(point.y, 0, "Top edge startPoint Y should be at bounds.minY")
    }

    func testStartPointBottomEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .bottom, startOffset: 200, endOffset: 800)
        let point = line.startPoint(in: testBounds)

        XCTAssertEqual(point.x, 200, "Bottom edge startPoint X should be bounds.minX + startOffset")
        XCTAssertEqual(point.y, 1080, "Bottom edge startPoint Y should be at bounds.maxY")
    }

    // MARK: - endPoint Tests

    func testEndPointLeftEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .left, startOffset: 100, endOffset: 500)
        let point = line.endPoint(in: testBounds)

        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 500)
    }

    func testEndPointRightEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .right, startOffset: 100, endOffset: 500)
        let point = line.endPoint(in: testBounds)

        XCTAssertEqual(point.x, 1920)
        XCTAssertEqual(point.y, 500)
    }

    func testEndPointTopEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .top, startOffset: 200, endOffset: 800)
        let point = line.endPoint(in: testBounds)

        XCTAssertEqual(point.x, 800)
        XCTAssertEqual(point.y, 0)
    }

    func testEndPointBottomEdge() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .bottom, startOffset: 200, endOffset: 800)
        let point = line.endPoint(in: testBounds)

        XCTAssertEqual(point.x, 800)
        XCTAssertEqual(point.y, 1080)
    }

    // MARK: - length Tests

    func testLength() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .left, startOffset: 100, endOffset: 500)
        XCTAssertEqual(line.length, 400)
    }

    func testLengthReversed() {
        let line = PortalLine(displayLayoutKey: testLayoutKey, edge: .left, startOffset: 500, endOffset: 100)
        XCTAssertEqual(line.length, 400, "Length should be absolute value")
    }

    // MARK: - Offset Bounds

    func testStartPointWithOffsetAtBounds() {
        let boundsWithOffset = CGRect(x: 100, y: 200, width: 1920, height: 1080)
        let layoutKey = DisplayLayoutKey(x: 100, y: 200, width: 1920, height: 1080)
        let line = PortalLine(displayLayoutKey: layoutKey, edge: .left, startOffset: 50, endOffset: 100)
        let point = line.startPoint(in: boundsWithOffset)

        XCTAssertEqual(point.x, 100, "Should respect bounds origin X")
        XCTAssertEqual(point.y, 250, "Should be bounds.minY + startOffset")
    }

    // MARK: - Codable with migration

    func testDecodeLegacyDisplayID() throws {
        // 模拟旧格式的 JSON（使用 displayID）
        let legacyJSON = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "displayID": 12345,
            "edge": "left",
            "startOffset": 100,
            "endOffset": 500
        }
        """

        let data = legacyJSON.data(using: .utf8)!
        let line = try JSONDecoder().decode(PortalLine.self, from: data)

        // 旧格式解码后，displayLayoutKey 应该为 nil（需要运行时解析）
        XCTAssertNil(line.displayLayoutKey)
        XCTAssertEqual(line.legacyDisplayID, 12345)
    }

    func testEncodeNewFormat() throws {
        let layoutKey = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
        let line = PortalLine(displayLayoutKey: layoutKey, edge: .right, startOffset: 0, endOffset: 1080)

        let data = try JSONEncoder().encode(line)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("displayLayoutKey"))
        XCTAssertFalse(json.contains("\"displayID\""))
    }
}
