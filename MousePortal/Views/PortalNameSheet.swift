import SwiftUI

struct PortalNameSheet: View {
    @Binding var portalName: String
    let canCreatePortal: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(L("portal.name_title"))
                .font(.headline)

            FocusableTextField(text: $portalName, placeholder: L("portal.name_placeholder")) {
                guard canCreatePortal else { return }
                onCreate()
            }
            .frame(width: 250, height: 24)

            HStack {
                Button(L("button.cancel")) {
                    onCancel()
                }

                Button(L("button.create")) {
                    onCreate()
                }
                .disabled(!canCreatePortal)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}
