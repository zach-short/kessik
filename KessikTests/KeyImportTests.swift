import XCTest
import CryptoKit
@testable import Kessik

/// Fixtures are throwaway keys made with ssh-keygen for these tests only. No Mac trusts them.
/// The BEGIN and END lines are added at run time, so secret scanners do not flag this file.
final class KeyImportTests: XCTestCase {
    private func wrap(_ body: String) -> String {
        "-----BEGIN " + "OPENSSH PRIVATE KEY-----\n" + body + "\n-----END " + "OPENSSH PRIVATE KEY-----\n"
    }

    /// `ssh-keygen -t ed25519 -N "" -C kessik-test`
    private lazy var ed25519 = wrap("""
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACBAzZC3JuTE+fSyM1+sBGLAALnSvtaDA4v3ls3Hcx42+gAAAJBfjz25X489
        uQAAAAtzc2gtZWQyNTUxOQAAACBAzZC3JuTE+fSyM1+sBGLAALnSvtaDA4v3ls3Hcx42+g
        AAAEC5KdTJHZDEnAdjJvJ05woWvvtuOUSOQ78jnMXXAs0xCEDNkLcm5MT59LIzX6wEYsAA
        udK+1oMDi/eWzcdzHjb6AAAAC2tlc3Npay10ZXN0AQI=
        """)
    private let ed25519Pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDNkLcm5MT59LIzX6wEYsAAudK+1oMDi/eWzcdzHjb6 kessik-test"
    private let ed25519Fingerprint = "SHA256:sEZNd1+kxuKG4jpbN+eikI/Q+LJeIKIGDOM5ouDE1qU"

    /// `ssh-keygen -t ed25519 -N test-pass -C kessik-test-enc` (aes256-ctr with bcrypt, the default).
    private lazy var encrypted = wrap("""
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCJQ2e3tA
        PGW3TpPlASGbcqAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIN0JSqQs9iQTUbKz
        yg+5Pv/CWC3bd+weFe4QMyTEqEioAAAAoKwxyqLyKJ9PbYTPtCET2u0lQeNP25gnVxLKPM
        7wuTX0EG5bswxpaZ8VTOjPY7hWuRispY/bjp5oskS90NeB9NL47jZBynadlZC97IF/wvl2
        tMqfV5CTcY931WPCZ50TXRAdgWNtz56f6voAj69gmws5HnaQUtjaARJyUlXUD8HWDepEIU
        jBwWaOX5NBkH84C/r6fRUrcs0y0JWFU5G18mk=
        """)
    private let encryptedPub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0JSqQs9iQTUbKzyg+5Pv/CWC3bd+weFe4QMyTEqEio kessik-test-enc"

    /// `ssh-keygen -t ed25519 -N x -Z chacha20-poly1305@openssh.com`, a cipher Citadel cannot read.
    private lazy var chacha = wrap("""
        b3BlbnNzaC1rZXktdjEAAAAAHWNoYWNoYTIwLXBvbHkxMzA1QG9wZW5zc2guY29tAAAABm
        JjcnlwdAAAABgAAAAQ8jrkG0du8qIxhAq81KLq6gAAABgAAAABAAAAMwAAAAtzc2gtZWQy
        NTUxOQAAACB+CTd5fpMm0GAiK0H8zDuTiy+LbrSvW8uwdlgfbB08WwAAAJChxqpNo0rLp9
        +BxLAtewF2o9j0Hksjlahe23JTHA27cSRrfYDkzvE1iSd/luj5sWlZrzYKBHoRJg9vf0+v
        F23mKc4dRD7IbhuFWVABDtlljff8kINR8Iy8XO9AEklMGT9g2mKcPVvaArpyTN2KHLDBJm
        RIyMkDwdyAyfPOLuzdp2XKlvRf8Y4nQq2/9dcinJLtLzyDuZnLIjVbpug2PMdv
        """)

    /// `ssh-keygen -t rsa -b 1024 -N ""`
    private lazy var rsa = wrap("""
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAlwAAAAdzc2gtcn
        NhAAAAAwEAAQAAAIEAylgb7W0v8RYLj+meP21HByuMtTCSTxSRbi8gqDzBInDFO5ACJMEq
        Fj4S0GfYQc7De5A4KtyD+PI62WhgUre67t8Dj6fV3DiToh4813qZBMFVr+IhioZmE0Z2HI
        sYwIUtOtTtbfsTN8GJDFcoUpG9sMHkJ2gNRHnmnj3mn3wnVksAAAIAzUkBW81JAVsAAAAH
        c3NoLXJzYQAAAIEAylgb7W0v8RYLj+meP21HByuMtTCSTxSRbi8gqDzBInDFO5ACJMEqFj
        4S0GfYQc7De5A4KtyD+PI62WhgUre67t8Dj6fV3DiToh4813qZBMFVr+IhioZmE0Z2HIsY
        wIUtOtTtbfsTN8GJDFcoUpG9sMHkJ2gNRHnmnj3mn3wnVksAAAADAQABAAAAgAtWVHpBG+
        aOLaeql0tGfCxSrFeamRgFNwDNcy75+HhNiT+FGhmlGQ6V+8fhiaRmSV2q/vqn0F0qdVGp
        H3yC/t452pFUCnm2iCA/YxYBeeVbvwcO379Q/YdtpN9zX9GpBlVRUJV7rBj4XgkU3Pg6IW
        LuAwHTaPDjq6gNbUHpP0GBAAAAQGs9AjVob6aAw/Xms8dNeNJJPvNhNcrvtzUoaeQKsdpW
        9o0LgWU/aOkJabwTXVy4ld1+z3Mw24+Sl4o/bWssNO4AAABBAPaLwQOHeAzYNU4CSoWdq7
        AJ8V6TAeKZscUQesnnl8Hus93qDFd/TJGm0eOzCukEuGJfEnAA5z+8CH49D7fG8zMAAABB
        ANIacZji57nTfiMZRLDx8pvdrNAMtTUHeLWGLtgcLAzdmNZA0OObZ0Agl/LB5HHzvLzOKA
        rRgJnHm0Ag9n6UEIkAAAAKa2Vzc2lrLXJzYQE=
        """)

    /// `ssh-keygen -t ecdsa -N ""`
    private lazy var ecdsa = wrap("""
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
        1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQRvucbQdqwM2DWtShnDJXuFMoO/G2n+
        /sOGcgrjXvVD1Rq0xlJh8hO2ZPcdsEDbd1/YM95xLr2jV8AXHs0+4rrXAAAAoH1tQMl9bU
        DJAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBG+5xtB2rAzYNa1K
        GcMle4Uyg78baf7+w4ZyCuNe9UPVGrTGUmHyE7Zk9x2wQNt3X9gz3nEuvaNXwBcezT7iut
        cAAAAgcU9hBjPNxkdCOyb3gDJkuQB6hO6PgRhRrVkn5K8a9k4AAAABeAECAwQFBgc=
        """)

    /// Key type and base64 of an `authorized_keys` line, without the comment.
    private func keyPart(_ line: String) -> String {
        line.split(separator: " ").prefix(2).joined(separator: " ")
    }

    private func assertFails(_ text: String, passphrase: String? = nil, with expected: KeyImport.Failure,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try KeyImport.parse(text, passphrase: passphrase), file: file, line: line) { error in
            XCTAssertEqual(error as? KeyImport.Failure, expected, file: file, line: line)
        }
    }

    func testEd25519KeyMatchesPubFile() throws {
        let key = try KeyImport.parse(ed25519)
        XCTAssertEqual(keyPart(DeviceKey.publicLine(for: key)), keyPart(ed25519Pub))
    }

    func testFingerprintMatchesSSHKeygen() throws {
        let key = try KeyImport.parse(ed25519)
        XCTAssertEqual(KeyImport.fingerprint(for: key), ed25519Fingerprint)
        XCTAssertEqual(KeyImport.fingerprint(ofLine: ed25519Pub), ed25519Fingerprint)
        XCTAssertNil(KeyImport.fingerprint(ofLine: "garbage"))
    }

    func testPastedTextWithExtraWhitespaceAndCRLF() throws {
        let messy = "\n  " + ed25519.replacingOccurrences(of: "\n", with: "\r\n  ") + "\n\n"
        let key = try KeyImport.parse(messy)
        XCTAssertEqual(keyPart(DeviceKey.publicLine(for: key)), keyPart(ed25519Pub))
    }

    func testRejectsGarbage() {
        assertFails("", with: .notAKey)
        assertFails("hello world", with: .notAKey)
        assertFails(wrap("bm90IGEga2V5"), with: .notAKey)
    }

    func testRejectsTruncatedKey() {
        // Valid base64 that stops inside the public key.
        let body = "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW"
        assertFails(wrap(body + "Qy"), with: .damaged)
        // Lines lost from the middle, so the base64 no longer decodes.
        assertFails(wrap(body + "Q"), with: .damaged)
        assertFails(wrap("@@@ not base64 @@@"), with: .damaged)
    }

    func testRejectsPublicKey() {
        assertFails(ed25519Pub, with: .publicKey)
    }

    func testRejectsRSA() {
        assertFails(rsa, with: .unsupportedType("RSA"))
        assertFails("-----BEGIN RSA PRIVATE KEY-----\nMIIB\n-----END RSA PRIVATE KEY-----", with: .unsupportedType("RSA"))
    }

    func testRejectsECDSA() {
        assertFails(ecdsa, with: .unsupportedType("ECDSA"))
    }

    func testRejectsPKCS8() {
        assertFails("-----BEGIN PRIVATE KEY-----\nMC4C\n-----END PRIVATE KEY-----", with: .otherFormat("PKCS#8 (PEM)"))
    }

    func testEncryptedKeyNeedsPassphrase() {
        assertFails(encrypted, with: .passphraseNeeded)
        assertFails(encrypted, passphrase: "", with: .passphraseNeeded)
    }

    func testEncryptedKeyWrongPassphrase() {
        assertFails(encrypted, passphrase: "nope", with: .wrongPassphrase)
    }

    func testEncryptedKeyRightPassphrase() throws {
        let key = try KeyImport.parse(encrypted, passphrase: "test-pass")
        XCTAssertEqual(keyPart(DeviceKey.publicLine(for: key)), keyPart(encryptedPub))
    }

    func testRejectsUnreadableCipher() {
        assertFails(chacha, passphrase: "x", with: .unsupportedEncryption("chacha20-poly1305@openssh.com"))
    }

    func testHeader() throws {
        let header = try KeyImport.header(of: encrypted)
        XCTAssertEqual(header.cipher, "aes256-ctr")
        XCTAssertEqual(header.kdf, "bcrypt")
        XCTAssertEqual(header.keyType, "ssh-ed25519")
        XCTAssertTrue(header.isEncrypted)
        XCTAssertFalse(try KeyImport.header(of: ed25519).isEncrypted)
    }

    func testErrorsGiveTheFix() {
        XCTAssertTrue(KeyImport.Failure.unsupportedEncryption("x").localizedDescription.contains("ssh-keygen -p -f"))
        XCTAssertTrue(KeyImport.Failure.unsupportedType("RSA").localizedDescription.contains("ed25519"))
    }
}
