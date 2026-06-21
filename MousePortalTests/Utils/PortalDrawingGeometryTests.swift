import XCTest
import CoreGraphics
@testable import MousePortal

final class PortalDrawingGeometryTests: XCTestCase {
    func testCanvasToScreenConvertsUsingScaleAndOffset() {
        let totalBounds = CGRect(x: -100, y: 50, width: 400, height: 200)
        let point = CGPoint(x: 250, y: 130)
        let scale: CGFloat = 2
        let offset = CGPoint(x: 40, y: 20)

        let result = PortalDrawingGeometry.canvasToScreen(point, scale: scale, offset: offset, totalBounds: totalBounds)

        XCTAssertEqual(result.x, 5, accuracy: 0.001)
        XCTAssertEqual(result.y, 105, accuracy: 0.001)
    }

    func testCreateLineFromDragUsesDisplayWithLargestOverlap() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, name: "Main"),
            DisplayInfo(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false, name: "Right")
        ]

        let line = PortalDrawingGeometry.createLineFromDrag(
            start: CGPoint(x: 1910, y: 200),
            end: CGPoint(x: 1950, y: 900),
            displays: displays
        )

        XCTAssertEqual(line?.displayLayoutKey, displays[1].layoutKey)
        XCTAssertEqual(line?.edge, .left)
    }

    func testFindNearestDisplayFallsBackWhenNoCandidateContainsMidpoint() {
        let displays = [
            DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isMain: true, name: "A"),
            DisplayInfo(id: 2, frame: CGRect(x: 500, y: 0, width: 100, height: 100), isMain: false, name: "B")
        ]

        let best = PortalDrawingGeometry.findBestDisplayForLine(
            start: CGPoint(x: 310, y: 20),
            end: CGPoint(x: 320, y: 30),
            displays: displays,
            tolerance: 0
        )

        XCTAssertEqual(best?.id, 2)
    }

    func testCalculateScaleAndOffsetCenterContent() {
        let totalBounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let size = CGSize(width: 600, height: 600)

        let scale = PortalDrawingGeometry.calculateScale(for: size, totalBounds: totalBounds)
        let offset = PortalDrawingGeometry.calculateOffset(for: size, scale: scale, totalBounds: totalBounds)

        XCTAssertEqual(scale, 0.48, accuracy: 0.001)
        XCTAssertEqual(offset.x, 60, accuracy: 0.001)
        XCTAssertEqual(offset.y, 180, accuracy: 0.001)
    }
}
