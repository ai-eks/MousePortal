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
            WindowLayoutEngine.matchWindowIndices(for: [placement], candidates: candidates, preferredIndices: [nil]),
            [1]
        )
    }

    func testWindowMatchingPrefersRetainedRuntimeWindow() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.matchWindowIndices(
                for: [placement],
                candidates: candidates,
                preferredIndices: [1]
            ),
            [1]
        )
    }

    func testWindowMatchingFallsBackWhenRetainedRuntimeWindowWasAlreadyUsed() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.matchWindowIndices(
                for: [placement, placement],
                candidates: candidates,
                preferredIndices: [1, 1]
            ),
            [1, 0]
        )
    }

    func testWindowMatchingDoesNotReuseCandidate() {
        let placement = placement(windowIndex: 0)
        let candidates = [candidate(windowIndex: 0), candidate(windowIndex: 1)]

        XCTAssertEqual(
            WindowLayoutEngine.matchWindowIndices(
                for: [placement, placement], candidates: candidates, preferredIndices: [0, nil]
            ),
            [0, 1]
        )
    }

    func testWindowMatchingRejectsNonstandardWindow() {
        let placement = placement()
        let candidates = [candidate(subrole: "AXDialog")]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [placement],
            candidates: candidates,
            preferredIndices: [nil]
        ), [nil])
    }

    func testWindowMatchingRejectsUnrelatedWindowWithDifferentIndex() {
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
            windowIndex: 1,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [placement],
            candidates: candidates,
            preferredIndices: [nil]
        ), [nil])
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

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [placement],
            candidates: candidates,
            preferredIndices: [0]
        ), [0])
    }

    func testBatchWindowMatchingReservesStrongMatchesBeforeIndexFallback() {
        let placements = [
            placement(
                windowTitle: "Codex - Microsoft Edge",
                documentURL: "https://chatgpt.com/codex",
                windowIndex: 0
            ),
            placement(
                windowTitle: "Game - Microsoft Edge",
                documentURL: "https://game.example.com",
                windowIndex: 1
            ),
            placement(
                windowTitle: "Agent Showcases - Microsoft Edge",
                documentURL: "https://showcases.example.com/old",
                windowIndex: 2
            )
        ]
        let candidates = [
            candidate(
                windowTitle: "VPC Console - Microsoft Edge",
                documentURL: "https://vpc.example.com",
                windowIndex: 0
            ),
            candidate(
                windowTitle: "Agent Showcases - Microsoft Edge",
                documentURL: "https://showcases.example.com/new",
                windowIndex: 1
            )
        ]

        XCTAssertEqual(
            WindowLayoutEngine.matchWindowIndices(
                for: placements,
                candidates: candidates,
                preferredIndices: [nil, nil, nil]
            ),
            [0, nil, 1]
        )
    }

    func testBatchWindowMatchingDoesNotFallbackAcrossDifferentWindowIndices() {
        let placements = [placement(
            windowTitle: "Saved",
            documentURL: "https://saved.example.com",
            windowIndex: 1
        )]
        let candidates = [candidate(
            windowTitle: "Current",
            documentURL: "https://current.example.com",
            windowIndex: 0
        )]

        XCTAssertEqual(
            WindowLayoutEngine.matchWindowIndices(
                for: placements,
                candidates: candidates,
                preferredIndices: [nil]
            ),
            [nil]
        )
    }

    func testMetadataAssignmentDoesNotLoseACompleteMatchingToOneHigherScore() {
        let a = placement(windowTitle: "A", windowIdentifier: "id-a", windowIndex: 10)
        let b = placement(windowTitle: "B", documentURL: "doc-b", windowIdentifier: "id-b", windowIndex: 20)
        let x = candidate(windowTitle: "A", documentURL: "doc-b", windowIdentifier: "id-a", windowIndex: 0)
        let y = candidate(windowTitle: "B", windowIdentifier: "id-b", windowIndex: 1)

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [a, b], candidates: [x, y], preferredIndices: [nil, nil]
        ), [0, 1])
        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [b, a], candidates: [y, x], preferredIndices: [nil, nil]
        ), [0, 1])
    }

    func testMetadataAssignmentMaximizesTotalScoreAtEqualCardinality() {
        let a = placement(windowTitle: "Shared", documentURL: "doc-a", windowIdentifier: "id-a", windowIndex: 10)
        let b = placement(windowTitle: "Shared", windowIdentifier: "id-b", windowIndex: 20)
        let x = candidate(windowTitle: "Shared", documentURL: "doc-a", windowIdentifier: "id-b", windowIndex: 0)
        let y = candidate(windowTitle: "Shared", windowIdentifier: "id-a", windowIndex: 1)

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [a, b], candidates: [x, y], preferredIndices: [nil, nil]
        ), [1, 0])
    }

    func testMetadataAssignmentMatchesExhaustiveSmallGraphOptimum() {
        var seed: UInt64 = 42
        func next(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) % UInt64(limit))
        }
        func score(_ saved: WindowPlacement, _ current: WindowMatchCandidate) -> Int {
            var value = saved.windowTitle == current.windowTitle ? 300 : 0
            if let document = saved.documentURL, document == current.documentURL { value += 1000 }
            if let identifier = saved.windowIdentifier, identifier == current.windowIdentifier { value += 600 }
            return value > 0 ? value + 80 : 0
        }
        for _ in 0..<200 {
            let placements = (0..<next(5)).map { index in
                placement(windowTitle: "title-\(next(4))", documentURL: "doc-\(next(4))",
                          windowIdentifier: "id-\(next(4))", windowIndex: index + 10)
            }
            let candidates = (0..<next(5)).map { index in
                candidate(windowTitle: "title-\(next(4))", documentURL: "doc-\(next(4))",
                          windowIdentifier: "id-\(next(4))", windowIndex: index)
            }
            var best = (count: 0, score: 0)
            func enumerate(_ row: Int, _ used: Set<Int>, _ total: Int) {
                if row == placements.count {
                    if used.count > best.count || (used.count == best.count && total > best.score) {
                        best = (used.count, total)
                    }
                    return
                }
                enumerate(row + 1, used, total)
                for column in candidates.indices where !used.contains(column) {
                    let value = score(placements[row], candidates[column])
                    if value > 0 { enumerate(row + 1, used.union([column]), total + value) }
                }
            }
            enumerate(0, [], 0)
            let matches = WindowLayoutEngine.matchWindowIndices(
                for: placements, candidates: candidates,
                preferredIndices: [Int?](repeating: nil, count: placements.count)
            )
            let columns = matches.compactMap { $0 }
            let total = matches.enumerated().reduce(0) { sum, pair in
                guard let column = pair.element else { return sum }
                return sum + score(placements[pair.offset], candidates[column])
            }
            XCTAssertEqual(Set(columns).count, columns.count)
            XCTAssertEqual(columns.count, best.count)
            XCTAssertEqual(total, best.score)
        }
    }

    func testBatchWindowMatchingAllocatesStrongerDocumentMatchBeforeEarlierTitleMatch() {
        let weak = placement(windowTitle: "Shared", windowIndex: 0)
        let strong = placement(windowTitle: "Old title", documentURL: "file:///report.pdf", windowIndex: 1)
        let candidates = [candidate(windowTitle: "Shared", documentURL: "file:///report.pdf", windowIndex: 0)]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [weak, strong], candidates: candidates, preferredIndices: [nil, nil]
        ), [nil, 0])
        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: [strong, weak], candidates: candidates, preferredIndices: [nil, nil]
        ), [0, nil])
    }

    func testBatchWindowMatchingAllocatesIdentifierMatchWithoutDocumentURLs() {
        let placements = [
            placement(windowTitle: "Shared", windowIndex: 0),
            placement(windowTitle: "Old title", windowIdentifier: "editor-window", windowIndex: 1)
        ]
        let candidates = [candidate(windowTitle: "Shared", windowIdentifier: "editor-window", windowIndex: 0)]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: placements, candidates: candidates, preferredIndices: [nil, nil]
        ), [nil, 0])
    }

    func testBatchWindowMatchingDoesNotScoreBlankDocumentsAsIdentityEvidence() {
        for blankDocument in ["", " \n "] {
            let weak = placement(windowTitle: "Shared", documentURL: blankDocument, windowIndex: 0)
            let strong = placement(windowTitle: "Old title", windowIdentifier: "editor-42", windowIndex: 1)
            let candidates = [candidate(
                windowTitle: "Shared", documentURL: blankDocument,
                windowIdentifier: "editor-42", windowIndex: 0
            )]

            XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
                for: [weak, strong], candidates: candidates, preferredIndices: [nil, nil]
            ), [nil, 0])
        }
    }

    func testBatchWindowMatchingKeepsRuntimeIdentitiesForIdenticalDocuments() {
        let placements = [
            placement(documentURL: "file:///report.pdf", windowIndex: 0),
            placement(documentURL: "file:///report.pdf", windowIndex: 1)
        ]
        let candidates = [
            candidate(documentURL: "file:///report.pdf", windowIndex: 0),
            candidate(documentURL: "file:///report.pdf", windowIndex: 1)
        ]

        XCTAssertEqual(WindowLayoutEngine.matchWindowIndices(
            for: placements, candidates: candidates, preferredIndices: [1, 0]
        ), [1, 0])
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
        windowTitle: String = "README",
        documentURL: String? = nil,
        windowIdentifier: String? = nil,
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
            windowTitle: windowTitle,
            documentURL: documentURL,
            windowIdentifier: windowIdentifier,
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
        windowTitle: String = "README",
        documentURL: String? = nil,
        windowIdentifier: String? = nil,
        windowIndex: Int = 0,
        subrole: String = "AXStandardWindow"
    ) -> WindowMatchCandidate {
        WindowMatchCandidate(
            windowTitle: windowTitle,
            documentURL: documentURL,
            windowIdentifier: windowIdentifier,
            role: "AXWindow",
            subrole: subrole,
            windowIndex: windowIndex,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }
}
