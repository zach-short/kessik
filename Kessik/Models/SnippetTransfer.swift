import Foundation

/// Moves snippets between phones as a JSON file. The file holds only label, text and kind:
/// never hosts, passwords or keys, and never the local ids.
enum SnippetTransfer {
    static let format = "kessik-snippets"
    static let version = 1
    static let fileName = "Kessik snippets.json"

    /// Limits for a file from anywhere. A snippet is typed into a terminal, so a longer text is
    /// dropped instead of cut short, where the cut could run a different command.
    static let maxFileBytes = 1_000_000
    static let maxSnippets = 500
    static let maxLabelLength = 100
    static let maxTextLength = 4_000

    enum ImportError: LocalizedError, Equatable {
        case tooLarge
        case notJSON
        case notSnippetFile
        case newerVersion(Int)
        case tooMany
        case empty

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The file is larger than a snippets file can be."
            case .notJSON: "The file is not a snippets file from Kessik. It is not valid JSON."
            case .notSnippetFile: "The file is not a snippets file from Kessik."
            case .newerVersion: "The file comes from a newer version of Kessik. Update the app, then import it again."
            case .tooMany: "The file has more than \(SnippetTransfer.maxSnippets) snippets."
            case .empty: "The file has no snippets that the app can use."
            }
        }
    }

    enum Mode {
        /// Keeps every snippet on the phone and adds the new ones. Skips exact copies.
        case merge
        /// Removes the snippets on the phone first.
        case replace
    }

    private struct Entry: Codable {
        var label: String?
        var text: String?
        var kind: String?

        /// A wrong type in one field drops that field, not the whole file.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try? container.decodeIfPresent(String.self, forKey: .label)
            text = try? container.decodeIfPresent(String.self, forKey: .text)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
        }

        init(_ snippet: Snippet) {
            label = snippet.label
            text = snippet.text
            kind = snippet.kind.rawValue
        }
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }

    private struct File: Codable {
        var format: String
        var version: Int
        var snippets: [Entry]
    }

    /// One JSON entry that does not decode as an object becomes nil, so it cannot fail the file.
    private struct Lenient: Decodable {
        var entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }

    private struct Body: Decodable {
        var snippets: [Lenient]
    }

    static func encode(_ snippets: [Snippet]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(format: format, version: version, snippets: snippets.map(Entry.init)))
    }

    /// Checks the file and returns clean snippets with new ids, grouped by kind.
    static func decode(_ data: Data) throws -> [Snippet] {
        guard data.count <= maxFileBytes else { throw ImportError.tooLarge }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw ImportError.notJSON }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == format, let fileVersion = header.version, fileVersion >= 1
        else { throw ImportError.notSnippetFile }
        guard fileVersion <= version else { throw ImportError.newerVersion(fileVersion) }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw ImportError.notSnippetFile }
        guard body.snippets.count <= maxSnippets else { throw ImportError.tooMany }

        let snippets = deduplicated(body.snippets.compactMap { $0.entry.flatMap(clean) })
        guard !snippets.isEmpty else { throw ImportError.empty }
        return grouped(snippets)
    }

    /// Reads a file picked in Files. Stops one byte past the limit, so a huge file is not loaded.
    static func read(_ url: URL) throws -> [Snippet] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try decode(try handle.read(upToCount: maxFileBytes + 1) ?? Data())
    }

    /// The new list for the phone. Order inside each kind is kept, existing snippets first.
    static func combine(_ existing: [Snippet], with imported: [Snippet], mode: Mode) -> [Snippet] {
        switch mode {
        case .replace:
            return grouped(deduplicated(imported))
        case .merge:
            let mine = Set(existing.map(Identity.init))
            return grouped(existing + deduplicated(imported).filter { !mine.contains(Identity($0)) })
        }
    }

    /// Same label, text and kind. The id does not count, because each phone makes its own.
    private struct Identity: Hashable {
        var label: String
        var text: String
        var kind: Snippet.Kind

        init(_ snippet: Snippet) {
            label = snippet.label
            text = snippet.text
            kind = snippet.kind
        }
    }

    private static func deduplicated(_ snippets: [Snippet]) -> [Snippet] {
        var seen = Set<Identity>()
        return snippets.filter { seen.insert(Identity($0)).inserted }
    }

    private static func grouped(_ snippets: [Snippet]) -> [Snippet] {
        Snippet.Kind.allCases.flatMap { kind in snippets.filter { $0.kind == kind } }
    }

    /// The same rules as the editor's Save, plus the limits. Nil drops the entry.
    private static func clean(_ entry: Entry) -> Snippet? {
        guard let rawKind = entry.kind, let kind = Snippet.Kind(rawValue: rawKind),
              let rawText = entry.text, rawText.count <= maxTextLength * 2 else { return nil }
        let text = stripControls(rawText, keepingLines: true).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxTextLength else { return nil }
        let rawLabel = String((entry.label ?? "").prefix(maxLabelLength * 2))
        var label = String(stripControls(rawLabel, keepingLines: false)
            .trimmingCharacters(in: .whitespaces).prefix(maxLabelLength))
        if label.isEmpty { label = String(text.prefix(maxLabelLength)) }
        return Snippet(label: label, text: text, kind: kind)
    }

    /// Removes escape and the other control characters, which could drive the terminal, and the
    /// bidirectional overrides, which could show text in an order that hides what runs.
    /// Text keeps tab and new line, which a typed command can hold. A label gets a space for each.
    private static func stripControls(_ string: String, keepingLines: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in string.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                scalars.append(!keepingLines ? " " : scalar == "\r" ? "\n" : scalar)
            } else if scalar.properties.generalCategory != .control, !bidiControls.contains(scalar.value) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static let bidiControls: Set<UInt32> = Set<UInt32>(0x202A...0x202E).union(Set<UInt32>(0x2066...0x2069))
}
