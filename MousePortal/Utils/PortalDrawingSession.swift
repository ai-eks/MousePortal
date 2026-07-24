import CoreGraphics

struct PortalDrawingCanvasContext {
    let scale: CGFloat
    let offset: CGPoint
    let totalBounds: CGRect
    let displays: [DisplayInfo]
}

struct PortalDrawingSession {
    enum Step: Equatable {
        case idle
        case drawingLineA
        case drawingLineB
        case naming
    }

    var isDrawingMode = false
    var currentStep: Step = .idle
    var tempLineA: PortalLine?
    var tempLineB: PortalLine?
    var dragStart: CGPoint?
    var dragEnd: CGPoint?
    var portalName = ""
    var defaultPortalName = ""
    var hasValidationError = false

    var isNamingPortal: Bool {
        currentStep == .naming
    }

    var canCreatePortal: Bool {
        guard let lineA = tempLineA, let lineB = tempLineB else { return false }
        return !Self.linesOverlap(lineA, lineB) && !trimmedPortalName.isEmpty
    }

    var stepInstructions: String {
        if hasValidationError {
            return L("portal.error_lines_overlap")
        }

        switch currentStep {
        case .idle:
            return ""
        case .drawingLineA:
            return L("portal.instruction_line_a")
        case .drawingLineB:
            return L("portal.instruction_line_b")
        case .naming:
            return L("portal.instruction_name")
        }
    }

    mutating func startDrawing() {
        isDrawingMode = true
        currentStep = .drawingLineA
        tempLineA = nil
        tempLineB = nil
        dragStart = nil
        dragEnd = nil
        portalName = ""
        defaultPortalName = ""
        hasValidationError = false
    }

    mutating func cancelDrawing() {
        isDrawingMode = false
        currentStep = .idle
        tempLineA = nil
        tempLineB = nil
        dragStart = nil
        dragEnd = nil
        portalName = ""
        hasValidationError = false
    }

    mutating func handleDragChanged(start: CGPoint, end: CGPoint) {
        guard isDrawingMode else { return }
        hasValidationError = false
        dragStart = start
        dragEnd = end
    }

    mutating func handleDragEnded(
        start: CGPoint,
        end: CGPoint,
        in context: PortalDrawingCanvasContext,
        nextPortalName: String
    ) -> Bool {
        guard isDrawingMode else { return false }

        let screenStart = PortalDrawingGeometry.canvasToScreen(
            start,
            scale: context.scale,
            offset: context.offset,
            totalBounds: context.totalBounds
        )
        let screenEnd = PortalDrawingGeometry.canvasToScreen(
            end,
            scale: context.scale,
            offset: context.offset,
            totalBounds: context.totalBounds
        )

        var shouldShowNameDialog = false
        if let line = PortalDrawingGeometry.createLineFromDrag(start: screenStart, end: screenEnd, displays: context.displays) {
            switch currentStep {
            case .drawingLineA:
                tempLineA = line
                currentStep = .drawingLineB
            case .drawingLineB:
                guard let lineA = tempLineA, !Self.linesOverlap(lineA, line) else {
                    hasValidationError = true
                    break
                }
                hasValidationError = false
                tempLineB = line
                currentStep = .naming
                portalName = nextPortalName
                defaultPortalName = nextPortalName
                shouldShowNameDialog = true
            case .idle, .naming:
                break
            }
        }

        dragStart = nil
        dragEnd = nil
        return shouldShowNameDialog
    }

    mutating func buildPortal(color: PortalColor) -> PortalPair? {
        guard canCreatePortal, let lineA = tempLineA, let lineB = tempLineB else { return nil }

        let portal = PortalPair(
            name: trimmedPortalName,
            lineA: lineA,
            lineB: lineB,
            isEnabled: true,
            isBidirectional: true,
            color: color,
            isGeneratedName: trimmedPortalName == defaultPortalName
        )

        cancelDrawing()
        return portal
    }

    private var trimmedPortalName: String {
        portalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func linesOverlap(_ lineA: PortalLine, _ lineB: PortalLine) -> Bool {
        guard let displayLayoutKey = lineA.displayLayoutKey,
              displayLayoutKey == lineB.displayLayoutKey,
              lineA.edge == lineB.edge else {
            return false
        }

        let overlapStart = max(min(lineA.startOffset, lineA.endOffset), min(lineB.startOffset, lineB.endOffset))
        let overlapEnd = min(max(lineA.startOffset, lineA.endOffset), max(lineB.startOffset, lineB.endOffset))
        return overlapStart <= overlapEnd
    }
}
