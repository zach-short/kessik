import Foundation
import UIKit
import Citadel
import NIOCore

/// Copies an image from the phone to the Mac over SFTP, so its path can go into a Claude prompt.
enum ImageUpload {
    struct Unreadable: LocalizedError {
        var errorDescription: String? { "The image could not be read." }
    }

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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "image-\(formatter.string(from: date)).\(ext)"
    }

    /// Returns the path of the file on the Mac.
    static func upload(_ data: Data, client: SSHClient) async throws -> String {
        guard let prepared = prepare(data) else { throw Unreadable() }
        let path = "\(folder)/\(fileName(at: .now, ext: prepared.ext))"
        let buffer = ByteBuffer(bytes: prepared.data)
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
