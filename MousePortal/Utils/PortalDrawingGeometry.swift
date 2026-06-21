import CoreGraphics

enum PortalDrawingGeometry {
    static func canvasToScreen(_ point: CGPoint, scale: CGFloat, offset: CGPoint, totalBounds: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / scale + totalBounds.minX,
            y: (point.y - offset.y) / scale + totalBounds.minY
        )
    }

    static func createLineFromDrag(start: CGPoint, end: CGPoint, displays: [DisplayInfo]) -> PortalLine? {
        guard let display = findBestDisplayForLine(start: start, end: end, displays: displays) else {
            return nil
        }

        let bounds = display.frame
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let edge = findNearestEdge(point: midPoint, bounds: bounds)

        switch edge {
        case .left, .right:
            let startOffset = max(0, min(start.y - bounds.minY, bounds.height))
            let endOffset = max(0, min(end.y - bounds.minY, bounds.height))
            return PortalLine(displayLayoutKey: display.layoutKey, edge: edge, startOffset: startOffset, endOffset: endOffset)
        case .top, .bottom:
            let startOffset = max(0, min(start.x - bounds.minX, bounds.width))
            let endOffset = max(0, min(end.x - bounds.minX, bounds.width))
            return PortalLine(displayLayoutKey: display.layoutKey, edge: edge, startOffset: startOffset, endOffset: endOffset)
        }
    }

    static func findBestDisplayForLine(start: CGPoint, end: CGPoint, displays: [DisplayInfo], tolerance: CGFloat = 100) -> DisplayInfo? {
        let midPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let candidates = displays.filter { display in
            let expandedBounds = display.frame.insetBy(dx: -tolerance, dy: -tolerance)
            return expandedBounds.contains(midPoint)
        }

        if candidates.isEmpty {
            return findNearestDisplay(to: midPoint, displays: displays)
        }

        if candidates.count == 1 {
            return candidates.first
        }

        let lineMinY = min(start.y, end.y)
        let lineMaxY = max(start.y, end.y)
        let lineMinX = min(start.x, end.x)
        let lineMaxX = max(start.x, end.x)

        return candidates.max { display1, display2 in
            let score1 = calculateOverlapScore(
                display: display1,
                lineMinX: lineMinX,
                lineMaxX: lineMaxX,
                lineMinY: lineMinY,
                lineMaxY: lineMaxY
            )
            let score2 = calculateOverlapScore(
                display: display2,
                lineMinX: lineMinX,
                lineMaxX: lineMaxX,
                lineMinY: lineMinY,
                lineMaxY: lineMaxY
            )
            return score1 < score2
        }
    }

    static func calculateScale(for size: CGSize, totalBounds: CGRect) -> CGFloat {
        guard totalBounds.width > 0 && totalBounds.height > 0 else { return 1 }
        let scaleX = size.width / totalBounds.width
        let scaleY = size.height / totalBounds.height
        return min(scaleX, scaleY) * 0.8
    }

    static func calculateOffset(for size: CGSize, scale: CGFloat, totalBounds: CGRect) -> CGPoint {
        let scaledWidth = totalBounds.width * scale
        let scaledHeight = totalBounds.height * scale
        return CGPoint(
            x: (size.width - scaledWidth) / 2,
            y: (size.height - scaledHeight) / 2
        )
    }

    static func calculateOverlapScore(
        display: DisplayInfo,
        lineMinX: CGFloat,
        lineMaxX: CGFloat,
        lineMinY: CGFloat,
        lineMaxY: CGFloat
    ) -> CGFloat {
        let bounds = display.frame
        let yOverlapMin = max(lineMinY, bounds.minY)
        let yOverlapMax = min(lineMaxY, bounds.maxY)
        let yOverlap = max(0, yOverlapMax - yOverlapMin)
        let xOverlapMin = max(lineMinX, bounds.minX)
        let xOverlapMax = min(lineMaxX, bounds.maxX)
        let xOverlap = max(0, xOverlapMax - xOverlapMin)

        // 同时考虑 X/Y 重叠，避免跨边界时多个候选得分完全相同。
        return yOverlap + xOverlap
    }

    static func findNearestDisplay(to point: CGPoint, displays: [DisplayInfo]) -> DisplayInfo? {
        displays.min { display1, display2 in
            let dist1 = distanceToRect(point: point, rect: display1.frame)
            let dist2 = distanceToRect(point: point, rect: display2.frame)
            return dist1 < dist2
        }
    }

    static func distanceToRect(point: CGPoint, rect: CGRect) -> CGFloat {
        let clampedX = max(rect.minX, min(point.x, rect.maxX))
        let clampedY = max(rect.minY, min(point.y, rect.maxY))
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return sqrt(dx * dx + dy * dy)
    }

    static func findNearestEdge(point: CGPoint, bounds: CGRect) -> PortalEdge {
        let distToLeft = abs(point.x - bounds.minX)
        let distToRight = abs(point.x - bounds.maxX)
        let distToTop = abs(point.y - bounds.minY)
        let distToBottom = abs(point.y - bounds.maxY)

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }
}
