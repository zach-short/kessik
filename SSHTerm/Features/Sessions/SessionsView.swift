import SwiftUI

struct SessionsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NewClaudeSessionButton()
                        .padding(.bottom, 8)

                    SectionLabel("tmux sessions")
                    if store.sessions.isEmpty {
                        Text("No sessions. Start one above.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .card()
                    }
                    ForEach(store.sessions) { session in
                        SessionRow(session: session)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle("Sessions")
        }
    }
}

struct NewClaudeSessionButton: View {
    var body: some View {
        Button {
            // Build step 4: folder picker, then `tmux new -A -s <name> -c <path> claude`.
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Claude session")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pick a repo and open Claude Code in tmux")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }
}

struct SessionRow: View {
    var session: TmuxSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    if session.attached {
                        Text("attached")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.online)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.online.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(session.path) · \(session.windows) window\(session.windows == 1 ? "" : "s")")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .card()
        .contextMenu {
            Button("Attach", systemImage: "arrow.right.circle") {}
            Button("Kill session", systemImage: "xmark.circle", role: .destructive) {}
        }
    }
}

#Preview {
    SessionsView()
        .environment(AppStore.preview)
        .preferredColorScheme(.dark)
}
