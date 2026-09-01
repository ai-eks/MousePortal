import XCTest
@testable import MousePortal

final class WindowLayoutEngineTests: XCTestCase {
    func testDisplaySelectionUsesLargestWindowIntersection() {
        let left = display(identity: "left", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let right = display(identity: "right", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))

        let selected = WindowLayoutEngine.display(
            containing: CGRect(x: 900, y: 100, width: 600, height: 500),
            from: [left, right]
        )

        XCTAssertEqual(selected?.identity.rawValue, "right")
    }

    func testDisplaySelectionReturnsNilForOffscreenWindow() {
        let display = display(identity: "main", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))

        XCTAssertNil(WindowLayoutEngine.display(
            containing: CGRect(x: 2000, y: 0, width: 300, height: 300),
            from: [display]
        ))
    }

    func testTargetFrameUsesRelativePositionOnMovedDisplay() {
        let targetDisplay = display(
            identity: "external",
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let placement = placement(
            displayIdentity: targetDisplay.identity,
            relativeX: 0.25,
            relativeY: 0.1,
            width: 800,
            height: 600
        )

        let frame = WindowLayoutEngine.targetFrame(for: placement, on: targetDisplay)

        XCTAssertEqual(frame.origin.x, -1440, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 108, accuracy: 0.001)
        XCTAssertEqual(frame.size.width, 800)
        XCTAssertEqual(frame.size.height, 600)
    }

    func testSavedFramePreservesUnclampedWindowPositionForPreview() {
        let savedDisplay = display(
            identity: "external",
            frame: CGRect(x: 1920, y: -200, width: 1600, height: 1000)
        )
        let placement = placement(
            displayIdentity: savedDisplay.identity,
            relativeX: 0.25,
            relativeY: 0.1,
            width: 900,
            height: 700
        )

        let frame = WindowLayoutEngine.savedFrame(for: placement, on: savedDisplay)

        XCTAssertEqual(frame, CGRect(x: 2320, y: -100, width: 900, height: 700))
    }

    func testTargetFrameClampsWindowToVisibleArea() {
        let targetDisplay = WindowDisplaySnapshot(
            identity: WindowDisplayIdentity(rawValue: "main"),
            frame: WindowRect(CGRect(x: 0, y: 0, width: 1200, height: 900)),
            visibleFrame: WindowRect(CGRect(x: 0, y: 24, width: 1200, height: 826)),
            isMain: true
        )
        let placement = placement(
            displayIdentity: targetDisplay.identity,
            relativeX: 0.9,
            relativeY: -0.2,
            width: 500,
            height: 1000
        )

        let frame = WindowLayoutEngine.targetFrame(for: placement, on: targetDisplay)

        XCTAssertEqual(frame, CGRect(x: 700, y: 24, width: 500, height: 826))
    }

    func testFrameMatchingAcceptsAccessibilityRoundingWithinTolerance() {
        let target = CGRect(x: 100, y: 200, width: 800, height: 600)
        let actual = CGRect(x: 101, y: 199, width: 799, height: 601)

        XCTAssertTrue(WindowLayoutEngine.framesMatch(actual, target: target))
    }

    func testFrameMatchingRejectsIncorrectSize() {
        let target = CGRect(x: 100, y: 200, width: 800, height: 600)
        let actual = CGRect(x: 100, y: 200, width: 810, height: 600)

        XCTAssertFalse(WindowLayoutEngine.framesMatch(actual, target: target))
    }

    func testFrameMatchingRejectsIncorrectPosition() {
        let target = CGRect(x: 100, y: 200, width: 800, height: 600)
        let actual = CGRect(x: 110, y: 200, width: 800, height: 600)

        XCTAssertFalse(WindowLayoutEngine.framesMatch(actual, target: target))
    }

    func testFrameMatchingRejectsMissingReadback() {
        let target = CGRect(x: 100, y: 200, width: 800, height: 600)

        XCTAssertFalse(WindowLayoutEngine.framesMatch(nil, target: target))
    }

    func testWindowMatchingPrefersDocumentOverPreviousIndex() {
        let placement = placement(
            documentURL: "file:///project/README.md",
            windowIndex: 0
        )
        let candidates = [
            candidate(documentURL: "file:///project/Other.md", windowIndex: 0),
            candidate(documentURL: "file:///project/README.md", windowIndex: 1)
        ]

        XCTAssertEqual(
            WindowLayoutEngine.bestMatchIndex(for: placement, candidates: candidates, excluding: []),
            1
        )
    }

    func testWindowMatchingPrefersRetainedRuntimeWindow() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.bestMatchIndex(
                for: placement,
                candidates: candidates,
                excluding: [],
                preferredIndex: 1
            ),
            1
        )
    }

    func testWindowMatchingFallsBackWhenRetainedRuntimeWindowWasAlreadyUsed() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.bestMatchIndex(
                for: placement,
                candidates: candidates,
                excluding: [1],
                preferredIndex: 1
            ),
            0
        )
    }

    func testWindowMatchingDoesNotReuseCandidate() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.bestMatchIndex(for: placement, candidates: candidates, excluding: [0]),
            1
        )
    }

    func testWindowMatchingRejectsNonstandardWindow() {
        let placement = placement()
        let candidates = [candidate(subrole: "AXDialog")]

        XCTAssertNil(WindowLayoutEngine.bestMatchIndex(
            for: placement,
            candidates: candidates,
            excluding: []
        ))
    }

    func testWindowMatchingRejectsUnrelatedFallbackWindow() {
        let placement = placement(
            documentURL: "file:///project/README.md",
            windowIndex: 0
        )
        let candidates = [WindowMatchCandidate(
            windowTitle: "Other",
            documentURL: "file:///project/Other.md",
            windowIdentifier: "other-window",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            windowIndex: 0,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )]

        XCTAssertNil(WindowLayoutEngine.bestMatchIndex(
            for: placement,
            candidates: candidates,
            excluding: []
        ))
    }

    func testWindowMatchingAllowsRetainedRuntimeWindowWithoutMetadataMatch() {
        let placement = placement(documentURL: "file:///project/README.md")
        let candidates = [WindowMatchCandidate(
            windowTitle: "Other",
            documentURL: "file:///project/Other.md",
            windowIdentifier: "other-window",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            windowIndex: 1,
            frame: CGRect(x: 300, y: 200, width: 500, height: 400)
        )]

        XCTAssertEqual(WindowLayoutEngine.bestMatchIndex(
            for: placement,
            candidates: candidates,
            excluding: [],
            preferredIndex: 0
        ), 0)
    }

    func testSnapshotCodableRoundTripPreservesStableDisplayIdentity() throws {
        let targetDisplay = display(identity: "uuid-123", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let snapshot = WindowLayoutSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1234),
            displays: [targetDisplay],
            windows: [placement(displayIdentity: targetDisplay.identity)]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WindowLayoutSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.windows.first?.displayIdentity.rawValue, "uuid-123")
    }

    func testSnapshotDisplayLayoutSignatureMatchesDisplayLayoutFormat() {
        let snapshot = WindowLayoutSnapshot(
            capturedAt: Date(),
            displays: [
                display(identity: "external", frame: CGRect(x: -1600, y: 0, width: 1600, height: 900)),
                display(identity: "main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            ],
            windows: []
        )

        XCTAssertEqual(snapshot.displayLayoutSignature, "1600x900@-1600,0|1920x1080@0,0M")
    }

    private func display(identity: String, frame: CGRect) -> WindowDisplaySnapshot {
        WindowDisplaySnapshot(
            identity: WindowDisplayIdentity(rawValue: identity),
            frame: WindowRect(frame),
            visibleFrame: WindowRect(frame),
            isMain: identity == "main"
        )
    }

    private func placement(
        documentURL: String? = nil,
        windowIndex: Int = 0,
        displayIdentity: WindowDisplayIdentity = WindowDisplayIdentity(rawValue: "main"),
        relativeX: Double = 0,
        relativeY: Double = 0,
        width: Double = 800,
        height: Double = 600
    ) -> WindowPlacement {
        WindowPlacement(
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            windowTitle: "README",
            documentURL: documentURL,
            windowIdentifier: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            windowIndex: windowIndex,
            displayIdentity: displayIdentity,
            relativeX: relativeX,
            relativeY: relativeY,
            width: width,
            height: height
        )
    }

    private func candidate(
        documentURL: String? = nil,
        windowIndex: Int = 0,
        subrole: String = "AXStandardWindow"
    ) -> WindowMatchCandidate {
        WindowMatchCandidate(
            windowTitle: "README",
            documentURL: documentURL,
            windowIdentifier: nil,
            role: "AXWindow",
            subrole: subrole,
            windowIndex: windowIndex,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }
}
