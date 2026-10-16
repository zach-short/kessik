import Foundation
import CryptoKit
import CommonCrypto
import NIOCore
import Citadel
import CCitadelBcrypt

/// Reads an OpenSSH private key file (`-----BEGIN OPENSSH PRIVATE KEY-----`) into an ed25519 or ECDSA key.
/// Citadel decodes and decrypts ed25519 keys. This type reads the file header first, because Citadel's
/// errors do not say why a key failed, and the user needs to know. Citadel cannot read ECDSA keys, so this
/// type reads them itself, with Citadel's bcrypt KDF and CommonCrypto's AES-CTR for an encrypted key.
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
                return "Kessik cannot use \(type) keys. It logs in with ed25519 and ECDSA keys only. Make one on the Mac with `ssh-keygen -t ed25519`, or generate one here."
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

    /// The unencrypted part of an OpenSSH private key file, and the private half as stored.
    struct Header: Equatable {
        var cipher: String
        var kdf: String
        var keyType: String
        /// The public key blob: key type and key bytes, as in an `authorized_keys` line.
        var publicBlob: Data
        /// The bcrypt salt and rounds of an encrypted key.
        var kdfOptions: Data
        /// The private half, still encrypted when the key has a passphrase.
        var privateSection: Data

        var isEncrypted: Bool { cipher != "none" }
    }

    private static let begin = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let end = "-----END OPENSSH PRIVATE KEY-----"
    private static let magic = Data("openssh-key-v1".utf8) + [0]
    /// The ciphers Citadel 0.12.0 decrypts, with the bcrypt KDF. ECDSA keys get the same two.
    private static let readableCiphers: Set<String> = ["aes128-ctr", "aes256-ctr"]
    /// The private scalar size of each ECDSA curve. NIOSSH signs with all three.
    private static let ecdsaSizes = ["ecdsa-sha2-nistp256": 32, "ecdsa-sha2-nistp384": 48, "ecdsa-sha2-nistp521": 66]

    /// Ed25519 or ECDSA key from `text`. `passphrase` is used only when the key is encrypted.
    static func parse(_ text: String, passphrase: String? = nil) throws -> DeviceKey.Key {
        let body = try base64Body(of: text)
        guard let data = Data(base64Encoded: body) else { throw Failure.damaged }
        let header = try readHeader(data)
        guard header.keyType == "ssh-ed25519" || ecdsaSizes[header.keyType] != nil else {
            throw Failure.unsupportedType(typeName(header.keyType))
        }

        var decryptionKey: Data?
        if header.isEncrypted {
            guard header.kdf == "bcrypt", readableCiphers.contains(header.cipher) else {
                throw Failure.unsupportedEncryption(header.cipher)
            }
            guard let passphrase, !passphrase.isEmpty else { throw Failure.passphraseNeeded }
            decryptionKey = Data(passphrase.utf8)
        }

        let key: DeviceKey.Key
        if header.keyType == "ssh-ed25519" {
            do {
                // Citadel removes only "\n", so it gets the key on one line with no other whitespace.
                key = .ed25519(try Curve25519.Signing.PrivateKey(sshEd25519: begin + body + end, decryptionKey: decryptionKey))
            } catch {
                // With a readable cipher, a decryption with the wrong passphrase fails the check numbers.
                throw header.isEncrypted ? Failure.wrongPassphrase : Failure.damaged
            }
        } else {
            key = try ecdsaKey(header, passphrase: decryptionKey)
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
    static func fingerprint(for key: DeviceKey.Key) -> String {
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

    private static func publicBlob(for key: DeviceKey.Key) -> Data {
        var buffer = ByteBuffer()
        key.sshKey.publicKey.write(to: &buffer)
        return Data(buffer.readableBytesView)
    }

    /// Reads the private half of an ECDSA key: check numbers, key type, curve, public point, private scalar.
    private static func ecdsaKey(_ header: Header, passphrase: Data?) throws -> DeviceKey.Key {
        let section = try passphrase.map { try decrypt(header, passphrase: $0) } ?? header.privateSection
        var reader = Reader(data: section)
        guard let check0 = reader.readUInt32(), let check1 = reader.readUInt32() else { throw Failure.damaged }
        // A wrong passphrase decrypts to noise, so the two check numbers differ.
        guard check0 == check1 else { throw header.isEncrypted ? Failure.wrongPassphrase : Failure.damaged }
        guard reader.readString() == Data(header.keyType.utf8),
              reader.readString() != nil,
              reader.readString() != nil,
              let scalar = reader.readString(),
              let size = ecdsaSizes[header.keyType]
        else { throw Failure.damaged }
        // The scalar is an SSH mpint: it can have a leading zero byte, or be shorter than the curve size.
        let digits = scalar.drop(while: { $0 == 0 })
        guard digits.count <= size, let key = DeviceKey.Key(ecdsaRaw: Data(count: size - digits.count) + digits) else {
            throw Failure.damaged
        }
        return key
    }

    /// The private half decrypted as `ssh-keygen` encrypts it: bcrypt makes the key and IV, then AES-CTR.
    private static func decrypt(_ header: Header, passphrase: Data) throws -> Data {
        var options = Reader(data: header.kdfOptions)
        guard let salt = options.readString(), let rounds = options.readUInt32(), sha512Ready else { throw Failure.damaged }
        let keyLength = header.cipher == "aes256-ctr" ? kCCKeySizeAES256 : kCCKeySizeAES128
        var material = [UInt8](repeating: 0, count: keyLength + kCCBlockSizeAES128)
        let derived = passphrase.withUnsafeBytes { pass in
            salt.withUnsafeBytes { salt in
                citadel_bcrypt_pbkdf(pass.bindMemory(to: UInt8.self).baseAddress, pass.count,
                                     salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     &material, material.count, rounds)
            }
        }
        guard derived == 0 else { throw Failure.damaged }

        var cryptor: CCCryptorRef?
        guard CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                      CCPadding(ccNoPadding), Array(material[keyLength...]), Array(material[..<keyLength]),
                                      keyLength, nil, 0, 0, 0, &cryptor) == CCCryptorStatus(kCCSuccess)
        else { throw Failure.damaged }
        defer { CCCryptorRelease(cryptor) }
        var plain = Data(count: header.privateSection.count)
        var moved = 0
        let status = plain.withUnsafeMutableBytes { out in
            header.privateSection.withUnsafeBytes { input in
                CCCryptorUpdate(cryptor, input.baseAddress, input.count, out.baseAddress, out.count, &moved)
            }
        }
        guard status == CCCryptorStatus(kCCSuccess), moved == plain.count else { throw Failure.damaged }
        return plain
    }

    /// Citadel's bcrypt needs a SHA-512 function, and Citadel sets one only on its own decryption path.
    private static let sha512Ready: Bool = {
        citadel_set_crypto_hash_sha512 { out, input, length in
            guard let out else { return }
            let digest = SHA512.hash(data: UnsafeRawBufferPointer(start: input, count: Int(length)))
            for (index, byte) in digest.enumerated() { out[index] = byte }
        }
        return true
    }()

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
        if text.contains("BEGIN EC PRIVATE KEY") { return .otherFormat("PEM") }
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
              let kdfOptions = reader.readString(),
              let count = reader.readUInt32()
        else { throw Failure.notAKey }
        guard count == 1, let blob = reader.readString(), let privateSection = reader.readString() else { throw Failure.damaged }
        var blobReader = Reader(data: blob)
        guard let type = blobReader.readString().flatMap({ String(data: $0, encoding: .utf8) }) else { throw Failure.damaged }
        return Header(cipher: cipher, kdf: kdf, keyType: type, publicBlob: blob, kdfOptions: kdfOptions, privateSection: privateSection)
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
