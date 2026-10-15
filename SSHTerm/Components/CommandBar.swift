import SwiftUI

/// Quick-connect / command field at the top of a screen.
struct CommandBar: View {
    @Binding var text: String
    var prompt: String = "Connect or run a command…"
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
            TextField(prompt, text: $text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .card()
    }
}
