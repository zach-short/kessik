import XCTest
@testable import Kessik

final class ReleaseNotesTests: XCTestCase {
    /// release-notes.json at the root of the repo, found from this file so the test reads the source copy.
    private var sourceFile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("release-notes.json")
    }

    private func sourceReleases() throws -> [ReleaseNotes.Release] {
        try ReleaseNotes.decode(Data(contentsOf: sourceFile))
    }

    // MARK: The file

    func testSourceFileDecodes() throws {
        XCTAssertFalse(try sourceReleases().isEmpty)
    }

    func testAppBundleCarriesTheNotes() {
        XCTAssertFalse(ReleaseNotes.all.isEmpty, "release-notes.json is not in the app bundle")
    }

    func testBundledCopyMatchesTheSourceFile() throws {
        XCTAssertEqual(ReleaseNotes.all, try sourceReleases())
    }

    func testVersionsAreUniqueAndNewestFirst() throws {
        let numbers = try sourceReleases().map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count, "a version appears twice")
        XCTAssertEqual(numbers, numbers.sorted(by: >), "versions must run newest first")
    }

    func testEveryReleaseIsComplete() throws {
        for release in try sourceReleases() {
            XCTAssertNotEqual(release.dayLabel, release.date, "\(release.version) has a date that does not parse")
            XCTAssertFalse(release.headline.isEmpty, "\(release.version) has no headline")
            XCTAssertFalse(release.lead.isEmpty, "\(release.version) has no lead")
            XCTAssertFalse(release.changes.isEmpty, "\(release.version) lists no changes")
            XCTAssertEqual(Set(release.changes.map(\.title)).count, release.changes.count,
                           "\(release.version) repeats a change title")
            for change in release.changes {
                XCTAssertFalse(change.title.isEmpty)
                XCTAssertFalse(change.detail.isEmpty, "\(change.title) has no detail")
            }
        }
    }

    /// A bump of MARKETING_VERSION with no entry for it fails here, and in scripts/archive.sh.
    func testNewestEntryIsThisBuildsVersion() throws {
        let newest = try XCTUnwrap(ReleaseNotes.all.first)
        XCTAssertEqual(newest.number, ReleaseNotes.bundleVersion)
        XCTAssertNotNil(ReleaseNotes.current)
    }

    // MARK: The pieces

    func testDayLabelUsesTheSitesFormat() {
        let release = ReleaseNotes.Release(version: "1.0.0", date: "2026-10-16", headline: "h", lead: "l", changes: [])
        XCTAssertEqual(release.dayLabel, "16 October 2026")
    }

    func testDayLabelFallsBackToTheRawStringWhenItDoesNotParse() {
        let release = ReleaseNotes.Release(version: "1.0.0", date: "soon", headline: "h", lead: "l", changes: [])
        XCTAssertEqual(release.dayLabel, "soon")
    }

    func testVersionsCompareAsNumbers() {
        XCTAssertGreaterThan(Version("1.10.0"), Version("1.9.0"))
        XCTAssertEqual(Version("1.1"), Version("1.1.0"))
        XCTAssertLessThan(Version("1.0.9"), Version("1.1.0"))
    }

    func testDecodeIgnoresTheCommentAndRejectsAnUnknownKind() throws {
        let good = Data(#"{"$comment":"x","versions":[{"version":"1.0.0","date":"2026-10-16","headline":"h","lead":"l","changes":[{"kind":"fixed","title":"t","detail":"d"}]}]}"#.utf8)
        XCTAssertEqual(try ReleaseNotes.decode(good).first?.changes.first?.kind, .fixed)

        let bad = Data(#"{"versions":[{"version":"1.0.0","date":"2026-10-16","headline":"h","lead":"l","changes":[{"kind":"removed","title":"t","detail":"d"}]}]}"#.utf8)
        XCTAssertThrowsError(try ReleaseNotes.decode(bad))
    }
}
