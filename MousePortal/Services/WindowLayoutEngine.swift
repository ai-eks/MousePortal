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
    var runtimeIdentity: WindowRuntimeIdentity? = nil
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

    static func matchWindowIndices(
        for placements: [WindowPlacement],
        candidates: [WindowMatchCandidate],
        preferredIndices: [Int?]
    ) -> [Int?] {
        var matches = [Int?](repeating: nil, count: placements.count)
        var usedIndices = Set<Int>()

        for placementIndex in placements.indices {
            guard let preferredIndex = preferredIndices[placementIndex],
                  candidates.indices.contains(preferredIndex),
                  !usedIndices.contains(preferredIndex),
                  candidates[preferredIndex].role == placements[placementIndex].role,
                  candidates[preferredIndex].subrole == placements[placementIndex].subrole else {
                continue
            }

            matches[placementIndex] = preferredIndex
            usedIndices.insert(preferredIndex)
        }

        // MousePortal 重启后重新枚举 AX 对象，只接受同应用、同进程启动、同会话的窗口 ID。
        for placementIndex in placements.indices where matches[placementIndex] == nil {
            let placement = placements[placementIndex]
            guard let identity = placement.runtimeIdentity,
                  identity.bundleIdentifier == placement.bundleIdentifier else { continue }
            let identityMatches = candidates.indices.filter {
                candidates[$0].runtimeIdentity == identity &&
                    candidates[$0].role == placement.role &&
                    candidates[$0].subrole == placement.subrole
            }
            guard identityMatches.count == 1,
                  let matchIndex = identityMatches.first,
                  !usedIndices.contains(matchIndex) else { continue }
            matches[placementIndex] = matchIndex
            usedIndices.insert(matchIndex)
        }

        // 这些字段只是相似度线索；真实窗口身份已在前两轮优先匹配。
        // 全局按分数分配，避免较早记录的弱匹配抢走后面记录的强匹配。
        var scoredPairs: [(placement: Int, candidate: Int, score: Double)] = []
        for placementIndex in placements.indices where matches[placementIndex] == nil {
            let placement = placements[placementIndex]
            for candidateIndex in candidates.indices where !usedIndices.contains(candidateIndex) {
                let candidate = candidates[candidateIndex]
                guard candidate.role == placement.role,
                      candidate.subrole == placement.subrole,
                      hasMeaningfulIdentityMatch(placement, candidate) else { continue }
                scoredPairs.append((placementIndex, candidateIndex, matchScore(placement, candidate)))
            }
        }
        scoredPairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.placement != $1.placement { return $0.placement < $1.placement }
            return $0.candidate < $1.candidate
        }

        for pair in scoredPairs where matches[pair.placement] == nil && !usedIndices.contains(pair.candidate) {
            matches[pair.placement] = pair.candidate
            usedIndices.insert(pair.candidate)
        }

        for placementIndex in placements.indices where matches[placementIndex] == nil {
            let placement = placements[placementIndex]
            guard let matchIndex = candidates.indices.first(where: { candidateIndex in
                let candidate = candidates[candidateIndex]
                return !usedIndices.contains(candidateIndex) &&
                    candidate.role == placement.role &&
                    candidate.subrole == placement.subrole &&
                    candidate.windowIndex == placement.windowIndex
            }) else {
                continue
            }

            matches[placementIndex] = matchIndex
            usedIndices.insert(matchIndex)
        }

        return matches
    }

    private static func hasMeaningfulIdentityMatch(
        _ placement: WindowPlacement,
        _ candidate: WindowMatchCandidate
    ) -> Bool {
        exactNonEmptyMatch(placement.documentURL, candidate.documentURL) ||
            exactNonEmptyMatch(placement.windowIdentifier, candidate.windowIdentifier) ||
            exactNonEmptyMatch(placement.windowTitle, candidate.windowTitle)
    }

    private static func exactNonEmptyMatch(_ saved: String?, _ current: String?) -> Bool {
        guard let saved,
              !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return saved == current
    }

    private static func matchScore(_ placement: WindowPlacement, _ candidate: WindowMatchCandidate) -> Double {
        var score = 0.0

        if exactNonEmptyMatch(placement.documentURL, candidate.documentURL) {
            score += 1_000
        }

        if exactNonEmptyMatch(placement.windowIdentifier, candidate.windowIdentifier) {
            score += 600
        }

        if exactNonEmptyMatch(placement.windowTitle, candidate.windowTitle) {
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
