import SwiftUI

private enum HomeSurface {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebarOverlay = Color.primary.opacity(0.035)
    static let separator = Color.primary.opacity(0.08)
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    let onResizeEnded: (Double) -> Void
    @State private var dragStartWidth: Double?
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isHovered || isDragging ? Color.accentColor.opacity(0.28) : HomeSurface.separator)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = width
                                    isDragging = true
                                    NSCursor.resizeLeftRight.set()
                                }
                                let initialWidth = dragStartWidth ?? width
                                width = min(max(initialWidth + Double(value.translation.width), 220), 360)
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                                isDragging = false
                                onResizeEnded(width)
                                (isHovered ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                            }
                    )
                    .onHover { hovering in
                        isHovered = hovering
                        if !isDragging {
                            (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                        }
                    }
            }
    }
}

struct ContentView: View {
    @ObservedObject private var displayService = DisplayService.shared
    @ObservedObject private var portalService = PortalService.shared
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var hotkeyConfigStore = HotkeyConfigStore.shared
    @ObservedObject private var layoutService = DisplayLayoutService.shared
    @ObservedObject private var windowLayoutService = WindowLayoutService.shared
    @ObservedObject private var languageService = LanguageService.shared

    @State private var selectedLayoutID: UUID?
    @State private var showingRenameSheet = false
    @State private var pendingDeleteLayout: DisplayLayout?
    @State private var renameText = ""
    @State private var renamingDisplayKey: DisplayLayoutKey?
    @State private var displayRenameText = ""
    @State private var editingPortal: PortalPair?
    @State private var selectedWindowSnapshotID: UUID?
    @State private var showsWindowLayout = false
    @State private var renamingWindowSnapshot: WindowLayoutSnapshot?
    @State private var windowSnapshotRenameText = ""
    @State private var sidebarWidth =
        (UserDefaults.standard.object(forKey: "mainSidebarWidth") as? NSNumber)?.doubleValue ?? 220.0

    // 绘制状态
    @State private var drawingSession = PortalDrawingSession()

    private let portalColors: [PortalColor] = PortalColor.allCases
    private let topBarHeight: CGFloat = 92
    @State private var nextColorIndex = 0

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：显示器排列列表
            VStack(alignment: .leading, spacing: 0) {
                // 标题栏
                HStack {
                    Text(L("layout.title"))
                        .font(.headline)
                    Spacer()
                    Button(action: cleanUpUnusedLayouts) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!layoutService.hasUnusedLayouts(
                        preserving: savedWindowLayoutSignatures
                    ))
                    .help(L("layout.cleanup_unused"))
                    .accessibilityLabel(L("layout.cleanup_unused"))
                }
                .padding()
                .frame(height: topBarHeight)

                // 排列列表
                List {
                    ForEach(layoutService.layouts) { layout in
                        let savedSnapshots = windowLayoutService.snapshots(matching: layout.signature)
                        let snapshots = windowLayoutService.isEnabled
                            ? savedSnapshots
                            : []

                        VStack(alignment: .leading, spacing: 3) {
                            LayoutRowView(
                                layout: layout,
                                isSelected: selectedLayoutID == layout.id,
                                isCurrent: layoutService.currentLayoutID == layout.id,
                                canDelete: LayoutSidebarRules.canDeleteLayout(
                                    layoutCount: layoutService.layouts.count,
                                    currentLayoutID: layoutService.currentLayoutID,
                                    targetLayoutID: layout.id,
                                    windowSnapshotCount: savedSnapshots.count,
                                    isLocked: layout.isLocked
                                ),
                                deleteHelpText: LayoutSidebarRules.deleteDisabledHelpText(
                                    layoutCount: layoutService.layouts.count,
                                    currentLayoutID: layoutService.currentLayoutID,
                                    targetLayoutID: layout.id,
                                    windowSnapshotCount: savedSnapshots.count,
                                    isLocked: layout.isLocked
                                ),
                                onToggleLock: {
                                    layoutService.toggleLayoutLock(layout)
                                },
                                onRename: {
                                    openRenameSheet(for: layout)
                                },
                                onDelete: {
                                    requestDeleteLayoutFromSidebar(layout)
                                },
                                onSelect: {
                                    selectedLayoutID = layout.id
                                }
                            )

                            ForEach(snapshots) { snapshot in
                                WindowLayoutSnapshotSidebarRow(
                                    title: windowSnapshotTitle(for: snapshot, in: snapshots),
                                    snapshot: snapshot,
                                    isSelected: selectedWindowSnapshotID == snapshot.id,
                                    onSelect: {
                                        selectWindowSnapshot(snapshot, in: layout)
                                    },
                                    onPromote: {
                                        promoteWindowSnapshot(snapshot, in: layout)
                                    },
                                    onRestore: {
                                        restoreWindowSnapshot(snapshot, in: layout)
                                    },
                                    onRename: {
                                        openRenameWindowSnapshot(
                                            snapshot,
                                            in: layout,
                                            matching: snapshots
                                        )
                                    },
                                    onDelete: {
                                        deleteWindowSnapshot(snapshot)
                                    }
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Divider()
                    .overlay(HomeSurface.separator)

                // 底部提示
                Text(L("layout.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .frame(width: CGFloat(min(max(sidebarWidth, 220), 360)))
            .background(HomeSurface.background.overlay(HomeSurface.sidebarOverlay))

            SidebarResizeHandle(width: $sidebarWidth) { finalWidth in
                UserDefaults.standard.set(finalWidth, forKey: "mainSidebarWidth")
            }

            // 右侧：主内容区域
            VStack(spacing: 0) {
                // 顶部工具栏
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        // 左侧：排列信息和绘制按钮
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedLayout?.displayName ?? L("layout.none"))
                                .font(.headline)
                            Text(selectedLayout?.layoutDescription ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 12)

                        // 绘制模式指示
                        if drawingSession.isDrawingMode {
                            Text(drawingSession.stepInstructions)
                                .font(.callout)
                                .foregroundColor(drawingSession.hasValidationError ? .red : .secondary)

                            Button(action: {
                                drawingSession.cancelDrawing()
                            }) {
                                Label(L("button.cancel"), systemImage: "xmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else if isCurrentLayout {
                            Button(action: saveCurrentWindowLayout) {
                                Label(L("window_recovery.save"), systemImage: "macwindow.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!windowLayoutService.isEnabled)
                            .help(saveWindowLayoutHelp)

                            Button(action: {
                                drawingSession.startDrawing()
                            }) {
                                Label(L("portal.add"), systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        // 状态指示
                        HStack(spacing: 12) {
                            StatusIndicator(
                                isEnabled: hotkeyService.isRunning,
                                label: L("status.hotkey")
                            )

                            StatusIndicator(
                                isEnabled: portalService.isRunning,
                                label: L("status.portal")
                            )
                        }

                        if #available(macOS 14.0, *) {
                            SettingsLink {
                                Image(systemName: "gear")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(action: {
                                AppDelegate.shared?.openSettings()
                            }) {
                                Image(systemName: "gear")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: { displayService.fetchDisplays() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(L("button.refresh"))
                    }

                    HStack(spacing: 16) {
                        Spacer()

                        Toggle(L("window_layout.show"), isOn: Binding(
                            get: { showsWindowLayout },
                            set: { isShown in
                                showsWindowLayout = isShown
                                if isShown {
                                    synchronizeWindowSnapshotSelection()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .fixedSize()
                        .disabled(!windowLayoutService.isEnabled || matchingWindowSnapshots.isEmpty)
                        .help(windowLayoutToggleHelp)

                        Toggle(L("settings.enable_hotkeys"), isOn: hotkeyJumpEnabledBinding)
                            .toggleStyle(.switch)
                            .fixedSize()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(height: topBarHeight)

                // 主画布区域 - 显示器布局 + 传送门绘制
                PortalCanvasView(
                    displays: displaysForView,
                    totalBounds: totalBoundsForView,
                    sharedEdges: sharedEdgesForView,
                    portals: selectedPortals,
                    drawingSession: drawingSession,
                    tempPortalColor: portalColors[nextColorIndex % portalColors.count],
                    windowSnapshot: showsWindowLayout ? selectedWindowSnapshot : nil,
                    hotkeyConfigs: isCurrentLayout && hotkeyConfigStore.globalEnabled
                        ? $hotkeyConfigStore.configs
                        : nil,
                    onHotkeySave: {
                        hotkeyConfigStore.save()
                    },
                    onDisplayRename: { display in
                        openRenameDisplaySheet(for: display)
                    },
                    onDragChanged: { value, _, _ in
                        handleDragChanged(value)
                    },
                    onDragEnded: { value, scale, offset in
                        handleDragEnded(value, scale: scale, offset: offset)
                    }
                )
                .frame(minHeight: 280)
                .id(selectedLayoutID) // 强制在选择布局变化时重新渲染

                // 传送门列表
                if selectedPortals.isEmpty && !drawingSession.isDrawingMode {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text(L("portal.empty_hint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !isCurrentLayout {
                            Text(L("layout.not_current_hint"))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 100)
                } else if !selectedPortals.isEmpty {
                    List {
                        ForEach(selectedPortals) { portal in
                            PortalListRowView(
                                portal: portal,
                                displays: displaysForView,
                                areActionsEnabled: isCurrentLayout,
                                onToggle: {
                                    if isCurrentLayout {
                                        layoutService.togglePortal(id: portal.id)
                                    }
                                },
                                onEdit: {
                                    editingPortal = portal
                                },
                                onDelete: {
                                    if isCurrentLayout {
                                        layoutService.removePortal(id: portal.id)
                                    }
                                }
                            )
                            .opacity(isCurrentLayout ? 1.0 : 0.6)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(selectedPortals.count > 4 ? .visible : .hidden)
                    .frame(height: portalListHeight)
                }

                Divider()
                    .overlay(HomeSurface.separator)

                // 底部图例
                HStack(spacing: 20) {
                    LegendItem(color: .blue, label: languageService.localizedString("legend.main_display"))
                    LegendItem(color: .gray, label: languageService.localizedString("legend.external_display"))
                    LegendItem(color: .green, label: languageService.localizedString("legend.shared_edge"), isLine: true)
                    PortalColorsLegend(
                        portals: selectedPortals,
                        label: languageService.localizedString("legend.portal")
                    )
                    Spacer()
                }
                .padding()
            }
            .background(HomeSurface.background)
        }
        .background(HomeSurface.background)
        .frame(minWidth: 1000, minHeight: 680)
        .onAppear {
            displayService.fetchDisplays()
            // 只在首次加载时设置 selectedLayoutID
            if selectedLayoutID == nil {
                let layout = layoutService.matchOrCreateLayout(
                    for: displayService.displays,
                    preserving: savedWindowLayoutSignatures
                )
                selectedLayoutID = layout.id
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            } else {
                // 确保 currentLayoutID 正确更新
                let layout = layoutService.matchOrCreateLayout(
                    for: displayService.displays,
                    preserving: savedWindowLayoutSignatures
                )
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            }
            checkPermissionOnLaunch()
            synchronizeWindowSnapshotSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displayService.fetchDisplays()
            hotkeyConfigStore.initializeDefaults(from: displayService.displays)
            // 使用稳定性检测，避免唤醒时产生大量中间状态的排列
            layoutService.handleDisplayChange(
                displays: displayService.displays,
                preserving: savedWindowLayoutSignatures
            ) { layout in
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            refreshHotkeyDisplayNames()
        }
        .onReceive(windowLayoutService.$snapshots) { _ in
            synchronizeWindowSnapshotSelection()
        }
        .onReceive(windowLayoutService.$isEnabled) { isEnabled in
            if isEnabled {
                synchronizeWindowSnapshotSelection()
            } else {
                selectedWindowSnapshotID = nil
                showsWindowLayout = false
            }
        }
        .onChange(of: selectedLayoutID) { _ in
            synchronizeWindowSnapshotSelection()
        }
        .alert(
            "",
            isPresented: Binding(
                get: { pendingDeleteLayout != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteLayout = nil
                    }
                }
            ),
            presenting: pendingDeleteLayout
        ) { layout in
            Button(L("layout.delete"), role: .destructive) {
                performDeleteLayout(layout)
                pendingDeleteLayout = nil
            }
            Button(L("button.cancel"), role: .cancel) {
                pendingDeleteLayout = nil
            }
        } message: { layout in
            Text("\(L("layout.delete_confirm_title %@", layout.displayName))\n\n\(deleteConfirmationMessage(for: layout))")
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameLayoutSheet(
                name: $renameText,
                onSave: {
                    if let id = selectedLayoutID,
                       let layout = layoutService.layouts.first(where: { $0.id == id }) {
                        layoutService.renameLayout(layout, to: renameText)
                    }
                    showingRenameSheet = false
                },
                onCancel: {
                    showingRenameSheet = false
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { renamingDisplayKey != nil },
                set: { isPresented in
                    if !isPresented {
                        renamingDisplayKey = nil
                    }
                }
            )
        ) {
            RenameDisplaySheet(
                name: $displayRenameText,
                onSave: {
                    saveDisplayName()
                },
                onCancel: {
                    renamingDisplayKey = nil
                }
            )
        }
        .sheet(item: $renamingWindowSnapshot) { snapshot in
            RenameWindowLayoutSheet(
                name: $windowSnapshotRenameText,
                onSave: {
                    _ = windowLayoutService.renameSnapshot(
                        id: snapshot.id,
                        to: windowSnapshotRenameText
                    )
                    renamingWindowSnapshot = nil
                },
                onCancel: {
                    renamingWindowSnapshot = nil
                }
            )
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
        .sheet(item: $editingPortal) { portal in
            PortalEditSheet(portal: portal, displays: displaysForView, isCurrentLayout: isCurrentLayout)
        }
    }

    // MARK: - 计算属性

    private var selectedLayout: DisplayLayout? {
        guard let id = selectedLayoutID else { return nil }
        return layoutService.layouts.first { $0.id == id }
    }

    private var isCurrentLayout: Bool {
        selectedLayoutID == layoutService.currentLayoutID
    }

    private var selectedPortals: [PortalPair] {
        selectedLayout?.portals ?? []
    }

    private var portalListHeight: CGFloat {
        CGFloat(min(selectedPortals.count, 4)) * 50 + 8
    }

    private var matchingWindowSnapshots: [WindowLayoutSnapshot] {
        guard let signature = selectedLayout?.signature else { return [] }
        return windowLayoutService.snapshots(matching: signature)
    }

    private var selectedWindowSnapshot: WindowLayoutSnapshot? {
        guard let selectedWindowSnapshotID else { return nil }
        return matchingWindowSnapshots.first { $0.id == selectedWindowSnapshotID }
    }

    private var windowLayoutToggleHelp: String {
        if !windowLayoutService.isEnabled {
            return L("window_recovery.enable_in_settings")
        }
        if matchingWindowSnapshots.isEmpty {
            return L("window_layout.no_saved")
        }
        return L("window_layout.show_help")
    }

    private var saveWindowLayoutHelp: String {
        windowLayoutService.isEnabled
            ? L("window_recovery.save_help")
            : L("window_recovery.enable_in_settings")
    }

    private var hotkeyJumpEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeyConfigStore.globalEnabled },
            set: { isEnabled in
                if isEnabled && !permissionService.checkAccessibility() {
                    permissionService.requestAccessibility()
                    return
                }

                hotkeyConfigStore.globalEnabled = isEnabled
                hotkeyConfigStore.save()
                if isEnabled {
                    hotkeyService.start()
                } else {
                    hotkeyService.stop()
                }
            }
        )
    }

    /// 用于显示的显示器列表（当前排列用实时数据，历史排列用快照）
    private var displaysForView: [DisplayInfo] {
        if isCurrentLayout {
            guard let selectedLayout else { return displayService.displays }
            return selectedLayout.displaysApplyingCustomNames(to: displayService.displays)
        } else {
            return selectedLayout?.snapshotDisplays ?? []
        }
    }

    /// 用于显示的总边界
    private var totalBoundsForView: CGRect {
        if isCurrentLayout {
            return displayService.totalBounds
        } else {
            return selectedLayout?.snapshotTotalBounds ?? .zero
        }
    }

    /// 用于显示的共享边缘（当前排列用实时数据，历史排列根据快照计算）
    private var sharedEdgesForView: [SharedEdge] {
        if isCurrentLayout {
            return displayService.sharedEdges
        } else {
            return calculateSharedEdges(for: displaysForView)
        }
    }

    /// 根据显示器列表计算共享边缘
    private func calculateSharedEdges(for displays: [DisplayInfo]) -> [SharedEdge] {
        var edges: [SharedEdge] = []

        for i in 0..<displays.count {
            for j in (i + 1)..<displays.count {
                let d1 = displays[i]
                let d2 = displays[j]

                // 检查左右相邻 (d1 在 d2 左边)
                if let edge = checkHorizontalAdjacency(left: d1, right: d2) {
                    edges.append(edge)
                }
                // 检查左右相邻 (d2 在 d1 左边)
                if let edge = checkHorizontalAdjacency(left: d2, right: d1) {
                    edges.append(edge)
                }
                // 检查上下相邻 (d1 在 d2 上面)
                if let edge = checkVerticalAdjacency(top: d1, bottom: d2) {
                    edges.append(edge)
                }
                // 检查上下相邻 (d2 在 d1 上面)
                if let edge = checkVerticalAdjacency(top: d2, bottom: d1) {
                    edges.append(edge)
                }
            }
        }

        return edges
    }

    /// 检查水平方向相邻（left 的右边缘 = right 的左边缘）
    private func checkHorizontalAdjacency(left: DisplayInfo, right: DisplayInfo) -> SharedEdge? {
        guard abs(left.rightEdge - right.leftEdge) <= 1 else { return nil }

        let overlapTop = max(left.topEdge, right.topEdge)
        let overlapBottom = min(left.bottomEdge, right.bottomEdge)

        guard overlapBottom > overlapTop else { return nil }

        let x = left.rightEdge
        return SharedEdge(
            from: left.id,
            to: right.id,
            start: CGPoint(x: x, y: overlapTop),
            end: CGPoint(x: x, y: overlapBottom)
        )
    }

    /// 检查垂直方向相邻（top 的下边缘 = bottom 的上边缘）
    private func checkVerticalAdjacency(top: DisplayInfo, bottom: DisplayInfo) -> SharedEdge? {
        guard abs(top.bottomEdge - bottom.topEdge) <= 1 else { return nil }

        let overlapLeft = max(top.leftEdge, bottom.leftEdge)
        let overlapRight = min(top.rightEdge, bottom.rightEdge)

        guard overlapRight > overlapLeft else { return nil }

        let y = top.bottomEdge
        return SharedEdge(
            from: top.id,
            to: bottom.id,
            start: CGPoint(x: overlapLeft, y: y),
            end: CGPoint(x: overlapRight, y: y)
        )
    }

    // MARK: - 绘制逻辑

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

    private func handleDragChanged(_ value: DragGesture.Value) {
        drawingSession.handleDragChanged(start: value.startLocation, end: value.location)
    }

    private func handleDragEnded(_ value: DragGesture.Value, scale: CGFloat, offset: CGPoint) {
        let nextPortalName = L("portal.default_name %lld", (selectedLayout?.portals.count ?? 0) + 1)
        _ = drawingSession.handleDragEnded(
            start: value.startLocation,
            end: value.location,
            in: PortalDrawingCanvasContext(
                scale: scale,
                offset: offset,
                totalBounds: totalBoundsForView,
                displays: displaysForView
            ),
            nextPortalName: nextPortalName
        )
    }

    private func createPortal() {
        let color = portalColors[nextColorIndex % portalColors.count]
        guard let portal = drawingSession.buildPortal(color: color) else { return }
        nextColorIndex += 1
        layoutService.addPortal(portal)
    }

    private func saveCurrentWindowLayout() {
        guard windowLayoutService.isEnabled else { return }
        guard permissionService.checkAccessibility() else {
            permissionService.requestAccessibility()
            return
        }
        guard let snapshot = windowLayoutService.saveCurrentLayout() else { return }
        selectedWindowSnapshotID = snapshot.id
        showsWindowLayout = true
        windowLayoutService.refreshAvailableApplications()
    }

    private func selectWindowSnapshot(_ snapshot: WindowLayoutSnapshot, in layout: DisplayLayout) {
        selectedLayoutID = layout.id
        selectedWindowSnapshotID = snapshot.id
        showsWindowLayout = true
    }

    private func promoteWindowSnapshot(_ snapshot: WindowLayoutSnapshot, in layout: DisplayLayout) {
        selectedLayoutID = layout.id
        selectedWindowSnapshotID = snapshot.id
        _ = windowLayoutService.promoteAutomaticSnapshot(id: snapshot.id)
    }

    private func restoreWindowSnapshot(_ snapshot: WindowLayoutSnapshot, in layout: DisplayLayout) {
        guard permissionService.checkAccessibility() else {
            permissionService.requestAccessibility()
            return
        }

        selectWindowSnapshot(snapshot, in: layout)
        _ = windowLayoutService.restoreSavedLayout(snapshotID: snapshot.id)
    }

    private func deleteWindowSnapshot(_ snapshot: WindowLayoutSnapshot) {
        _ = windowLayoutService.deleteSnapshot(id: snapshot.id)
    }

    private func windowSnapshotTitle(
        for snapshot: WindowLayoutSnapshot,
        in snapshots: [WindowLayoutSnapshot]
    ) -> String {
        if let name = snapshot.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        if snapshot.kind == .automatic {
            return L("window_layout.automatic_before_lock")
        }

        let manualSnapshots = snapshots.filter { $0.kind == .manual }
        let index = manualSnapshots.firstIndex(where: { $0.id == snapshot.id }) ?? 0
        return L("window_layout.saved %lld", index + 1)
    }

    private func openRenameWindowSnapshot(
        _ snapshot: WindowLayoutSnapshot,
        in layout: DisplayLayout,
        matching snapshots: [WindowLayoutSnapshot]
    ) {
        selectedLayoutID = layout.id
        selectedWindowSnapshotID = snapshot.id
        windowSnapshotRenameText = windowSnapshotTitle(for: snapshot, in: snapshots)
        renamingWindowSnapshot = snapshot
    }

    private func synchronizeWindowSnapshotSelection() {
        guard windowLayoutService.isEnabled else {
            selectedWindowSnapshotID = nil
            showsWindowLayout = false
            return
        }

        let snapshots = matchingWindowSnapshots
        guard !snapshots.isEmpty else {
            selectedWindowSnapshotID = nil
            showsWindowLayout = false
            return
        }

        if !snapshots.contains(where: { $0.id == selectedWindowSnapshotID }) {
            selectedWindowSnapshotID = snapshots.first(where: { $0.kind == .automatic })?.id
                ?? snapshots.last?.id
        }
    }

    private func openRenameSheet(for layout: DisplayLayout) {
        renameText = layout.displayName
        selectedLayoutID = layout.id
        showingRenameSheet = true
    }

    private func openRenameDisplaySheet(for display: DisplayInfo) {
        guard selectedLayoutID != nil else { return }
        renamingDisplayKey = display.layoutKey
        displayRenameText = display.name
    }

    private func saveDisplayName() {
        guard let layoutID = selectedLayoutID,
              let displayLayoutKey = renamingDisplayKey else {
            return
        }

        layoutService.renameDisplay(
            in: layoutID,
            displayLayoutKey: displayLayoutKey,
            to: displayRenameText
        )
        if layoutID == layoutService.currentLayoutID {
            hotkeyConfigStore.renameDisplay(displayLayoutKey: displayLayoutKey, to: displayRenameText)
        }
        renamingDisplayKey = nil
    }

    private func requestDeleteLayoutFromSidebar(_ layout: DisplayLayout) {
        let windowSnapshotCount = windowLayoutService
            .snapshots(matching: layout.signature)
            .count
        switch LayoutSidebarRules.deletionAction(
            layoutCount: layoutService.layouts.count,
            currentLayoutID: layoutService.currentLayoutID,
            targetLayoutID: layout.id,
            portalCount: layout.portals.count,
            windowSnapshotCount: windowSnapshotCount,
            isLocked: layout.isLocked
        ) {
        case .unavailable:
            return
        case .deleteImmediately:
            performDeleteLayout(layout)
        case .requireConfirmation:
            pendingDeleteLayout = layout
        }
    }

    private func performDeleteLayout(_ layout: DisplayLayout) {
        pendingDeleteLayout = nil

        let remainingSelection = LayoutSidebarRules.nextSelectedLayoutID(
            afterDeleting: layout.id,
            currentSelectionID: selectedLayoutID,
            orderedLayoutIDs: layoutService.layouts.map(\.id)
        )
        layoutService.deleteLayout(
            layout,
            preserving: savedWindowLayoutSignatures
        )

        if selectedLayoutID == layout.id {
            selectedLayoutID = remainingSelection
        }
    }

    private func deleteConfirmationMessage(for layout: DisplayLayout) -> String {
        LayoutSidebarRules.deleteConfirmationMessage(portalCount: layout.portals.count)
    }

    private func cleanUpUnusedLayouts() {
        let removedIDs = layoutService.cleanUpUnusedLayouts(
            preserving: savedWindowLayoutSignatures
        )
        guard let selectedLayoutID, removedIDs.contains(selectedLayoutID) else { return }
        self.selectedLayoutID = layoutService.currentLayoutID ?? layoutService.layouts.first?.id
    }

    private var savedWindowLayoutSignatures: Set<String> {
        Set(windowLayoutService.snapshots.map(\.displayLayoutSignature))
    }

    private func refreshHotkeyDisplayNames() {
        guard let layout = layoutService.currentLayout else { return }
        hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
    }

    private func checkPermissionOnLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !permissionService.checkAccessibility() {
                permissionService.requestAccessibility()
            }
        }
    }

}

/// 快捷键标签
struct HotkeyBadge: View {
    @Binding var config: HotkeyConfig
    let onSave: () -> Void
    var showsDisplayName = true

    var body: some View {
        HStack(spacing: 4) {
            if showsDisplayName {
                Text(config.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(config.shortcutString.isEmpty ? L("hotkey.not_set") : config.shortcutString)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)

            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { newValue in
                    config.isEnabled = newValue
                    onSave()
                }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7)
            .labelsHidden()
        }
    }
}

/// 显示器排列下的二级窗口布局项。
private struct WindowLayoutSnapshotSidebarRow: View {
    let title: String
    let snapshot: WindowLayoutSnapshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onPromote: () -> Void
    let onRestore: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.kind == .automatic ? "lock.fill" : "macwindow")
                .frame(width: 14)

            Text(snapshot.kind == .automatic
                 ? L("window_layout.kind.automatic")
                 : L("window_layout.kind.manual"))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .foregroundColor(snapshot.kind == .automatic ? .orange : .accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill((snapshot.kind == .automatic ? Color.orange : Color.accentColor).opacity(0.12))
                )

            Text(title)
                .lineLimit(1)
                .fontWeight(isSelected ? .semibold : .regular)
                .layoutPriority(1)

            Spacer(minLength: 2)

            if snapshot.kind == .automatic {
                SnapshotActionButton(
                    systemImage: "arrow.up.circle",
                    accessibilityLabel: L("window_layout.promote_to_manual"),
                    tint: .orange,
                    action: onPromote
                )
            }

            SnapshotActionButton(
                systemImage: "play.fill",
                accessibilityLabel: L("window_layout.apply"),
                tint: .accentColor,
                action: onRestore
            )

            SnapshotActionButton(
                systemImage: "pencil",
                accessibilityLabel: L("layout.rename"),
                tint: .primary,
                action: onRename
            )

            SnapshotActionButton(
                systemImage: "trash",
                accessibilityLabel: L("layout.delete"),
                tint: .red,
                action: onDelete
            )
        }
        .font(.caption)
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .help(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
    }
}

private struct SnapshotActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 图例项
struct LegendItem: View {
    let color: Color
    let label: String
    var isLine: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isLine {
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: 4)
                    .cornerRadius(2)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 12)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 传送门颜色图例 - 显示当前使用的所有传送门颜色
struct PortalColorsLegend: View {
    let portals: [PortalPair]
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            // 显示使用中的颜色（去重）
            let usedColors = Array(Set(portals.map { $0.color }))
            if usedColors.isEmpty {
                // 没有传送门时显示默认样式
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 20, height: 4)
                    .cornerRadius(2)
            } else {
                // 显示所有使用中的颜色
                ForEach(usedColors, id: \.self) { portalColor in
                    Rectangle()
                        .fill(Color(
                            red: portalColor.color.red,
                            green: portalColor.color.green,
                            blue: portalColor.color.blue
                        ))
                        .frame(width: 20, height: 4)
                        .cornerRadius(2)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 状态指示器
struct StatusIndicator: View {
    let isEnabled: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 显示器排列行视图
struct LayoutRowView: View {
    let layout: DisplayLayout
    let isSelected: Bool
    let isCurrent: Bool
    let canDelete: Bool
    let deleteHelpText: String
    let onToggleLock: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    if layout.isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help(L("layout.locked"))
                    }
                    Text(layout.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                }

                Text(layout.layoutDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                RowActionButton(
                    systemImage: layout.isLocked ? "lock.fill" : "lock.open",
                    accessibilityLabel: layout.isLocked ? L("layout.unlock") : L("layout.lock"),
                    tint: layout.isLocked ? .orange : .secondary,
                    action: onToggleLock
                )

                RowActionButton(
                    systemImage: "pencil",
                    accessibilityLabel: L("layout.rename"),
                    tint: .primary,
                    action: onRename
                )

                RowActionButton(
                    systemImage: "trash",
                    accessibilityLabel: deleteHelpText,
                    tint: canDelete ? .red : .secondary,
                    isEnabled: canDelete,
                    action: onDelete
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// 传送门列表行视图
struct PortalListRowView: View {
    let portal: PortalPair
    let displays: [DisplayInfo]
    let areActionsEnabled: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(
                    red: portal.color.color.red,
                    green: portal.color.color.green,
                    blue: portal.color.color.blue
                ))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(portal.displayName)
                    .fontWeight(.medium)

                Text(portalDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { portal.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .labelsHidden()
            .disabled(!areActionsEnabled)
            .help(areActionsEnabled ? L("portal.enabled") : L("layout.readonly_hint"))

            RowActionButton(
                systemImage: "pencil",
                accessibilityLabel: areActionsEnabled ? L("portal.edit") : L("layout.readonly_hint"),
                tint: .primary,
                isEnabled: areActionsEnabled,
                action: onEdit
            )

            RowActionButton(
                systemImage: "trash",
                accessibilityLabel: areActionsEnabled ? L("portal.delete") : L("layout.readonly_hint"),
                tint: .red,
                isEnabled: areActionsEnabled,
                action: onDelete
            )
        }
        .padding(.vertical, 4)
    }

    private var portalDescription: String {
        let displayA = displays.first { $0.layoutKey == portal.lineA.displayLayoutKey }?.name ?? L("display.unknown")
        let displayB = displays.first { $0.layoutKey == portal.lineB.displayLayoutKey }?.name ?? L("display.unknown")
        let edgeA = portal.lineA.edge.localizedName
        let edgeB = portal.lineB.edge.localizedName
        let directionSymbol = portal.isBidirectional ? "↔" : "→"

        return "\(displayA) (\(edgeA)) \(directionSymbol) \(displayB) (\(edgeB))"
    }
}

struct RowActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isEnabled ? tint : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isEnabled ? tint.opacity(0.12) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isEnabled ? tint.opacity(0.18) : Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(accessibilityLabel)
        .opacity(isEnabled ? 1.0 : 0.55)
    }
}

/// 重命名排列对话框
struct RenameLayoutSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(L("layout.rename_title"))
                .font(.headline)

            FocusableTextField(text: $name, placeholder: L("layout.name_placeholder")) {
                if !name.isEmpty {
                    onSave()
                }
            }
            .frame(width: 250, height: 24)

            HStack {
                Button(L("button.cancel"), action: onCancel)
                Button(L("button.save"), action: onSave)
                    .disabled(name.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320, height: 150)
    }
}

/// 重命名窗口布局对话框
private struct RenameWindowLayoutSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L("window_layout.rename_title"))
                .font(.headline)

            FocusableTextField(text: $name, placeholder: L("window_layout.name_placeholder")) {
                if canSave {
                    onSave()
                }
            }
            .frame(width: 250, height: 24)

            HStack {
                Button(L("button.cancel"), action: onCancel)
                Button(L("button.save"), action: onSave)
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320, height: 150)
    }
}

/// 重命名显示器对话框
struct RenameDisplaySheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L("display.rename_title"))
                .font(.headline)

            FocusableTextField(text: $name, placeholder: L("display.name_placeholder")) {
                if canSave {
                    onSave()
                }
            }
            .frame(width: 250, height: 24)

            HStack {
                Button(L("button.cancel"), action: onCancel)
                Button(L("button.save"), action: onSave)
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320, height: 150)
    }
}

/// 传送门编辑对话框
struct PortalEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var layoutService = DisplayLayoutService.shared

    let portal: PortalPair
    let displays: [DisplayInfo]
    let isCurrentLayout: Bool

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var isBidirectional: Bool
    @State private var selectedColor: PortalColor
    @State private var lineA: PortalLine
    @State private var lineB: PortalLine

    init(portal: PortalPair, displays: [DisplayInfo], isCurrentLayout: Bool = true) {
        self.portal = portal
        self.displays = displays
        self.isCurrentLayout = isCurrentLayout
        _name = State(initialValue: portal.displayName)
        _isEnabled = State(initialValue: portal.isEnabled)
        _isBidirectional = State(initialValue: portal.isBidirectional)
        _selectedColor = State(initialValue: portal.color)
        _lineA = State(initialValue: portal.lineA)
        _lineB = State(initialValue: portal.lineB)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L("portal.edit_title"))
                .font(.headline)

            Form {
                TextField(L("portal.name"), text: $name)
                    .disabled(!isCurrentLayout)

                Toggle(L("portal.enabled"), isOn: $isEnabled)
                    .disabled(!isCurrentLayout)

                Toggle(L("portal.bidirectional"), isOn: $isBidirectional)
                    .disabled(!isCurrentLayout)

                Picker(L("portal.color"), selection: $selectedColor) {
                    ForEach(PortalColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(Color(
                                    red: color.color.red,
                                    green: color.color.green,
                                    blue: color.color.blue
                                ))
                                .frame(width: 12, height: 12)
                            Text(color.localizedName)
                        }
                        .tag(color)
                    }
                }
                .disabled(!isCurrentLayout)

                Section {
                    LabeledContent(L("portal.line_a")) {
                        Text(lineDescription(for: lineA))
                    }

                    LabeledContent(L("portal.line_b")) {
                        Text(lineDescription(for: lineB))
                    }
                } header: {
                    HStack {
                        Text(L("portal.position"))
                        Spacer()
                        Button(action: swapPortalLines) {
                            Label("A/B", systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!isCurrentLayout)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !isCurrentLayout {
                Text(L("layout.readonly_hint"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Button(L("button.cancel")) {
                    dismiss()
                }

                if isCurrentLayout {
                    Button(L("button.save")) {
                        saveChanges()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 550, height: 450)
    }

    private func saveChanges() {
        var updatedPortal = portal
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedPortal.rename(
            to: trimmedName,
            preservingGeneratedName: portal.customName == nil && trimmedName == portal.displayName
        )
        updatedPortal.isEnabled = isEnabled
        updatedPortal.isBidirectional = isBidirectional
        updatedPortal.color = selectedColor
        updatedPortal.lineA = lineA
        updatedPortal.lineB = lineB
        layoutService.updatePortal(updatedPortal)
    }

    private func lineDescription(for line: PortalLine) -> String {
        let displayName = displays.first { $0.layoutKey == line.displayLayoutKey }?.name ?? L("display.unknown")
        return "\(displayName) - \(line.edge.localizedName)"
    }

    private func swapPortalLines() {
        let originalLineA = lineA
        lineA = lineB
        lineB = originalLineA
    }
}
