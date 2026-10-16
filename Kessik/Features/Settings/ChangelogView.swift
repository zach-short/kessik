import SwiftUI

/// Settings > Changelog: every version in `release-notes.json`, newest first. The site shows the
/// same file at kessik.com/changelog.
struct ChangelogView: View {
    private let releases = ReleaseNotes.all
    private let current = ReleaseNotes.bundleVersion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(lead)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                if releases.isEmpty {
                    Text("The notes for this build could not be read. kessik.com/changelog has them.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .card()
                } else {
                    ForEach(releases) { release in
                        SectionLabel("\(release.version) · \(release.dayLabel)")
                            .padding(.top, 8)
                        ReleaseCard(release: release, isCurrent: release.number == current)
                    }
                    Text("The same notes are at kessik.com/changelog.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Says which version this build is, and what it was about.
    private var lead: String {
        if let release = ReleaseNotes.current {
            return "You are on \(release.version). \(release.headline) Every version is below, newest first."
        }
        return "Each version of Kessik, newest first."
    }
}

private struct ReleaseCard: View {
    let release: ReleaseNotes.Release
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if isCurrent {
                    Text("THIS BUILD")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.warning)
                }
                Text(release.headline)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(release.lead)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            ForEach(release.changes) { change in
                Divider().overlay(Theme.stroke)
                ChangeRow(change: change)
            }
        }
        .card()
    }
}

/// The kind is a word as well as a color, so the row reads the same without color.
private struct ChangeRow: View {
    let change: ReleaseNotes.Change

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.kind.label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(color)
            Text(change.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(change.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch change.kind {
        case .new: Theme.online
        case .better: Theme.warning
        case .fixed: Theme.accent
        }
    }
}

#Preview {
    NavigationStack { ChangelogView() }
        .preferredColorScheme(.dark)
}
