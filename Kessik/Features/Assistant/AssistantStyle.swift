import SwiftUI

/// Shared pieces for the Assistant screens. They use the app's Theme tokens only; the assistant's
/// positive color is `Theme.online`, so its screens read calm and friendly next to the warm accent.
enum AssistantStyle {
    static let accent = Theme.online
    static let bigCorner: CGFloat = 20
}

/// A filled, rounded primary button: Approve, Send.
struct FilledButtonStyle: ButtonStyle {
    var color: Color = AssistantStyle.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// A quiet rounded button: Edit, Not now.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
    }
}

/// A small rounded label, such as a repo name or a model tier.
struct Chip: View {
    var text: String
    var icon: String?
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.semibold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// A state word for a job, with its color.
struct JobStatus: View {
    var status: String

    var body: some View {
        switch status {
        case "approved": Chip(text: "Starting", icon: "clock", color: Theme.textSecondary)
        case "started": Chip(text: "Working", icon: "bolt.fill", color: AssistantStyle.accent)
        case "waiting": Chip(text: "Waiting for you", icon: "hand.raised.fill", color: Theme.warning)
        case "finished": Chip(text: "Done", icon: "checkmark", color: Theme.textSecondary)
        case "failed": Chip(text: "Did not start", icon: "exclamationmark.triangle.fill", color: Theme.accent)
        case "rejected": Chip(text: "Declined", icon: "xmark", color: Theme.textTertiary)
        default: Chip(text: "Needs approval", icon: "checkmark.seal", color: Theme.warning)
        }
    }
}

/// A one-line message at the top of a screen when a request fails.
struct InlineError: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .card()
    }
}
