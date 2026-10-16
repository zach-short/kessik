import Foundation

/// What changed in each version. The notes are data, not code: `release-notes.json` at the root of
/// the repo is the one copy, bundled into the app and imported by the site (`site/src/pages/changelog.astro`),
/// so the two cannot disagree. `ReleaseNotesTests` holds the file to its shape.
enum ReleaseNotes {
    /// The resource in the app bundle, named without its extension the way `Bundle` wants it.
    private static let resource = "release-notes"

    /// One version and everything that changed in it.
    struct Release: Codable, Identifiable, Equatable {
        /// MAJOR.MINOR.PATCH, the same string as `MARKETING_VERSION` in project.yml.
        let version: String
        /// The day the version went out, as `yyyy-MM-dd`.
        let date: String
        /// One line that describes the version.
        let headline: String
        /// The paragraph under the headline.
        let lead: String
        let changes: [Change]

        var id: String { version }

        var number: Version { Version(version) }

        /// The date as the site writes it, "16 October 2026", or the raw string when it does not parse.
        var dayLabel: String {
            guard let day = Self.parser.date(from: date) else { return date }
            return Self.display.string(from: day)
        }

        private static let parser: DateFormatter = formatter("yyyy-MM-dd", locale: "en_US_POSIX")
        private static let display: DateFormatter = formatter("d MMMM yyyy", locale: "en_GB")

        private static func formatter(_ format: String, locale: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: locale)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }

    /// One thing that changed.
    struct Change: Codable, Identifiable, Equatable {
        let kind: Kind
        /// A short noun phrase: the thing, not a sentence about it.
        let title: String
        /// What it means, in one or two sentences.
        let detail: String

        var id: String { title }
    }

    /// What a change is. Three kinds, so nobody has to choose from a longer list.
    enum Kind: String, Codable, CaseIterable {
        /// Something that was not there before.
        case new
        /// Something that was there, done better.
        case better
        /// Something that was wrong.
        case fixed

        var label: String {
            switch self {
            case .new: "New"
            case .better: "Better"
            case .fixed: "Fixed"
            }
        }
    }

    /// Every release in the bundle, newest first. Empty when the resource is missing or does not
    /// decode, because a screen that says so beats a crash.
    static var all: [Release] { loaded }

    /// The release for this build's version, or nil on a build the file does not cover.
    static var current: Release? {
        guard let version = bundleVersion else { return nil }
        return loaded.first { $0.number == version }
    }

    /// `CFBundleShortVersionString` as numbers.
    static var bundleVersion: Version? {
        guard let string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !string.isEmpty else { return nil }
        return Version(string)
    }

    /// Decodes the file's bytes. Separate from `loaded` so a test can hold the real file to the same decoder.
    static func decode(_ data: Data) throws -> [Release] {
        try JSONDecoder().decode(File.self, from: data).versions
    }

    /// The file's top level. `$comment` is for whoever opens the file and is not decoded.
    private struct File: Codable {
        let versions: [Release]
    }

    private static let loaded: [Release] = {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? decode(data) else { return [] }
        return releases
    }()
}

/// A marketing version as three numbers, so `1.10.0` sorts above `1.9.0` and `1.1` equals `1.1.0`,
/// neither of which a string comparison gets right. A missing or non-numeric part counts as zero.
struct Version: Comparable, Hashable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        major = parts.count > 0 ? parts[0] : 0
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
