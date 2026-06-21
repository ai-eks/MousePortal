import XCTest
import CoreGraphics
@testable import MousePortal

final class PortalPairTests: XCTestCase {

    let layoutKey1 = DisplayLayoutKey(x: 0, y: 0, width: 1920, height: 1080)
    let layoutKey2 = DisplayLayoutKey(x: 1920, y: 0, width: 1920, height: 1080)
    private var originalLanguage: AppLanguage?

    override func setUp() {
        super.setUp()
        originalLanguage = LanguageService.shared.currentLanguage
    }

    override func tearDown() {
        if let originalLanguage {
            LanguageService.shared.applyLanguage(originalLanguage)
        }
        super.tearDown()
    }

    // MARK: - Display Name Tests

    func testLegacyDefaultPortalNameLocalizesDisplayName() throws {
        LanguageService.shared.applyLanguage(.english)
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "传送门 1",
          "lineA": {
            "id": "22222222-2222-2222-2222-222222222222",
            "displayLayoutKey": { "x": 0, "y": 0, "width": 1920, "height": 1080 },
            "edge": "right",
            "startOffset": 0,
            "endOffset": 1080
          },
          "lineB": {
            "id": "33333333-3333-3333-3333-333333333333",
            "displayLayoutKey": { "x": 1920, "y": 0, "width": 1920, "height": 1080 },
            "edge": "left",
            "startOffset": 0,
            "endOffset": 1080
          },
          "isEnabled": true,
          "isBidirectional": true,
          "color": "orange"
        }
        """.data(using: .utf8)!

        let portal = try JSONDecoder().decode(PortalPair.self, from: json)

        XCTAssertNil(portal.customName)
        XCTAssertEqual(portal.defaultNameIndex, 1)
        XCTAssertEqual(portal.displayName, "Portal 1")
    }

    func testCustomPortalNameDoesNotLocalize() {
        LanguageService.shared.applyLanguage(.english)
        let portal = PortalPair(name: "传送门 1", lineA: sampleLineA(), lineB: sampleLineB())

        XCTAssertEqual(portal.customName, "传送门 1")
        XCTAssertEqual(portal.displayName, "传送门 1")
    }

    // MARK: - calculateTargetPosition Tests

    func testCalculateTargetPositionHorizontalToHorizontal() {
        // 从显示器1右边缘 -> 显示器2左边缘
        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 0, endOffset: 1080)
        let lineB = PortalLine(displayLayoutKey: layoutKey2, edge: .left, startOffset: 0, endOffset: 1080)
        let portal = PortalPair(name: "Test", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

        let mousePoint = CGPoint(x: 1920, y: 540)
        let target = portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB)

        XCTAssertNotNil(target)
        XCTAssertEqual(target!.x, 1925, accuracy: 1)
        XCTAssertEqual(target!.y, 540, accuracy: 1)
    }

    func testCalculateTargetPositionVerticalToVertical() {
        let layoutKeyBottom = DisplayLayoutKey(x: 0, y: 1080, width: 1920, height: 1080)

        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .bottom, startOffset: 0, endOffset: 1920)
        let lineB = PortalLine(displayLayoutKey: layoutKeyBottom, edge: .top, startOffset: 0, endOffset: 1920)
        let portal = PortalPair(name: "Test", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 0, y: 1080, width: 1920, height: 1080)

        let mousePoint = CGPoint(x: 960, y: 1080)
        let target = portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB)

        XCTAssertNotNil(target)
        XCTAssertEqual(target!.x, 960, accuracy: 1)
        XCTAssertEqual(target!.y, 1085, accuracy: 1)
    }

    func testCalculateTargetPositionProportional() {
        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 0, endOffset: 1080)
        let lineB = PortalLine(displayLayoutKey: layoutKey2, edge: .left, startOffset: 270, endOffset: 810)
        let portal = PortalPair(name: "Test", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

        let mousePoint = CGPoint(x: 1920, y: 540)
        let target = portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB)

        XCTAssertNotNil(target)
        XCTAssertEqual(target!.y, 540, accuracy: 1)
    }

    func testCalculateTargetPositionOutOfRange() {
        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 100, endOffset: 500)
        let lineB = PortalLine(displayLayoutKey: layoutKey2, edge: .left, startOffset: 100, endOffset: 500)
        let portal = PortalPair(name: "Test", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

        let mousePoint = CGPoint(x: 1920, y: 50)
        let target = portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB)

        XCTAssertNil(target)
    }

    func testCalculateTargetPositionCrossEdgeTypes() {
        let layoutKeyOffset = DisplayLayoutKey(x: 2000, y: 0, width: 1920, height: 1080)

        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 0, endOffset: 1080)
        let lineB = PortalLine(displayLayoutKey: layoutKeyOffset, edge: .bottom, startOffset: 0, endOffset: 1920)
        let portal = PortalPair(name: "Test", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 2000, y: 0, width: 1920, height: 1080)

        let mousePoint = CGPoint(x: 1920, y: 270)
        let target = portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB)

        XCTAssertNotNil(target)
        XCTAssertEqual(target!.x, 2480, accuracy: 1)
    }

    func testCalculateTargetPositionReturnsNilForZeroLengthSourceLine() {
        let lineA = PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 300, endOffset: 300)
        let lineB = PortalLine(displayLayoutKey: layoutKey2, edge: .left, startOffset: 100, endOffset: 900)
        let portal = PortalPair(name: "Zero Length", lineA: lineA, lineB: lineB)

        let boundsA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boundsB = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let mousePoint = CGPoint(x: 1920, y: 300)

        XCTAssertNil(portal.calculateTargetPosition(from: mousePoint, lineABounds: boundsA, lineBBounds: boundsB))
    }

    private func sampleLineA() -> PortalLine {
        PortalLine(displayLayoutKey: layoutKey1, edge: .right, startOffset: 0, endOffset: 1080)
    }

    private func sampleLineB() -> PortalLine {
        PortalLine(displayLayoutKey: layoutKey2, edge: .left, startOffset: 0, endOffset: 1080)
    }
}
