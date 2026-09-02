import Cocoa
import Combine
import SwiftUI

/// 应用代理，管理菜单栏和后台运行
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    // 服务实例
    private var hotkeyService: HotkeyService?
    private var portalService: PortalService?
    private let permissionService = PermissionService.shared
    private let windowLayoutService = WindowLayoutService.shared
    private var hotkeyConfigStore = HotkeyConfigStore.shared
    private var cancellables: Set<AnyCancellable> = []

    // 应用状态
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    private enum MenuItemTag {
        static let accessibilityStatus = 1001
    }

    private enum SwiftUIActionSelector {
        static let showMainWindow = NSSelectorFromString("showMainWindow:")
        static let showSettingsWindow = NSSelectorFromString("showSettingsWindow:")
        static let showPreferencesWindow = NSSelectorFromString("showPreferencesWindow:")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置单例引用
        AppDelegate.shared = self
        AppTheme.stored().apply()
        terminateOtherInstancesIfNeeded()

        // 确保应用作为正规前台应用运行（对于 swift run 方式很重要）
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 根据设置决定是否显示菜单栏图标
        if showMenuBarIcon {
            setupMenuBarItem()
        }
        setupServices()

        // 如果隐藏菜单栏图标，确保有方式打开设置
        if !showMenuBarIcon {
            showMainWindow()
        }

        permissionService.$isAccessibilityGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateAccessibilityStatusItem()
            }
            .store(in: &cancellables)

        windowLayoutService.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupMenu()
            }
            .store(in: &cancellables)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = permissionService.checkAccessibility()
        updateAccessibilityStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时显示主窗口
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭最后一个窗口后继续在菜单栏运行，但不占用 Dock
        sender.setActivationPolicy(.accessory)
        return false
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        statusItem?.autosaveName = "MousePortalStatusItem"
        statusItem?.isVisible = true

        if let button = statusItem?.button {
            let image = menuBarIconImage()
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = L("app.title")
            button.action = #selector(togglePopover)
            button.target = self
        }

        setupMenu()
    }

    private func menuBarIconImage() -> NSImage? {
        let iconURL = AppResources.bundle.url(forResource: "menuicon", withExtension: "png")

        let image = iconURL.flatMap(NSImage.init(contentsOf:)) ?? NSImage(
            systemSymbolName: "cursorarrow.motionlines",
            accessibilityDescription: L("app.title")
        )

        image?.isTemplate = true
        image?.size = NSSize(width: 26, height: 14)
        image?.accessibilityDescription = L("app.title")
        return image
    }

    private func setupMenu() {
        _ = permissionService.checkAccessibility()
        let menu = NSMenu()
        menu.delegate = self

        // 功能开关
        let hotkeyItem = NSMenuItem(title: L("menu.enable_hotkey"), action: #selector(toggleHotkey), keyEquivalent: "")
        hotkeyItem.state = hotkeyConfigStore.globalEnabled ? .on : .off
        menu.addItem(hotkeyItem)

        let portalItem = NSMenuItem(title: L("menu.enable_portal"), action: #selector(togglePortal), keyEquivalent: "")
        portalItem.state = (portalService?.isRunning ?? false) ? .on : .off
        menu.addItem(portalItem)

        let windowRecoveryItem = NSMenuItem(
            title: L("window_recovery.enabled"),
            action: #selector(toggleWindowRecovery),
            keyEquivalent: ""
        )
        windowRecoveryItem.state = windowLayoutService.isEnabled ? .on : .off
        menu.addItem(windowRecoveryItem)

        menu.addItem(NSMenuItem.separator())

        let accessibilityItem = NSMenuItem(title: accessibilityStatusTitle, action: nil, keyEquivalent: "")
        accessibilityItem.tag = MenuItemTag.accessibilityStatus
        accessibilityItem.isEnabled = false
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())

        // 窗口操作
        menu.addItem(NSMenuItem(title: L("menu.open_window"), action: #selector(showMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: L("menu.preferences"), action: #selector(openSettingsFromMenu), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        // 退出
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        _ = permissionService.checkAccessibility()
        updateAccessibilityStatusItem(in: menu)
    }

    // MARK: - Services Setup

    private func setupServices() {
        hotkeyService = HotkeyService.shared
        portalService = PortalService.shared

        if hotkeyConfigStore.globalEnabled {
            hotkeyService?.start()
        }

        // 传送门默认启动
        portalService?.start()
        windowLayoutService.startMonitoring()
    }

    private func terminateOtherInstancesIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        guard !otherInstances.isEmpty else { return }

        for app in otherInstances {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if otherInstances.allSatisfy(\.isTerminated) {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for app in otherInstances where !app.isTerminated {
            app.forceTerminate()
        }
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        showMainWindow()
    }

    @objc private func toggleHotkey() {
        hotkeyConfigStore.globalEnabled.toggle()
        hotkeyConfigStore.save()
        if hotkeyConfigStore.globalEnabled {
            hotkeyService?.start()
        } else {
            hotkeyService?.stop()
        }
        setupMenu()
    }

    @objc private func togglePortal() {
        if portalService?.isRunning == true {
            portalService?.stop()
        } else {
            portalService?.start()
        }
        setupMenu()
    }

    @objc private func toggleWindowRecovery() {
        if !windowLayoutService.isEnabled && !permissionService.checkAccessibility() {
            permissionService.requestAccessibility()
            return
        }

        windowLayoutService.setEnabled(!windowLayoutService.isEnabled)
        setupMenu()
    }

    // 传递 SwiftUI 环境的 openWindow，可用于直接打开特定 Window
    var openWindowAction: OpenWindowAction?

    @objc func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let isWindowOpen = NSApplication.shared.windows.contains { window in
            if isMainWindow(window) {
                window.makeKeyAndOrderFront(nil)
                return true
            }
            return false
        }

        if !isWindowOpen {
            // macOS 13+ can open Window by id using an environment action
            if let window = NSApplication.shared.windows.first(where: isMainWindow(_:)) {
                window.makeKeyAndOrderFront(nil)
            } else if let openWindow = openWindowAction {
                openWindow(id: "main")
            } else {
                sendSwiftUIAction(SwiftUIActionSelector.showMainWindow)
            }
        }
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitApp() {
        hotkeyService?.stop()
        portalService?.stop()
        windowLayoutService.stopMonitoring()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Public Methods

    /// 打开设置窗口（供外部调用）
    func openSettings() {
        if #available(macOS 14.0, *) {
            sendSwiftUIAction(SwiftUIActionSelector.showSettingsWindow)
        } else {
            sendSwiftUIAction(SwiftUIActionSelector.showPreferencesWindow)
        }
    }

    func updateMenuBarVisibility() {
        // 直接从 UserDefaults 读取，确保获取最新值
        let shouldShow = UserDefaults.standard.bool(forKey: "showMenuBarIcon")

        if shouldShow && statusItem == nil {
            setupMenuBarItem()
        } else if !shouldShow && statusItem != nil {
            NSStatusBar.system.removeStatusItem(statusItem!)
            statusItem = nil
        }
    }

    func refreshMenu() {
        setupMenu()
    }

    private var accessibilityStatusTitle: String {
        AccessibilityPermissionPresentation.menuStatusTitle(
            isGranted: permissionService.isAccessibilityGranted
        )
    }

    private func updateAccessibilityStatusItem(in menu: NSMenu? = nil) {
        let targetMenu = menu ?? statusItem?.menu
        targetMenu?.item(withTag: MenuItemTag.accessibilityStatus)?.title = accessibilityStatusTitle
    }

    private func sendSwiftUIAction(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        window.title.hasPrefix(L("app.title")) || window.contentView is NSHostingView<ContentView>
    }
}
