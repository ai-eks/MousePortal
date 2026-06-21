import XCTest
import CoreGraphics
@testable import MousePortal

final class SharedEdgeTests: XCTestCase {

    // MARK: - Horizontal Adjacency Tests

    func testHorizontalAdjacentDisplays() {
        let left = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Left"
        )
        let right = DisplayInfo(
            id: 2,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            isMain: false,
            name: "Right"
        )

        XCTAssertEqual(left.rightEdge, right.leftEdge, "Displays should be adjacent")
    }

    func testVerticalAdjacentDisplays() {
        let top = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Top"
        )
        let bottom = DisplayInfo(
            id: 2,
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
            isMain: false,
            name: "Bottom"
        )

        XCTAssertEqual(top.bottomEdge, bottom.topEdge, "Displays should be adjacent")
    }

    func testPartialOverlapVertical() {
        let left = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Left"
        )
        let right = DisplayInfo(
            id: 2,
            frame: CGRect(x: 1920, y: 200, width: 1920, height: 1080),
            isMain: false,
            name: "Right"
        )

        let overlapTop = max(left.topEdge, right.topEdge)
        let overlapBottom = min(left.bottomEdge, right.bottomEdge)

        XCTAssertEqual(overlapTop, 200)
        XCTAssertEqual(overlapBottom, 1080)
        XCTAssertEqual(overlapBottom - overlapTop, 880, "Overlap should be 880 pixels")
    }

    func testNoOverlap() {
        let left = DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isMain: true,
            name: "Left"
        )
        let right = DisplayInfo(
            id: 2,
            frame: CGRect(x: 2000, y: 0, width: 1920, height: 1080),
            isMain: false,
            name: "Right"
        )

        let gap = right.leftEdge - left.rightEdge
        XCTAssertEqual(gap, 80, "Gap should be 80 pixels")
        XCTAssertGreaterThan(gap, 1, "Gap exceeds tolerance, no shared edge")
    }

    func testSharedEdgeCreation() {
        let edge = SharedEdge(
            from: 1,
            to: 2,
            start: CGPoint(x: 1920, y: 0),
            end: CGPoint(x: 1920, y: 1080)
        )

        XCTAssertEqual(edge.fromDisplayID, 1)
        XCTAssertEqual(edge.toDisplayID, 2)
        XCTAssertEqual(edge.start, CGPoint(x: 1920, y: 0))
        XCTAssertEqual(edge.end, CGPoint(x: 1920, y: 1080))
    }

    func testSharedEdgeEqualityUsesGeometryInsteadOfUUID() {
        let edgeA = SharedEdge(
            from: 1,
            to: 2,
            start: CGPoint(x: 1920, y: 100),
            end: CGPoint(x: 1920, y: 900)
        )
        let edgeB = SharedEdge(
            from: 1,
            to: 2,
            start: CGPoint(x: 1920, y: 100),
            end: CGPoint(x: 1920, y: 900)
        )

        XCTAssertEqual(edgeA, edgeB)
    }
}
