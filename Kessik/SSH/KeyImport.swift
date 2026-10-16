import Foundation
import CryptoKit
import Citadel

/// Reads an OpenSSH private key file (`-----BEGIN OPENSSH PRIVATE KEY-----`) into an ed25519 key.
/// Citadel does the decoding and the passphrase decryption. This type reads the file header first,
/// because Citadel's errors do not say why a key failed, and the user needs to know.
enum KeyImport {
    enum Failure: LocalizedError, Equatable {
        case notAKey
        case publicKey
        case otherFormat(String)
        case unsupportedType(String)
        case passphraseNeeded
        case wrongPassphrase
        case unsupportedEncryption(String)
        case damaged

        var errorDescription: String? {
            switch self {
            case .notAKey:
                return "This is not an OpenSSH private key. Paste the whole file, from the BEGIN OPENSSH PRIVATE KEY line to the END line."
            case .publicKey:
                return "This is a public key. Import the private key file, the one without .pub at the end."
            case .otherFormat(let format):
                return "This key is in \(format) format. On the Mac, run `ssh-keygen -p -f <file>` on a copy of the key to save it in OpenSSH format, then import it again."
            case .unsupportedType(let type):
                return "Kessik cannot use \(type) keys. It logs in with ed25519 keys only. Make one on the Mac with `ssh-keygen -t ed25519`, or generate one here."
            case .passphraseNeeded:
                return "This key has a passphrase. Type it to import the key."
            case .wrongPassphrase:
                return "The passphrase is wrong."
            case .unsupportedEncryption(let cipher):
                return "This key is encrypted with \(cipher), which Kessik cannot read. Encrypted keys need aes256-ctr or aes128-ctr. On the Mac, run `ssh-keygen -p -f <file>` on a copy of the key and set an empty passphrase, then import the copy."
            case .damaged:
                return "The key is damaged or incomplete. Copy the whole file again."
            }
        }
    }

    /// The unencrypted part of an OpenSSH private key file.
    struct Header: Equatable {
        var cipher: String
        var kdf: String
        var keyType: String
        /// The public key blob: key type and key bytes, as in an `authorized_keys` line.
        var publicBlob: Data

        var isEncrypted: Bool { cipher != "none" }
    }

    private static let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let end = "-----END OPENSSH PRIVATE KEY-----"
    private static let magic = Data("openssh-key-v1".utf8) + [0]
    /// The ciphers Citadel 0.12.0 decrypts, with the bcrypt KDF.
    private static let readableCiphers: Set<String> = ["aes128-ctr", "aes256-ctr"]

    /// Ed25519 key from `text`. `passphrase` is used only when the key is encrypted.
    static func parse(_ text: String, passphrase: String? = nil) throws -> Curve25519.Signing.PrivateKey {
        let body = try base64Body(of: text)
        guard let data = Data(base64Encoded: body) else { throw Failure.damaged }
        let header = try readHeader(data)
        guard header.keyType == "ssh-ed25519" else { throw Failure.unsupportedType(typeName(header.keyType)) }

        var decryptionKey: Data?
        if header.isEncrypted {
            guard header.kdf == "bcrypt", readableCiphers.contains(header.cipher) else {
                throw Failure.unsupportedEncryption(header.cipher)
            }
            guard let passphrase, !passphrase.isEmpty else { throw Failure.passphraseNeeded }
            decryptionKey = Data(passphrase.utf8)
        }

        let key: Curve25519.Signing.PrivateKey
        do {
            // Citadel removes only "\n", so it gets the key on one line with no other whitespace.
            key = try Curve25519.Signing.PrivateKey(sshEd25519: begin + body + end, decryptionKey: decryptionKey)
        } catch {
            // With a readable cipher, a decryption with the wrong passphrase fails the check numbers.
            throw header.isEncrypted ? Failure.wrongPassphrase : Failure.damaged
        }
        // The file's public half must belong to the private half, or the Mac would reject every login.
        guard publicBlob(for: key) == header.publicBlob else { throw Failure.damaged }
        return key
    }

    /// The header of `text`, without decrypting it.
    static func header(of text: String) throws -> Header {
        guard let data = Data(base64Encoded: try base64Body(of: text)) else { throw Failure.damaged }
        return try readHeader(data)
    }

    /// `SHA256:…` as `ssh-keygen -l` prints it.
    static func fingerprint(for key: Curve25519.Signing.PrivateKey) -> String {
        fingerprint(blob: publicBlob(for: key))
    }

    /// The fingerprint of an `authorized_keys` line, or nil when the line has no key.
    static func fingerprint(ofLine line: String) -> String? {
        let fields = line.split(separator: " ")
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])) else { return nil }
        return fingerprint(blob: blob)
    }

    private static func fingerprint(blob: Data) -> String {
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }

    private static func publicBlob(for key: Curve25519.Signing.PrivateKey) -> Data {
        var blob = Data()
        appendString(Data("ssh-ed25519".utf8), to: &blob)
        appendString(key.publicKey.rawRepresentation, to: &blob)
        return blob
    }

    private static func appendString(_ bytes: Data, to data: inout Data) {
        withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(bytes)
    }

    /// The base64 text between the OpenSSH markers, with all whitespace removed.
    /// Throws a specific error for the other key formats people paste by mistake.
    private static func base64Body(of text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.range(of: begin), let stop = trimmed.range(of: end, range: start.upperBound..<trimmed.endIndex) else {
            throw otherFormatFailure(trimmed)
        }
        return String(trimmed[start.upperBound..<stop.lowerBound].unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        })
    }

    private static func otherFormatFailure(_ text: String) -> Failure {
        if text.hasPrefix("ssh-") || text.hasPrefix("ecdsa-sha2-") { return .publicKey }
        if text.contains("BEGIN RSA PRIVATE KEY") { return .unsupportedType("RSA") }
        if text.contains("BEGIN EC PRIVATE KEY") { return .unsupportedType("ECDSA") }
        if text.contains("BEGIN DSA PRIVATE KEY") { return .unsupportedType("DSA") }
        if text.contains("BEGIN PRIVATE KEY") || text.contains("BEGIN ENCRYPTED PRIVATE KEY") { return .otherFormat("PKCS#8 (PEM)") }
        if text.hasPrefix("PuTTY-User-Key-File") { return .otherFormat("PuTTY") }
        return .notAKey
    }

    private static func readHeader(_ data: Data) throws -> Header {
        var reader = Reader(data: data)
        guard reader.read(count: magic.count) == magic,
              let cipher = reader.readString().flatMap({ String(data: $0, encoding: .utf8) }),
              let kdf = reader.readString().flatMap({ String(data: $0, encoding: .utf8) }),
              reader.readString() != nil,
              let count = reader.readUInt32()
        else { throw Failure.notAKey }
        guard count == 1, let blob = reader.readString() else { throw Failure.damaged }
        var blobReader = Reader(data: blob)
        guard let type = blobReader.readString().flatMap({ String(data: $0, encoding: .utf8) }) else { throw Failure.damaged }
        return Header(cipher: cipher, kdf: kdf, keyType: type, publicBlob: blob)
    }

    private static func typeName(_ keyType: String) -> String {
        switch keyType {
        case "ssh-rsa": return "RSA"
        case "ssh-dss": return "DSA"
        case _ where keyType.hasPrefix("ecdsa-"): return "ECDSA"
        case _ where keyType.hasPrefix("sk-"): return "security key"
        default: return keyType
        }
    }

    /// Reads the length-prefixed fields of the OpenSSH key format.
    private struct Reader {
        let data: Data
        var offset = 0

        init(data: Data) { self.data = Data(data) }

        mutating func read(count: Int) -> Data? {
            guard count >= 0, data.count - offset >= count else { return nil }
            defer { offset += count }
            return data.subdata(in: offset..<offset + count)
        }

        mutating func readUInt32() -> UInt32? {
            read(count: 4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
        }

        mutating func readString() -> Data? {
            guard let length = readUInt32(), length <= UInt32(Int32.max) else { return nil }
            return read(count: Int(length))
        }
    }
}
