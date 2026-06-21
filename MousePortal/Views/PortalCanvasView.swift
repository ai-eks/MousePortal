import SwiftUI

struct PortalCanvasView: View {
    let displays: [DisplayInfo]
    let totalBounds: CGRect
    let sharedEdges: [SharedEdge]
    let portals: [PortalPair]
    let drawingSession: PortalDrawingSession
    let tempPortalColor: PortalColor
    var selectedPortalID: UUID?
    var onPortalTap: ((PortalPair) -> Void)? = nil
    var onCanvasTap: (() -> Void)? = nil
    var onDisplayRename: ((DisplayInfo) -> Void)? = nil
    let onDragChanged: (DragGesture.Value, CGFloat, CGPoint) -> Void
    let onDragEnded: (DragGesture.Value, CGFloat, CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = PortalDrawingGeometry.calculateScale(for: geometry.size, totalBounds: totalBounds)
            let offset = PortalDrawingGeometry.calculateOffset(for: geometry.size, scale: scale, totalBounds: totalBounds)

            ZStack {
                ForEach(displays) { display in
                    DisplayRectView(
                        display: display,
                        onRename: onDisplayRename.map { rename in
                            { rename(display) }
                        }
                    )
                        .frame(
                            width: display.frame.width * scale,
                            height: display.frame.height * scale
                        )
                        .position(
                            x: (display.frame.midX - totalBounds.minX) * scale + offset.x,
                            y: (display.frame.midY - totalBounds.minY) * scale + offset.y
                        )
                }

                ForEach(sharedEdges) { edge in
                    Path { path in
                        let startX = (edge.start.x - totalBounds.minX) * scale + offset.x
                        let startY = (edge.start.y - totalBounds.minY) * scale + offset.y
                        let endX = (edge.end.x - totalBounds.minX) * scale + offset.x
                        let endY = (edge.end.y - totalBounds.minY) * scale + offset.y

                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(Color.green, lineWidth: 4)
                    .shadow(color: .green.opacity(0.5), radius: 4)
                }

                ForEach(portals) { portal in
                    PortalPairOverlayView(
                        portal: portal,
                        displays: displays,
                        totalBounds: totalBounds,
                        scale: scale,
                        offset: offset,
                        isSelected: selectedPortalID == portal.id
                    )
                    .onTapGesture {
                        onPortalTap?(portal)
                    }
                }

                if let lineA = drawingSession.tempLineA,
                   let display = displayForPortalLine(lineA) {
                    PortalLineOverlayView(
                        line: lineA,
                        displayBounds: display.frame,
                        totalBounds: totalBounds,
                        scale: scale,
                        offset: offset,
                        color: tempPortalColor
                    )
                }

                if let lineB = drawingSession.tempLineB,
                   let display = displayForPortalLine(lineB) {
                    PortalLineOverlayView(
                        line: lineB,
                        displayBounds: display.frame,
                        totalBounds: totalBounds,
                        scale: scale,
                        offset: offset,
                        color: tempPortalColor
                    )
                }

                if let start = drawingSession.dragStart,
                   let end = drawingSession.dragEnd,
                   drawingSession.isDrawingMode {
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, dash: [5, 5]))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        onDragChanged(value, scale, offset)
                    }
                    .onEnded { value in
                        onDragEnded(value, scale, offset)
                    }
            )
            .onTapGesture {
                onCanvasTap?()
            }
        }
    }

    private func displayForPortalLine(_ line: PortalLine) -> DisplayInfo? {
        if let layoutKey = line.displayLayoutKey {
            return displays.first { $0.layoutKey == layoutKey }
        }
        if let legacyDisplayID = line.legacyDisplayID {
            return displays.first { $0.id == legacyDisplayID }
        }
        return nil
    }
}

struct PortalPairOverlayView: View {
    let portal: PortalPair
    let displays: [DisplayInfo]
    let totalBounds: CGRect
    let scale: CGFloat
    let offset: CGPoint
    var isSelected: Bool = false

    var body: some View {
        Group {
            if let displayA = displayForPortalLine(portal.lineA) {
                PortalLineOverlayView(
                    line: portal.lineA,
                    displayBounds: displayA.frame,
                    totalBounds: totalBounds,
                    scale: scale,
                    offset: offset,
                    color: portal.color,
                    isSelected: isSelected,
                    isEnabled: portal.isEnabled
                )
            }

            if let displayB = displayForPortalLine(portal.lineB) {
                PortalLineOverlayView(
                    line: portal.lineB,
                    displayBounds: displayB.frame,
                    totalBounds: totalBounds,
                    scale: scale,
                    offset: offset,
                    color: portal.color,
                    isSelected: isSelected,
                    isEnabled: portal.isEnabled
                )
            }
        }
    }

    private func displayForPortalLine(_ line: PortalLine) -> DisplayInfo? {
        if let layoutKey = line.displayLayoutKey {
            return displays.first { $0.layoutKey == layoutKey }
        }
        if let legacyDisplayID = line.legacyDisplayID {
            return displays.first { $0.id == legacyDisplayID }
        }
        return nil
    }
}

struct PortalLineOverlayView: View {
    let line: PortalLine
    let displayBounds: CGRect
    let totalBounds: CGRect
    let scale: CGFloat
    let offset: CGPoint
    let color: PortalColor
    var isSelected: Bool = false
    var isEnabled: Bool = true

    var body: some View {
        let startPoint = transformPoint(line.startPoint(in: displayBounds))
        let endPoint = transformPoint(line.endPoint(in: displayBounds))

        Path { path in
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        .stroke(
            Color(red: color.color.red, green: color.color.green, blue: color.color.blue)
                .opacity(isEnabled ? 1.0 : 0.4),
            style: StrokeStyle(lineWidth: isSelected ? 6 : 4, lineCap: .round)
        )
        .shadow(color: isSelected ? .white : .clear, radius: 4)
    }

    private func transformPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - totalBounds.minX) * scale + offset.x,
            y: (point.y - totalBounds.minY) * scale + offset.y
        )
    }
}
