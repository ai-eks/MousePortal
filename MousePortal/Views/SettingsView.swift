import SwiftUI

/// 设置主界面
struct SettingsView: View {
    @ObservedObject private var languageService = LanguageService.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("settings.general"), systemImage: "gear")
                }

            HotkeySettingsView()
                .tabItem {
                    Label(L("settings.hotkeys"), systemImage: "keyboard")
                }

            PortalSettingsView()
                .tabItem {
                    Label(L("settings.portals"), systemImage: "arrow.left.arrow.right")
                }

            WindowRecoverySettingsView()
                .tabItem {
                    Label(L("settings.window_recovery"), systemImage: "macwindow.on.rectangle")
                }
        }
        .frame(width: 550, height: 450)
        .id(languageService.refreshID)
    }
}

/// 普通应用窗口布局保存与恢复。
struct WindowRecoverySettingsView: View {
    @ObservedObject private var service = WindowLayoutService.shared
    @ObservedObject private var permissionService = PermissionService.shared
    @State private var applicationSearchText = ""

    private var filteredApplications: [WindowApplicationOption] {
        WindowApplicationSearch.filtered(
            service.availableApplications,
            query: applicationSearchText
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(L("window_recovery.enabled"), isOn: Binding(
                        get: { service.isEnabled },
                        set: { enabled in
                            if enabled && !permissionService.checkAccessibility() {
                                permissionService.requestAccessibility()
                            } else {
                                service.setEnabled(enabled)
                                AppDelegate.shared?.refreshMenu()
                            }
                        }
                    ))

                    Text(L("window_recovery.limitations"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle(L("window_recovery.remember_before_sleep"), isOn: Binding(
                    get: { service.rememberBeforeSleepOrLockEnabled },
                    set: { service.setRememberBeforeSleepOrLockEnabled($0) }
                ))
                .disabled(!service.isEnabled)

                Toggle(L("window_recovery.automatic"), isOn: Binding(
                    get: { service.automaticRestoreEnabled },
                    set: { service.setAutomaticRestoreEnabled($0) }
                ))
                .disabled(!service.isEnabled || !service.rememberBeforeSleepOrLockEnabled)
            } header: {
                Text(L("window_recovery.behavior"))
            }

            if !service.availableApplications.isEmpty {
                Section {
                    TextField(
                        L("window_recovery.search_apps"),
                        text: $applicationSearchText
                    )
                    .textFieldStyle(.roundedBorder)

                    ForEach(filteredApplications) { application in
                        Toggle(application.name, isOn: Binding(
                            get: {
                                service.ignoredBundleIdentifiers.contains(application.bundleIdentifier)
                            },
                            set: { ignored in
                                service.setApplicationIgnored(
                                    application.bundleIdentifier,
                                    ignored: ignored
                                )
                            }
                        ))
                    }
                } header: {
                    Text(L("window_recovery.ignored_apps"))
                } footer: {
                    Text(L("window_recovery.ignored_apps_description"))
                }
            }

        }
        .formStyle(.grouped)
        .onAppear {
            _ = permissionService.checkAccessibility()
            service.refreshAvailableApplications()
        }
    }
}

/// 通用设置
struct GeneralSettingsView: View {
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var languageService = LanguageService.shared
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section {
                // 语言选择
                Picker(L("settings.language"), selection: $languageService.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        if language == .system {
                            Text(language.displayName).tag(language)
                        } else {
                            Text("\(language.displayName) (\(language.englishName))").tag(language)
                        }
                    }
                }

                Toggle(L("settings.show_menubar_icon"), isOn: Binding(
                    get: { showMenuBarIcon },
                    set: { newValue in
                        showMenuBarIcon = newValue
                        // 延迟一点确保 UserDefaults 已写入
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            AppDelegate.shared?.updateMenuBarVisibility()
                        }
                    }
                ))
                Toggle(L("settings.launch_at_login"), isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { newValue in
                        launchAtLoginService.setEnabled(newValue)
                    }
                ))
            } header: {
                Text(L("settings.app_behavior"))
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text(L("settings.accessibility_permission"))
                            .font(.headline)
                        Text(L("settings.accessibility_description"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if permissionService.isAccessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(L("settings.permission_granted"))
                            .foregroundColor(.green)
                    } else {
                        Button(L("settings.grant_permission")) {
                            permissionService.requestAccessibility()
                        }
                    }
                }
            } header: {
                Text(L("settings.permissions"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            _ = permissionService.checkAccessibility()
            launchAtLoginService.refreshState()
        }
        .id(languageService.refreshID)
    }
}

/// 快捷键设置
struct HotkeySettingsView: View {
    @ObservedObject private var hotkeyConfigStore = HotkeyConfigStore.shared
    @ObservedObject private var displayService = DisplayService.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.enable_hotkeys"), isOn: Binding(
                    get: { hotkeyConfigStore.globalEnabled },
                    set: { newValue in
                        hotkeyConfigStore.globalEnabled = newValue
                        hotkeyConfigStore.save()
                        if newValue {
                            HotkeyService.shared.start()
                        } else {
                            HotkeyService.shared.stop()
                        }
                    }
                ))
            }

            Section {
                ForEach(hotkeyConfigStore.configs.indices, id: \.self) { index in
                    HStack {
                        Text(hotkeyConfigStore.configs[index].displayName)
                            .frame(width: 120, alignment: .leading)

                        Spacer()
                        HotkeyRecorder(
                            keyCode: hotkeyConfigStore.configs[index].keyCode,
                            modifiers: hotkeyConfigStore.configs[index].modifiers,
                            formattedString: hotkeyConfigStore.configs[index].shortcutString,
                            onChange: { newKeyCode, newModifiers in
                                hotkeyConfigStore.updateConfig(
                                    for: hotkeyConfigStore.configs[index].displayID,
                                    keyCode: newKeyCode,
                                    modifiers: newModifiers
                                )
                            }
                        )

                        Toggle("", isOn: Binding(
                            get: { hotkeyConfigStore.configs[index].isEnabled },
                            set: { newValue in
                                hotkeyConfigStore.configs[index].isEnabled = newValue
                                hotkeyConfigStore.save()
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            } header: {
                HStack {
                    Text(L("settings.display_hotkeys"))
                    Text(L("hotkey.click_to_record"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            displayService.fetchDisplays()
            hotkeyConfigStore.initializeDefaults(from: displayService.displays)
        }
    }
}

/// 传送门设置
struct PortalSettingsView: View {
    @ObservedObject private var portalService = PortalService.shared

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.enable_portals"), isOn: Binding(
                    get: { portalService.isRunning },
                    set: { newValue in
                        if newValue {
                            portalService.start()
                        } else {
                            portalService.stop()
                        }
                        AppDelegate.shared?.refreshMenu()
                    }
                ))

                Picker(L("settings.trigger_mode"), selection: Binding(
                    get: { portalService.triggerMode },
                    set: { newValue in
                        portalService.triggerMode = newValue
                        portalService.save()
                    }
                )) {
                    Text(L("trigger.automatic")).tag(PortalTriggerMode.automatic)
                    Text(L("trigger.with_key")).tag(PortalTriggerMode.withKey)
                }

                if portalService.triggerMode == .withKey {
                    Picker(L("settings.trigger_key"), selection: Binding(
                        get: { portalService.triggerKey },
                        set: { newValue in
                            portalService.triggerKey = newValue
                            portalService.save()
                        }
                    )) {
                        ForEach(PortalTriggerKey.allCases) { triggerKey in
                            Text(triggerKey.displayTitle).tag(triggerKey)
                        }
                    }
                }
            }

            Section {
                if portalService.portals.isEmpty {
                    Text(L("settings.no_portals"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(portalService.portals) { portal in
                        PortalRowView(portal: portal)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            portalService.removePortal(id: portalService.portals[index].id)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L("settings.portal_list"))
                    Spacer()
                    Text(L("settings.portal_hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 传送门行视图
struct PortalRowView: View {
    let portal: PortalPair
    @ObservedObject private var portalService = PortalService.shared

    var body: some View {
        HStack {
            Circle()
                .fill(Color(red: portal.color.color.red, green: portal.color.color.green, blue: portal.color.color.blue))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading) {
                Text(portal.displayName)
                    .font(.headline)
                Text("\(portal.lineA.edge.localizedName) → \(portal.lineB.edge.localizedName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { portal.isEnabled },
                set: { _ in portalService.togglePortal(id: portal.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}
