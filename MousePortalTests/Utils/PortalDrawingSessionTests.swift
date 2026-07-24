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
        session.hasValidationError = true

        session.startDrawing()

        XCTAssertTrue(session.isDrawingMode)
        XCTAssertEqual(session.currentStep, .drawingLineA)
        XCTAssertNil(session.tempLineA)
        XCTAssertNil(session.tempLineB)
        XCTAssertNil(session.dragStart)
        XCTAssertNil(session.dragEnd)
        XCTAssertEqual(session.portalName, "")
        XCTAssertFalse(session.hasValidationError)
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

    func testHandleDragEndedRejectsOverlappingLineOnSameDisplayEdge() {
        var session = PortalDrawingSession()
        session.startDrawing()

        XCTAssertFalse(drawLine(from: 10, to: 60, in: &session))
        XCTAssertFalse(drawLine(from: 90, to: 40, in: &session))
        XCTAssertEqual(session.currentStep, .drawingLineB)
        XCTAssertNil(session.tempLineB)
        XCTAssertFalse(session.canCreatePortal)
        XCTAssertTrue(session.hasValidationError)
        XCTAssertEqual(session.stepInstructions, L("portal.error_lines_overlap"))

        session.handleDragChanged(start: .zero, end: CGPoint(x: 0, y: 20))
        XCTAssertFalse(session.hasValidationError)
    }

    func testHandleDragEndedRejectsLinesThatTouchAtEndpoint() {
        var session = PortalDrawingSession()
        session.startDrawing()

        XCTAssertFalse(drawLine(from: 10, to: 50, in: &session))
        XCTAssertFalse(drawLine(from: 50, to: 90, in: &session))
        XCTAssertEqual(session.currentStep, .drawingLineB)
        XCTAssertNil(session.tempLineB)
        XCTAssertTrue(session.hasValidationError)
    }

    func testHandleDragEndedAllowsSeparatedLinesOnSameDisplayEdge() {
        var session = PortalDrawingSession()
        session.startDrawing()

        XCTAssertFalse(drawLine(from: 10, to: 49, in: &session))
        XCTAssertTrue(drawLine(from: 50, to: 90, in: &session))
        XCTAssertEqual(session.currentStep, .naming)
        XCTAssertNotNil(session.tempLineB)
        XCTAssertFalse(session.hasValidationError)
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

    func testBuildPortalRejectsOverlappingLinesOnSameDisplayEdge() {
        var session = PortalDrawingSession()
        session.isDrawingMode = true
        session.currentStep = .naming
        session.tempLineA = sampleLine(edge: .left, startOffset: 10, endOffset: 70)
        session.tempLineB = sampleLine(edge: .left, startOffset: 50, endOffset: 90)
        session.portalName = "Portal 1"

        XCTAssertFalse(session.canCreatePortal)
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

    private func drawLine(
        from startOffset: CGFloat,
        to endOffset: CGFloat,
        in session: inout PortalDrawingSession
    ) -> Bool {
        let display = sampleDisplay()
        return session.handleDragEnded(
            start: CGPoint(x: 0, y: startOffset),
            end: CGPoint(x: 0, y: endOffset),
            in: PortalDrawingCanvasContext(
                scale: 1,
                offset: .zero,
                totalBounds: display.frame,
                displays: [display]
            ),
            nextPortalName: "Portal 1"
        )
    }

    private func sampleLine(
        edge: PortalEdge,
        startOffset: CGFloat = 10,
        endOffset: CGFloat = 90
    ) -> PortalLine {
        PortalLine(
            displayLayoutKey: sampleDisplay().layoutKey,
            edge: edge,
            startOffset: startOffset,
            endOffset: endOffset
        )
    }
}
