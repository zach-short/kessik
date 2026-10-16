import SwiftUI
import UIKit
import Citadel
import NIOCore

/// Reads the tmux history of the open session and searches it. With an empty search field the
/// whole history shows; with text, only the matching lines, each with the lines around it.
/// A tap copies a line.
struct ScrollbackSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let client: SSHClient
    let session: String
    @State private var scrollback: Scrollback?
    @State private var loadError: String?
    @State private var query = ""
    @State private var hits: [Scrollback.Hit] = []
    /// The query that `hits` belongs to. It trails `query` while a search runs.
    @State private var searched = ""
    @State private var copied = false
    /// Counts finished reads, so a search runs again on new history.
    @State private var reads = 0

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationTitle("Search the scrollback")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find text")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Read again", systemImage: "arrow.clockwise") {
                            Task { await load() }
                        }
                        .disabled(scrollback == nil && loadError == nil)
                    }
                }
                .safeAreaInset(edge: .bottom) { footer }
        }
        .task { await load() }
        .task(id: SearchKey(query: query, reads: reads)) { await search() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let loadError {
            VStack(spacing: 12) {
                Label("Could not read the history", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Theme.warning)
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again", systemImage: "arrow.clockwise") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        } else if let scrollback {
            if query.isEmpty {
                lineList(scrollback)
            } else if hits.isEmpty, searched == query {
                Text("No matches")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                hitList
            }
        } else {
            ProgressView("Reading the history…")
        }
    }

    /// The newest line is at the bottom, as in the terminal, and the list opens there.
    private func lineList(_ scrollback: Scrollback) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(scrollback.lines.indices, id: \.self) { index in
                    let line = scrollback.lines[index]
                    Text(line.isEmpty ? " " : line)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { copy(line) }
                }
            }
            .padding(.vertical, 8)
        }
        .defaultScrollAnchor(.bottom)
    }

    private var hitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(hits) { hit in
                    hitRow(hit)
                }
            }
            .padding(12)
        }
        .defaultScrollAnchor(.bottom)
        // A new search opens at its newest match.
        .id(searched)
    }

    private func hitRow(_ hit: Scrollback.Hit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(hit.before.enumerated()), id: \.offset) { _, line in contextLine(line) }
            Text(highlighted(hit))
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(hit.after.enumerated()), id: \.offset) { _, line in contextLine(line) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { copy(hit.line) }
        .contextMenu {
            Button("Copy line", systemImage: "doc.on.doc") { copy(hit.line) }
            Button("Copy with context", systemImage: "text.alignleft") {
                copy((hit.before + [hit.line] + hit.after).joined(separator: "\n"))
            }
        }
        .accessibilityHint("Copies the line")
    }

    private func contextLine(_ line: String) -> some View {
        Text(line.isEmpty ? " " : line)
            .font(Theme.mono)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
    }

    private func highlighted(_ hit: Scrollback.Hit) -> AttributedString {
        var text = AttributedString()
        for part in Scrollback.segments(hit.line, ranges: hit.ranges) {
            var piece = AttributedString(part.text)
            if part.match {
                piece.backgroundColor = Theme.accent.opacity(0.3)
                piece.foregroundColor = Theme.accent
            }
            text += piece
        }
        return text
    }

    private var footer: some View {
        Text(footerText)
            .font(.caption)
            .foregroundStyle(copied ? Theme.online : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
    }

    private var footerText: String {
        if copied { return "Copied" }
        guard let scrollback else { return " " }
        if query.isEmpty {
            return "\(scrollback.lines.count) lines. Tap a line to copy it."
        }
        guard searched == query else { return "Searching…" }
        let count = Scrollback.matchCount(hits)
        return "\(count) \(count == 1 ? "match" : "matches") in \(hits.count) \(hits.count == 1 ? "line" : "lines")"
    }

    // MARK: Actions

    private func load() async {
        loadError = nil
        do {
            let command = Scrollback.captureCommand(session: session)
            let client = client
            let output = try await withTimeout(20) {
                try await client.executeCommand(command, maxResponseSize: Scrollback.maxBytes)
            }
            // Splitting 10,000 lines takes a moment, so it runs off the main thread.
            scrollback = await Task.detached { Scrollback(output: String(buffer: output)) }.value
            reads += 1
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// Runs after a short pause, so typing a word does not search once per letter.
    private func search() async {
        guard let scrollback, !query.isEmpty else {
            hits = []
            searched = query
            return
        }
        let query = query
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let found = await Task.detached { scrollback.search(query) }.value
        guard !Task.isCancelled else { return }
        hits = found
        searched = query
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    static func message(for error: Error) -> String {
        if error is TimedOut { return "The Mac did not answer in time." }
        if case CitadelError.commandOutputTooLarge = error { return "The history is too large to read." }
        if error is SSHClient.CommandFailed { return "tmux could not read this session. It may have closed." }
        return "The history could not be read: \(error.localizedDescription)"
    }

    private struct SearchKey: Equatable {
        let query: String
        let reads: Int
    }
}
