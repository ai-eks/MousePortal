import SwiftUI

@main
struct MousePortalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(AppVersion.windowTitle, id: "main") {
            ContentView()
                .onAppear {
                    appDelegate.openWindowAction = openWindow
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 760)
        .commands {
            // 替换默认的 About 菜单
            CommandGroup(replacing: .appInfo) {
                Button(L("menu.about")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            // 替换默认的 Quit 菜单
            CommandGroup(replacing: .appTermination) {
                Button(L("menu.quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        Settings {
            SettingsView()
        }
    }
}
