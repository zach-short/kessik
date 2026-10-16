import SwiftUI

/// Art, a title and a line of help for a list with nothing in it yet. The art is in the asset
/// catalog, drawn in Theme colors on a clear background.
struct EmptyState<Actions: View>: View {
    var art: String
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(art)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 130)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}

extension EmptyState where Actions == EmptyView {
    init(art: String, title: String, message: String) {
        self.init(art: art, title: title, message: message) { EmptyView() }
    }
}

#Preview {
    VStack {
        EmptyState(art: "EmptyTmux", title: "No tmux sessions",
                   message: "Start a Claude session above. It keeps running on the Mac after you close the app.")
        EmptyState(art: "EmptyLink", title: "No Mac yet", message: "Add your Mac in Settings.") {
            Button("Open Settings") {}
                .buttonStyle(.borderedProminent)
        }
    }
    .background(Theme.background)
}
