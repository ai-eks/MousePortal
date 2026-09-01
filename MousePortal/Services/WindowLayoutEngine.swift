import Foundation
import CoreGraphics

struct WindowMatchCandidate: Equatable {
    let windowTitle: String?
    let documentURL: String?
    let windowIdentifier: String?
    let role: String
    let subrole: String
    let windowIndex: Int
    let frame: CGRect
}

enum WindowLayoutEngine {
    static func savedFrame(
        for placement: WindowPlacement,
        on display: WindowDisplaySnapshot
    ) -> CGRect {
        let displayFrame = display.frame.cgRect
        return CGRect(
            x: displayFrame.minX + placement.relativeX * displayFrame.width,
            y: displayFrame.minY + placement.relativeY * displayFrame.height,
            width: placement.width,
            height: placement.height
        )
    }

    static func display(
        containing windowFrame: CGRect,
        from displays: [WindowDisplaySnapshot]
    ) -> WindowDisplaySnapshot? {
        displays.max { lhs, rhs in
            intersectionArea(windowFrame, lhs.frame.cgRect) < intersectionArea(windowFrame, rhs.frame.cgRect)
        }.flatMap { display in
            intersectionArea(windowFrame, display.frame.cgRect) > 0 ? display : nil
        }
    }

    static func targetFrame(
        for placement: WindowPlacement,
        on display: WindowDisplaySnapshot
    ) -> CGRect {
        let displayFrame = display.frame.cgRect
        let visibleFrame = display.visibleFrame.cgRect

        let width = min(max(placement.width, 1), visibleFrame.width)
        let height = min(max(placement.height, 1), visibleFrame.height)
        let desiredX = displayFrame.minX + placement.relativeX * displayFrame.width
        let desiredY = displayFrame.minY + placement.relativeY * displayFrame.height
        let x = min(max(desiredX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(desiredY, visibleFrame.minY), visibleFrame.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func framesMatch(
        _ actual: CGRect?,
        target: CGRect,
        tolerance: CGFloat = 2
    ) -> Bool {
        guard let actual else { return false }

        return abs(actual.minX - target.minX) <= tolerance &&
            abs(actual.minY - target.minY) <= tolerance &&
            abs(actual.width - target.width) <= tolerance &&
            abs(actual.height - target.height) <= tolerance
    }

    static func bestMatchIndex(
        for placement: WindowPlacement,
        candidates: [WindowMatchCandidate],
        excluding usedIndices: Set<Int>,
        preferredIndex: Int? = nil
    ) -> Int? {
        if let preferredIndex,
           candidates.indices.contains(preferredIndex),
           !usedIndices.contains(preferredIndex),
           candidates[preferredIndex].role == placement.role,
           candidates[preferredIndex].subrole == placement.subrole {
            return preferredIndex
        }

        return candidates.indices
            .filter { !usedIndices.contains($0) }
            .filter {
                candidates[$0].role == placement.role &&
                candidates[$0].subrole == placement.subrole
            }
            .max { lhs, rhs in
                matchScore(placement, candidates[lhs]) < matchScore(placement, candidates[rhs])
            }
    }

    private static func matchScore(_ placement: WindowPlacement, _ candidate: WindowMatchCandidate) -> Double {
        var score = 0.0

        if let documentURL = placement.documentURL,
           documentURL == candidate.documentURL {
            score += 1_000
        }

        if let identifier = placement.windowIdentifier,
           identifier == candidate.windowIdentifier {
            score += 600
        }

        if let title = placement.windowTitle,
           title == candidate.windowTitle {
            score += 300
        }

        if placement.windowIndex == candidate.windowIndex {
            score += 120
        }

        let widthDifference = abs(placement.width - candidate.frame.width)
        let heightDifference = abs(placement.height - candidate.frame.height)
        let sizeDifference = widthDifference + heightDifference
        score += max(0, 80 - sizeDifference / 20)

        return score
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
