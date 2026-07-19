import SwiftUI

private enum HomeSurface {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebarOverlay = Color.primary.opacity(0.035)
    static let separator = Color.primary.opacity(0.08)
}

struct ContentView: View {
    @ObservedObject private var displayService = DisplayService.shared
    @ObservedObject private var portalService = PortalService.shared
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var hotkeyConfigStore = HotkeyConfigStore.shared
    @ObservedObject private var layoutService = DisplayLayoutService.shared
    @ObservedObject private var languageService = LanguageService.shared

    @State private var selectedLayoutID: UUID?
    @State private var showingRenameSheet = false
    @State private var pendingDeleteLayout: DisplayLayout?
    @State private var renameText = ""
    @State private var renamingDisplayKey: DisplayLayoutKey?
    @State private var displayRenameText = ""
    @State private var editingPortal: PortalPair?

    // 绘制状态
    @State private var drawingSession = PortalDrawingSession()

    private let portalColors: [PortalColor] = PortalColor.allCases
    private let topBarHeight: CGFloat = 64
    @State private var nextColorIndex = 0

    var body: some View {
        HSplitView {
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
                    .disabled(!layoutService.hasUnusedLayouts)
                    .help(L("layout.cleanup_unused"))
                    .accessibilityLabel(L("layout.cleanup_unused"))
                }
                .padding()
                .frame(height: topBarHeight)

                // 排列列表
                List(selection: $selectedLayoutID) {
                    ForEach(layoutService.layouts) { layout in
                        LayoutRowView(
                            layout: layout,
                            isSelected: selectedLayoutID == layout.id,
                            isCurrent: layoutService.currentLayoutID == layout.id,
                            canDelete: LayoutSidebarRules.canDeleteLayout(
                                layoutCount: layoutService.layouts.count,
                                currentLayoutID: layoutService.currentLayoutID,
                                targetLayoutID: layout.id,
                                isLocked: layout.isLocked
                            ),
                            deleteHelpText: LayoutSidebarRules.deleteDisabledHelpText(
                                layoutCount: layoutService.layouts.count,
                                currentLayoutID: layoutService.currentLayoutID,
                                targetLayoutID: layout.id,
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
                            }
                        )
                        .tag(layout.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()
                    .overlay(HomeSurface.separator)

                // 底部提示
                Text(L("layout.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 250)
            .background(HomeSurface.background.overlay(HomeSurface.sidebarOverlay))

            // 右侧：主内容区域
            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                // 左侧：排列信息和绘制按钮
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedLayout?.displayName ?? L("layout.none"))
                            .font(.headline)
                        Text(selectedLayout?.layoutDescription ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 绘制模式指示
                    if drawingSession.isDrawingMode {
                        Text(drawingSession.stepInstructions)
                            .font(.callout)
                            .foregroundColor(.secondary)

                        Button(action: {
                            drawingSession.cancelDrawing()
                        }) {
                            Label(L("button.cancel"), systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else if isCurrentLayout {
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
                .padding()
                .frame(height: topBarHeight)

                // 主画布区域 - 显示器布局 + 传送门绘制
                PortalCanvasView(
                    displays: displaysForView,
                    totalBounds: totalBoundsForView,
                    sharedEdges: sharedEdgesForView,
                    portals: selectedPortals,
                    drawingSession: drawingSession,
                    tempPortalColor: portalColors[nextColorIndex % portalColors.count],
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
                    .frame(maxHeight: 150)
                }

                Divider()
                    .overlay(HomeSurface.separator)

                // 底部：图例和快捷键设置
                VStack(spacing: 12) {
                    // 图例
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

                    Divider()
                        .overlay(HomeSurface.separator)

                    // 快捷键设置区域
                    HStack {
                        Text(L("settings.enable_hotkeys"))
                            .font(.headline)

                        Toggle("", isOn: Binding(
                            get: { hotkeyConfigStore.globalEnabled },
                            set: { newValue in
                                if newValue && !permissionService.isAccessibilityGranted {
                                    permissionService.requestAccessibility()
                                } else {
                                    hotkeyConfigStore.globalEnabled = newValue
                                    hotkeyConfigStore.save()
                                    if newValue {
                                        hotkeyService.start()
                                    } else {
                                        hotkeyService.stop()
                                    }
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()

                        Spacer()

                        // 显示各屏幕快捷键
                        ForEach(hotkeyConfigStore.configs.indices, id: \.self) { index in
                            HotkeyBadge(config: $hotkeyConfigStore.configs[index], onSave: {
                                hotkeyConfigStore.save()
                            })
                        }
                    }
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
                let layout = layoutService.matchOrCreateLayout(for: displayService.displays)
                selectedLayoutID = layout.id
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            } else {
                // 确保 currentLayoutID 正确更新
                let layout = layoutService.matchOrCreateLayout(for: displayService.displays)
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            }
            checkPermissionOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displayService.fetchDisplays()
            hotkeyConfigStore.initializeDefaults(from: displayService.displays)
            // 使用稳定性检测，避免唤醒时产生大量中间状态的排列
            layoutService.handleDisplayChange(displays: displayService.displays) { layout in
                hotkeyConfigStore.initializeDefaults(from: layout.displaysApplyingCustomNames(to: displayService.displays))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            refreshHotkeyDisplayNames()
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
        switch LayoutSidebarRules.deletionAction(
            layoutCount: layoutService.layouts.count,
            currentLayoutID: layoutService.currentLayoutID,
            targetLayoutID: layout.id,
            portalCount: layout.portals.count,
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
        layoutService.deleteLayout(layout)

        if selectedLayoutID == layout.id {
            selectedLayoutID = remainingSelection
        }
    }

    private func deleteConfirmationMessage(for layout: DisplayLayout) -> String {
        LayoutSidebarRules.deleteConfirmationMessage(portalCount: layout.portals.count)
    }

    private func cleanUpUnusedLayouts() {
        let removedIDs = layoutService.cleanUpUnusedLayouts()
        guard let selectedLayoutID, removedIDs.contains(selectedLayoutID) else { return }
        self.selectedLayoutID = layoutService.currentLayoutID ?? layoutService.layouts.first?.id
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

    var body: some View {
        HStack(spacing: 4) {
            Text(config.displayName)
                .font(.caption)
                .foregroundColor(.secondary)

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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
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

            if !layout.portals.isEmpty {
                Text("\(layout.portals.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
