import SwiftUI

/// 可正确获取焦点的 NSTextField 包装
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard !context.coordinator.didFocusOnce else { return }
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.makeFirstResponder(nsView)
                context.coordinator.didFocusOnce = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var didFocusOnce = false

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}
