import Foundation

/// The history of a tmux pane as plain lines, and a literal, case-insensitive search over it.
/// tmux owns the scrollback (SwiftTerm only holds the visible screen), so the text comes from
/// `tmux capture-pane` on its own exec channel.
struct Scrollback: Sendable {
    /// Lines of history to read. More would make the capture and the list slow on a phone.
    static let maxLines = 10_000
    /// A stop for very long lines. 10,000 full lines of a wide pane fit well under this.
    static let maxBytes = 8 * 1024 * 1024

    /// `-p` prints to stdout. Without `-e` tmux sends no escape sequences, so the text is plain.
    /// `-J` joins lines that the pane wrapped. `-S -N` starts N lines back in the history, and the
    /// capture runs to the end of the visible screen. The target needs the trailing `:`, or tmux
    /// reads `=name` as a pane and finds no session.
    static func captureCommand(session name: String, lines: Int = maxLines) -> String {
        Tmux.pathPrefix + "tmux capture-pane -p -J -S -\(lines) -t \(Tmux.quote("=" + name + ":"))"
    }

    let lines: [String]

    /// `-J` keeps trailing spaces, and the empty rows below the cursor come out as blank lines.
    /// Both go, so the newest line is the last one.
    init(output: String, maxLines: Int = Scrollback.maxLines) {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.reversed().drop(while: { $0 == " " || $0 == "\r" || $0 == "\t" }).reversed())
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        self.lines = Array(lines.suffix(maxLines))
    }

    struct Hit: Identifiable, Equatable, Sendable {
        /// The line's index in `lines`.
        let id: Int
        let line: String
        let ranges: [Range<String.Index>]
        let before: [String]
        let after: [String]
    }

    /// Lines that hold `query`, oldest first, so the newest is last as in the terminal.
    /// An empty query matches nothing.
    func search(_ query: String, context: Int = 1) -> [Hit] {
        guard !query.isEmpty else { return [] }
        return lines.indices.compactMap { index in
            let ranges = Scrollback.occurrences(of: query, in: lines[index])
            guard !ranges.isEmpty else { return nil }
            let before = lines[max(0, index - context)..<index]
            let after = lines[(index + 1)..<min(lines.count, index + 1 + context)]
            return Hit(id: index, line: lines[index], ranges: ranges, before: Array(before), after: Array(after))
        }
    }

    /// Every place the query appears, without overlap. Without `.regularExpression`, `range(of:)`
    /// reads the query as plain text, so `.` or `*` match only themselves.
    static func occurrences(of query: String, in line: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = line.startIndex
        while start < line.endIndex,
              let range = line.range(of: query, options: .caseInsensitive, range: start..<line.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }

    /// The number of matches, not of lines: a line that holds the query twice counts twice.
    static func matchCount(_ hits: [Hit]) -> Int {
        hits.reduce(0) { $0 + $1.ranges.count }
    }

    /// The line cut into plain and matched pieces, in order, for highlighting.
    static func segments(_ line: String, ranges: [Range<String.Index>]) -> [(text: String, match: Bool)] {
        var parts: [(text: String, match: Bool)] = []
        var cursor = line.startIndex
        for range in ranges {
            if cursor < range.lowerBound { parts.append((String(line[cursor..<range.lowerBound]), false)) }
            parts.append((String(line[range]), true))
            cursor = range.upperBound
        }
        if cursor < line.endIndex { parts.append((String(line[cursor...]), false)) }
        return parts
    }
}
