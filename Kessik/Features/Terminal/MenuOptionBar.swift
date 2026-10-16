import SwiftUI
import UIKit

/// Claude Code's open menu as one button per option. It takes the reply row's place, at the same
/// height, so the terminal does not resize when a menu opens.
struct MenuOptionBar: View {
    let menu: ClaudeMenu
    let choose: @MainActor (ClaudeMenu.Option) -> Void
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(menu.options) { option in
                    Button {
                        // The bar goes away on this tap, so sensoryFeedback on it would not fire.
                        if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        choose(option)
                    } label: {
                        chip(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Option \(option.number), \(option.label)")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private func chip(_ option: ClaudeMenu.Option) -> some View {
        HStack(spacing: 6) {
            Text("\(option.number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.background)
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle())
            Text(Self.short(option.label))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(Theme.surfaceRaised, in: Capsule())
        // The option Claude Code has selected now, which Return would choose.
        .overlay(Capsule().strokeBorder(option.number == menu.cursor ? Theme.accent.opacity(0.7) : .clear))
    }

    /// A row that scrolls sideways gives Text all the width it asks for, so a long label, such as
    /// "Yes, and always allow access to /Users/…", is cut here.
    private static func short(_ label: String) -> String {
        label.count > 34 ? label.prefix(33).trimmingCharacters(in: .whitespaces) + "…" : label
    }
}

/// Shown while tmux shows its history after a swipe up. One tap goes back to the newest output.
struct LatestOutputButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label("Latest", systemImage: "arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to latest output")
        .padding(12)
    }
}
