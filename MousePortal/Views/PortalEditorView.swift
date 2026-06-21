import SwiftUI

/// 传送门编辑器视图 - 用于在画布上绘制传送门
struct PortalEditorView: View {
    @ObservedObject private var displayService = DisplayService.shared
    @ObservedObject private var portalService = PortalService.shared

    @State private var drawingSession = PortalDrawingSession()
    @State private var selectedPortalID: UUID?

    private let portalColors: [PortalColor] = PortalColor.allCases
    @State private var nextColorIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: {
                    if drawingSession.isDrawingMode {
                        drawingSession.cancelDrawing()
                    } else {
                        startDrawing()
                    }
                }) {
                    Label(
                        drawingSession.isDrawingMode ? L("portal.cancel") : L("portal.add"),
                        systemImage: drawingSession.isDrawingMode ? "xmark.circle" : "plus.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(drawingSession.isDrawingMode ? .red : .accentColor)

                if drawingSession.isDrawingMode {
                    Text(drawingSession.stepInstructions)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let selectedID = selectedPortalID,
                   let portal = portalService.portals.first(where: { $0.id == selectedID }) {
                    HStack {
                        Text(portal.displayName)
                            .font(.headline)

                        Button(action: {
                            portalService.togglePortal(id: selectedID)
                        }) {
                            Image(systemName: portal.isEnabled ? "eye" : "eye.slash")
                        }

                        Button(action: {
                            portalService.removePortal(id: selectedID)
                            selectedPortalID = nil
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 画布区域
            PortalCanvasView(
                displays: displayService.displays,
                totalBounds: displayService.totalBounds,
                sharedEdges: displayService.sharedEdges,
                portals: portalService.portals,
                drawingSession: drawingSession,
                tempPortalColor: portalColors[nextColorIndex % portalColors.count],
                selectedPortalID: selectedPortalID,
                onPortalTap: { portal in
                    selectedPortalID = portal.id
                },
                onCanvasTap: {
                    if !drawingSession.isDrawingMode {
                        selectedPortalID = nil
                    }
                },
                onDragChanged: { value, _, _ in
                    handleDragChanged(value)
                },
                onDragEnded: { value, scale, offset in
                    handleDragEnded(value, scale: scale, offset: offset)
                }
            )
        }
        .onAppear {
            displayService.fetchDisplays()
        }
        .sheet(isPresented: isNamingPortalPresented) {
            PortalNameSheet(
                portalName: $drawingSession.portalName,
                canCreatePortal: drawingSession.canCreatePortal,
                onCancel: {
                    drawingSession.cancelDrawing()
                },
                onCreate: {
                    createPortal()
                }
            )
        }
    }

    private var isNamingPortalPresented: Binding<Bool> {
        Binding(
            get: { drawingSession.isNamingPortal },
            set: { isPresented in
                if !isPresented && drawingSession.isNamingPortal {
                    drawingSession.cancelDrawing()
                }
            }
        )
    }

    private func startDrawing() {
        drawingSession.startDrawing()
        selectedPortalID = nil
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        drawingSession.handleDragChanged(start: value.startLocation, end: value.location)
    }

    private func handleDragEnded(_ value: DragGesture.Value, scale: CGFloat, offset: CGPoint) {
        let nextPortalName = L("portal.default_name %lld", portalService.portals.count + 1)
        _ = drawingSession.handleDragEnded(
            start: value.startLocation,
            end: value.location,
            in: PortalDrawingCanvasContext(
                scale: scale,
                offset: offset,
                totalBounds: displayService.totalBounds,
                displays: displayService.displays
            ),
            nextPortalName: nextPortalName
        )
    }

    private func createPortal() {
        let color = portalColors[nextColorIndex % portalColors.count]
        guard let portal = drawingSession.buildPortal(color: color) else { return }
        nextColorIndex += 1

        // 使用 DisplayLayoutService 添加传送门（与显示器排列绑定）
        DisplayLayoutService.shared.addPortal(portal)
    }

}
