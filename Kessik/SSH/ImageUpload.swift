import Foundation
import UIKit
import Citadel
import NIOCore

/// Copies an image or any other file from the phone to the Mac over SFTP, so its path can go into a Claude prompt.
enum ImageUpload {
    struct Unreadable: LocalizedError {
        var errorDescription: String? { "The image could not be read." }
    }

    struct FileUnreadable: LocalizedError {
        var errorDescription: String? { "The file could not be read." }
    }

    struct TooLarge: LocalizedError {
        var errorDescription: String? { "The file is larger than 100 MB." }
    }

    /// The whole file goes into memory before it is sent, so very large files are refused.
    static let maxFileSize = 100 * 1024 * 1024

    /// macOS clears /tmp on restart, which suits screenshots meant for one prompt.
    static let folder = "/tmp/kessik"

    /// PNG, JPEG and GIF go as they are. Anything else, such as a HEIC photo, becomes JPEG,
    /// because Claude Code does not read HEIC.
    static func prepare(_ data: Data) -> (data: Data, ext: String)? {
        let head = [UInt8](data.prefix(4))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "png") }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "jpg") }
        if head.starts(with: [0x47, 0x49, 0x46]) { return (data, "gif") }
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else { return nil }
        return (jpeg, "jpg")
    }

    /// For example `image-20261015-143012.png`. The time keeps two uploads apart.
    static func fileName(at date: Date, ext: String) -> String {
        "image-\(stamp(date)).\(ext)"
    }

    /// For example `20261015-143012-My-notes.pdf`. The time keeps two uploads apart, and the
    /// original name tells Claude what the file is.
    static func fileName(at date: Date, original: String) -> String {
        "\(stamp(date))-\(safeName(original))"
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// Keeps letters, digits, `.`, `-` and `_`, and makes the rest `-`, so the path needs no quotes.
    /// Drops leading dots and dashes, and shortens long names but keeps the extension.
    static func safeName(_ name: String) -> String {
        let mapped = String(name.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "-" })
        let trimmed = String(mapped.drop { $0 == "." || $0 == "-" })
        var stem = trimmed
        var ext = ""
        if let dot = trimmed.lastIndex(of: "."), trimmed.distance(from: dot, to: trimmed.endIndex) <= 17 {
            stem = String(trimmed[..<dot])
            ext = String(trimmed[dot...])
        }
        while stem.utf8.count > 100 { stem.removeLast() }
        if stem.isEmpty { stem = "file" }
        return stem + ext
    }

    /// Throws when the file is too large to send.
    static func checkSize(_ bytes: Int) throws {
        guard bytes <= maxFileSize else { throw TooLarge() }
    }

    /// Reads a file picked in Files, away from the main thread. Returns its bytes and its name.
    static func read(_ url: URL) async throws -> (data: Data, name: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw FileUnreadable() }
        try checkSize(size)
        guard let data = try? Data(contentsOf: url) else { throw FileUnreadable() }
        return (data, url.lastPathComponent)
    }

    /// Returns the path of the image on the Mac.
    static func upload(_ data: Data, client: SSHClient) async throws -> String {
        guard let prepared = prepare(data) else { throw Unreadable() }
        return try await send(prepared.data, name: fileName(at: .now, ext: prepared.ext), client: client)
    }

    /// Sends the file as it is. Returns its path on the Mac.
    static func upload(_ data: Data, original: String, client: SSHClient) async throws -> String {
        try checkSize(data.count)
        return try await send(data, name: fileName(at: .now, original: original), client: client)
    }

    private static func send(_ data: Data, name: String, client: SSHClient) async throws -> String {
        let path = "\(folder)/\(name)"
        let buffer = ByteBuffer(bytes: data)
        try await client.withSFTP { sftp in
            // Fails when the folder exists, which is fine.
            try? await sftp.createDirectory(atPath: folder)
            try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                try await file.write(buffer)
            }
        }
        return path
    }
}
