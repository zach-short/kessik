import XCTest
@testable import Kessik

final class PasteTextTests: XCTestCase {
    func testPlainPasteTurnsNewLinesIntoReturn() {
        XCTAssertEqual(PasteText.bytes("a\nb\r\nc", bracketed: false), Array("a\rb\rc".utf8))
    }

    func testBracketedPasteWrapsTheText() {
        XCTAssertEqual(PasteText.bytes("hi", bracketed: true), Array("\u{1b}[200~hi\u{1b}[201~".utf8))
    }

    func testEscapeInTheTextCannotEndThePaste() {
        let text = "a\u{1b}[201~rm -rf ~\n"
        XCTAssertEqual(PasteText.bytes(text, bracketed: true), Array("\u{1b}[200~a[201~rm -rf ~\r\u{1b}[201~".utf8))
        XCTAssertEqual(PasteText.bytes("\u{1b}[A", bracketed: false), Array("[A".utf8))
    }
}

final class ImageUploadTests: XCTestCase {
    func testPNGAndJPEGKeepTheirBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        XCTAssertEqual(ImageUpload.prepare(png)?.ext, "png")
        XCTAssertEqual(ImageUpload.prepare(png)?.data, png)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        XCTAssertEqual(ImageUpload.prepare(jpeg)?.ext, "jpg")
    }

    func testOtherImagesBecomeJPEG() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        let heicLike = image.heicData() ?? Data()
        XCTAssertEqual(ImageUpload.prepare(heicLike)?.ext, "jpg")
    }

    func testDataThatIsNoImageIsRefused() {
        XCTAssertNil(ImageUpload.prepare(Data("text".utf8)))
    }

    func testFileNameHoldsTheTime() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 10, 15, 14, 30, 12)
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(ImageUpload.fileName(at: date, ext: "png"), "image-20261015-143012.png")
    }
}

final class FileUploadTests: XCTestCase {
    func testSafeNameKeepsWordsAndExtension() {
        XCTAssertEqual(ImageUpload.safeName("My notes.pdf"), "My-notes.pdf")
        XCTAssertEqual(ImageUpload.safeName("Résumé 日本.txt"), "Résumé-日本.txt")
        XCTAssertEqual(ImageUpload.safeName("Makefile"), "Makefile")
        XCTAssertEqual(ImageUpload.safeName("a.tar.gz"), "a.tar.gz")
    }

    func testSafeNameCannotLeaveTheFolder() {
        XCTAssertEqual(ImageUpload.safeName("../x"), "x")
        XCTAssertEqual(ImageUpload.safeName("a/b\u{0}c\nd"), "a-b-c-d")
        XCTAssertEqual(ImageUpload.safeName(".env"), "env")
        XCTAssertEqual(ImageUpload.safeName(".."), "file")
        XCTAssertEqual(ImageUpload.safeName(""), "file")
    }

    func testLongNameIsShortenedButKeepsTheExtension() {
        let name = ImageUpload.safeName(String(repeating: "é", count: 300) + ".swift")
        XCTAssertTrue(name.hasSuffix(".swift"))
        XCTAssertLessThanOrEqual(name.utf8.count, 120)
    }

    func testFileNameStartsWithTheTime() {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 10, 15, 14, 30, 12)
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(ImageUpload.fileName(at: date, original: "My notes.pdf"), "20261015-143012-My-notes.pdf")
    }

    func testFilesOver100MBAreRefused() {
        XCTAssertNoThrow(try ImageUpload.checkSize(100 * 1024 * 1024))
        XCTAssertThrowsError(try ImageUpload.checkSize(100 * 1024 * 1024 + 1)) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "The file is larger than 100 MB.")
        }
    }
}
