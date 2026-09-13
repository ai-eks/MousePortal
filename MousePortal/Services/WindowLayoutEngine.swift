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
                  exactWindowTypeMatches(placements[placementIndex], candidates[preferredIndex]) else {
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
                candidates[$0].runtimeIdentity == identity && exactWindowTypeMatches(placement, candidates[$0])
            }
            guard identityMatches.count == 1,
                  let matchIndex = identityMatches.first,
                  !usedIndices.contains(matchIndex) else { continue }
            matches[placementIndex] = matchIndex
            usedIndices.insert(matchIndex)
        }

        // 这些字段只是相似度线索；真实窗口身份已在前两轮优先匹配。
        // 精确身份先保留；其余先最大化有效配对数量，再最大化整体相似度。
        let remainingPlacements = placements.indices.filter {
            matches[$0] == nil && placements[$0].requiresExactIdentity != true
        }
        let remainingCandidates = candidates.indices.filter { !usedIndices.contains($0) }
        let scores = remainingPlacements.map { placementIndex in
            let placement = placements[placementIndex]
            return remainingCandidates.map { candidateIndex -> Double in
                let candidate = candidates[candidateIndex]
                guard candidate.role == placement.role,
                      candidate.subrole == placement.subrole,
                      hasMeaningfulIdentityMatch(placement, candidate) else { return 0 }
                return matchScore(placement, candidate)
            }
        }
        for (row, column) in maximumMetadataAssignment(scores).enumerated() {
            guard let column else { continue }
            let candidateIndex = remainingCandidates[column]
            matches[remainingPlacements[row]] = candidateIndex
            usedIndices.insert(candidateIndex)
        }

        for placementIndex in placements.indices where matches[placementIndex] == nil {
            let placement = placements[placementIndex]
            guard placement.requiresExactIdentity != true else { continue }
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

    private static func exactWindowTypeMatches(_ placement: WindowPlacement, _ candidate: WindowMatchCandidate) -> Bool {
        if placement.requiresExactIdentity == true {
            // CG 阶段未知的类型，直到重新枚举 AX 且精确身份命中后才能确认。
            return candidate.role == "AXWindow" && candidate.subrole == "AXStandardWindow"
        }
        return candidate.role == placement.role && candidate.subrole == placement.subrole
    }

    // 匈牙利算法；每行附加一个虚拟候选，允许没有有效线索的窗口保持未匹配。
    private static func maximumMetadataAssignment(_ scores: [[Double]]) -> [Int?] {
        let rows = scores.count
        let realColumns = scores.first?.count ?? 0
        guard rows > 0, realColumns > 0 else { return [Int?](repeating: nil, count: rows) }
        let columns = realColumns + rows
        let cardinalityBonus = (scores.flatMap { $0 }.max() ?? 0) * Double(min(rows, realColumns)) + 1
        var rowPotential = [Double](repeating: 0, count: rows + 1)
        var columnPotential = [Double](repeating: 0, count: columns + 1)
        var rowAtColumn = [Int](repeating: 0, count: columns + 1)
        var previousColumn = [Int](repeating: 0, count: columns + 1)

        for row in 1...rows {
            rowAtColumn[0] = row
            var column = 0
            var distances = [Double](repeating: .infinity, count: columns + 1)
            var visited = [Bool](repeating: false, count: columns + 1)
            repeat {
                visited[column] = true
                let currentRow = rowAtColumn[column]
                var delta = Double.infinity
                var nextColumn = 0
                for next in 1...columns where !visited[next] {
                    let score = next <= realColumns ? scores[currentRow - 1][next - 1] : 0
                    let cost = score > 0 ? -(cardinalityBonus + score) : 0
                    let distance = cost - rowPotential[currentRow] - columnPotential[next]
                    if distance < distances[next] {
                        distances[next] = distance
                        previousColumn[next] = column
                    }
                    if distances[next] < delta {
                        delta = distances[next]
                        nextColumn = next
                    }
                }
                for next in 0...columns {
                    if visited[next] {
                        rowPotential[rowAtColumn[next]] += delta
                        columnPotential[next] -= delta
                    } else {
                        distances[next] -= delta
                    }
                }
                column = nextColumn
            } while rowAtColumn[column] != 0

            repeat {
                let previous = previousColumn[column]
                rowAtColumn[column] = rowAtColumn[previous]
                column = previous
            } while column != 0
        }

        var matches = [Int?](repeating: nil, count: rows)
        for column in 1...realColumns {
            let row = rowAtColumn[column]
            if row > 0, scores[row - 1][column - 1] > 0 {
                matches[row - 1] = column - 1
            }
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
