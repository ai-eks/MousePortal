import XCTest
import CoreGraphics
@testable import MousePortal

final class PortalDrawingSessionTests: XCTestCase {
    func testStartDrawingResetsStateAndMovesToFirstStep() {
        var session = PortalDrawingSession()
        session.tempLineA = sampleLine(edge: .left)
        session.tempLineB = sampleLine(edge: .right)
        session.portalName = "Existing"
        session.currentStep = .naming
        session.isDrawingMode = false

        session.startDrawing()

        XCTAssertTrue(session.isDrawingMode)
        XCTAssertEqual(session.currentStep, .drawingLineA)
        XCTAssertNil(session.tempLineA)
        XCTAssertNil(session.tempLineB)
        XCTAssertNil(session.dragStart)
        XCTAssertNil(session.dragEnd)
        XCTAssertEqual(session.portalName, "")
    }

    func testHandleDragEndedTransitionsToNamingAfterSecondLine() {
        var session = PortalDrawingSession()
        let display = sampleDisplay()
        let context = PortalDrawingCanvasContext(
            scale: 1,
            offset: .zero,
            totalBounds: display.frame,
            displays: [display]
        )

        session.startDrawing()

        XCTAssertFalse(
            session.handleDragEnded(
                start: CGPoint(x: 0, y: 10),
                end: CGPoint(x: 0, y: 90),
                in: context,
                nextPortalName: "Portal 1"
            )
        )
        XCTAssertEqual(session.currentStep, .drawingLineB)
        XCTAssertNotNil(session.tempLineA)
        XCTAssertNil(session.tempLineB)
        XCTAssertFalse(session.isNamingPortal)

        XCTAssertTrue(
            session.handleDragEnded(
                start: CGPoint(x: 100, y: 15),
                end: CGPoint(x: 100, y: 85),
                in: context,
                nextPortalName: "Portal 1"
            )
        )
        XCTAssertEqual(session.currentStep, .naming)
        XCTAssertNotNil(session.tempLineB)
        XCTAssertEqual(session.portalName, "Portal 1")
        XCTAssertTrue(session.isNamingPortal)
        XCTAssertTrue(session.canCreatePortal)
    }

    func testBuildPortalTrimsNameAndResetsSession() {
        var session = PortalDrawingSession()
        session.isDrawingMode = true
        session.currentStep = .naming
        session.tempLineA = sampleLine(edge: .left)
        session.tempLineB = sampleLine(edge: .right)
        session.portalName = "  Portal 1  "

        let portal = session.buildPortal(color: .teal)

        XCTAssertEqual(portal?.name, "Portal 1")
        XCTAssertEqual(portal?.color, .teal)
        XCTAssertEqual(session.currentStep, .idle)
        XCTAssertFalse(session.isDrawingMode)
        XCTAssertNil(session.tempLineA)
        XCTAssertNil(session.tempLineB)
        XCTAssertEqual(session.portalName, "")
    }

    func testBuildPortalRejectsWhitespaceOnlyName() {
        var session = PortalDrawingSession()
        session.isDrawingMode = true
        session.currentStep = .naming
        session.tempLineA = sampleLine(edge: .left)
        session.tempLineB = sampleLine(edge: .right)
        session.portalName = "   "

        XCTAssertNil(session.buildPortal(color: .orange))
        XCTAssertTrue(session.isDrawingMode)
        XCTAssertEqual(session.currentStep, .naming)
    }

    private func sampleDisplay() -> DisplayInfo {
        DisplayInfo(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isMain: true,
            name: "Main"
        )
    }

    private func sampleLine(edge: PortalEdge) -> PortalLine {
        PortalLine(
            displayLayoutKey: sampleDisplay().layoutKey,
            edge: edge,
            startOffset: 10,
            endOffset: 90
        )
    }
}
