import SwiftUI
import Carbon

struct HotkeyRecorder: View {
    let keyCode: UInt16
    let modifiers: UInt64
    let formattedString: String
    let onChange: (UInt16, UInt64) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            startRecording()
        }) {
            HStack {
                if isRecording {
                    Text(L("hotkey.recording")) // 需要在 Localization 中添加，或者用默认文本 "Type shortcut"
                        .foregroundColor(.blue)
                } else {
                    Text(formattedString.isEmpty ? L("hotkey.not_set") : formattedString)
                        .foregroundColor(formattedString.isEmpty ? .secondary : .primary)
                }
            }
            .frame(width: 100, height: 24) // 保持与之前类似的尺寸
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.blue.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(formattedString.isEmpty ? L("hotkey.click_to_record") : formattedString)
        .onHover { hover in
            isHovering = hover
        }
        // 监听失去焦点事件以取消录制
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        // 移除旧的监听器（如果有）
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }

        // 添加本地事件监听
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if !isRecording { return event }

            // 处理 ESC (取消)
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // 处理 Delete (清除)
            if event.keyCode == 51 {
                onChange(UInt16.max, 0)
                stopRecording()
                return nil
            }

            // 忽略单纯的修饰键按下
            // 只要按下任意非修饰键，我们就认为是一个组合
            // 或者如果包含修饰键，我们怎么判断？
            // 通常 keyDown 会在按下普通键时触发。如果只按修饰键，会触发 flagsChanged，这里我们只监听 keyDown。
            // 所以只有当用户按下一个非修饰键时，我们才捕获当前的修饰符状态。

            let newModifiers = convertCocoaModifiersToCarbon(event.modifierFlags)
            let newKeyCode = event.keyCode

            onChange(newKeyCode, newModifiers)
            stopRecording()

            return nil // 吞掉事件
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func convertCocoaModifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var carbonFlags: UInt64 = 0

        if flags.contains(.control) {
            carbonFlags |= UInt64(CGEventFlags.maskControl.rawValue)
        }
        if flags.contains(.option) {
            carbonFlags |= UInt64(CGEventFlags.maskAlternate.rawValue)
        }
        if flags.contains(.shift) {
            carbonFlags |= UInt64(CGEventFlags.maskShift.rawValue)
        }
        if flags.contains(.command) {
            carbonFlags |= UInt64(CGEventFlags.maskCommand.rawValue)
        }

        return carbonFlags
    }
}
