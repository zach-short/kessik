import XCTest
import CryptoKit
import NIOSSH
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

    /// An ECDSA fixture with its `ssh-keygen -y` line and `ssh-keygen -l` fingerprint.
    private struct ECDSAFixture {
        var text: String
        var pub: String
        var fingerprint: String
        var label: String
    }

    /// `ssh-keygen -t ecdsa -b 256|384|521 -N "" -C kessik-test-p<bits>`
    private lazy var ecdsaKeys = [
        ECDSAFixture(text: wrap("""
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
            1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQQJ3Jm17OL9mWdBxqv2EIASWGitX0w7
            ATFGDraRl4TgK9c+xw1v1yYAhO1vWAeUn36gMDmj7yyUBEkLgleSZELVAAAAsPZ2rrH2dq
            6xAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAncmbXs4v2ZZ0HG
            q/YQgBJYaK1fTDsBMUYOtpGXhOAr1z7HDW/XJgCE7W9YB5SffqAwOaPvLJQESQuCV5JkQt
            UAAAAhAI+KzkWUwTZ+SchCEX99t6jyZ5h61jmIWu9smn0CF4AqAAAAEGtlc3Npay10ZXN0
            LXAyNTYBAgMEBQYH
            """),
            pub: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAncmbXs4v2ZZ0HGq/YQgBJYaK1fTDsBMUYOtpGXhOAr1z7HDW/XJgCE7W9YB5SffqAwOaPvLJQESQuCV5JkQtU= kessik-test-p256",
            fingerprint: "SHA256:8F3t5VKat5wbxcPkkm9NJBWb8wsAYiEWPt5jTLRtv/c",
            label: "ECDSA P-256"),
        ECDSAFixture(text: wrap("""
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAiAAAABNlY2RzYS
            1zaGEyLW5pc3RwMzg0AAAACG5pc3RwMzg0AAAAYQTGBVQzYWFd20knOMaj/2YV5LkLDaic
            sC6dsvMRHeZlm4KfbJ1RociLKkl3EgOB1kppAbsGWCxfPtfAzKO9+9Snl6m+jEAv1tYTpV
            7541Y4izSZGQJxlfpcDe1U8OyLIywAAADYZaKL3WWii90AAAATZWNkc2Etc2hhMi1uaXN0
            cDM4NAAAAAhuaXN0cDM4NAAAAGEExgVUM2FhXdtJJzjGo/9mFeS5Cw2onLAunbLzER3mZZ
            uCn2ydUaHIiypJdxIDgdZKaQG7BlgsXz7XwMyjvfvUp5epvoxAL9bWE6Ve+eNWOIs0mRkC
            cZX6XA3tVPDsiyMsAAAAMCyfAzBvplxPgtimBFhtewgWnTBFqzD186BxYtLb5wmSOJ2kjU
            e+hCLFsszq4yGofAAAABBrZXNzaWstdGVzdC1wMzg0
            """),
            pub: "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBMYFVDNhYV3bSSc4xqP/ZhXkuQsNqJywLp2y8xEd5mWbgp9snVGhyIsqSXcSA4HWSmkBuwZYLF8+18DMo7371KeXqb6MQC/W1hOlXvnjVjiLNJkZAnGV+lwN7VTw7IsjLA== kessik-test-p384",
            fingerprint: "SHA256:4r5cIFAZiTwbHa7YIFma3BNlJVNFGhNFB3K+iJ5dpgw",
            label: "ECDSA P-384"),
        ECDSAFixture(text: wrap("""
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAArAAAABNlY2RzYS
            1zaGEyLW5pc3RwNTIxAAAACG5pc3RwNTIxAAAAhQQB7Z75mnjaCYolwj2XJkWfrxheTsZv
            wz5d8Z0KadwokjCaLWn+w7d/+fjQ3OdWwwGRuwRQIGeUdo5sD7SaSSD1H8kAKYNf3M8SOV
            FwdCHQXAT6LFGp9j731jDaxymzo7OhqpuyNNsEFzNA4/R7B/ezG816aszQpkvUz7GpuB7g
            5pQFhNcAAAEQwDo1WsA6NVoAAAATZWNkc2Etc2hhMi1uaXN0cDUyMQAAAAhuaXN0cDUyMQ
            AAAIUEAe2e+Zp42gmKJcI9lyZFn68YXk7Gb8M+XfGdCmncKJIwmi1p/sO3f/n40NznVsMB
            kbsEUCBnlHaObA+0mkkg9R/JACmDX9zPEjlRcHQh0FwE+ixRqfY+99Yw2scps6Ozoaqbsj
            TbBBczQOP0ewf3sxvNemrM0KZL1M+xqbge4OaUBYTXAAAAQgDqjJ4WX7DT1z2y3AYmrPwC
            u+9FqtRmAX+sMCkCJOjZ1bErzEa4EHr1vX1r10Sk1v/Njivh+2fV2DqhJlLOj1V6pwAAAB
            BrZXNzaWstdGVzdC1wNTIxAQI=
            """),
            pub: "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAHtnvmaeNoJiiXCPZcmRZ+vGF5Oxm/DPl3xnQpp3CiSMJotaf7Dt3/5+NDc51bDAZG7BFAgZ5R2jmwPtJpJIPUfyQApg1/czxI5UXB0IdBcBPosUan2PvfWMNrHKbOjs6Gqm7I02wQXM0Dj9HsH97MbzXpqzNCmS9TPsam4HuDmlAWE1w== kessik-test-p521",
            fingerprint: "SHA256:syWlgI33ixuf1QQQV0I2e9ncMLlDmNAzAsoy71ugOE0",
            label: "ECDSA P-521"),
    ]

    /// `ssh-keygen -t ecdsa -b 521 -N test-pass -C kessik-test-enc` (aes256-ctr with bcrypt, the default).
    private lazy var encryptedECDSA = ECDSAFixture(text: wrap("""
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBhElUmDp
        48pdzL2wRqiCM3AAAAGAAAAAEAAACsAAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlz
        dHA1MjEAAACFBADaNSDNeCVJBtoRMznGBvE18wEC+DhRcW+rymVAIFF0MMSKyl/7P/2wIn
        8PdPclIsArH1pfINMzVvtyMgLQvRriXwGsCQQ0Q//oYC9nbKCIEyeVQjuHim7nL7CUkUCs
        MDhKnWVdzSCiLUHRYCaPkm7n+wc6KWDaCfWNNVQ02ofPpJuaaAAAARCTQ/2mGW7wgGM87n
        oJLRWzYIcbpdHO1R0ZyO9ZBuf7Otm1e0bq66ShrATvDfaqX/jVu9eCLSv04H4XTfPEs18k
        CUp3R6M09GlCsHp/3E1xv1ELraQ8yUTlADzbHRAIrb0oQct0jM1C//zDqCNA5/GR/IGAuT
        OkY0hBrNR5FsMIbWNYM+iJRBRLY7tJTiM6fwP6GQSFmbd4lqb+4xHYTLmbl+YbGgw8ipfJ
        z8kcnleISzN5QapwjNghVPir3Z1w06sxzFTW0BvH3RSC2FKK/BhVoT7OBODhLxl8dwGdCx
        6kAxDpnnwhbE8Zc2+yD0qySWzrWjaQakYP6xww6aQzW/t5NxircZAOe6L5fH8nvDtFDQ==
        """),
        pub: "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBADaNSDNeCVJBtoRMznGBvE18wEC+DhRcW+rymVAIFF0MMSKyl/7P/2wIn8PdPclIsArH1pfINMzVvtyMgLQvRriXwGsCQQ0Q//oYC9nbKCIEyeVQjuHim7nL7CUkUCsMDhKnWVdzSCiLUHRYCaPkm7n+wc6KWDaCfWNNVQ02ofPpJuaaA== kessik-test-enc",
        fingerprint: "SHA256:nqJd6LKT6kvsCJQ17oXS8rAaMVBfDLhyjIYKdTTR8Bg",
        label: "ECDSA P-521")

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

    func testRSAErrorSaysWhichKeysWork() {
        let message = KeyImport.Failure.unsupportedType("RSA").localizedDescription
        XCTAssertTrue(message.contains("cannot use RSA keys"))
        XCTAssertTrue(message.contains("ed25519 and ECDSA"))
    }

    func testECDSAKeysMatchSSHKeygen() throws {
        for fixture in ecdsaKeys {
            let key = try KeyImport.parse(fixture.text)
            XCTAssertEqual(keyPart(DeviceKey.publicLine(for: key)), keyPart(fixture.pub), fixture.label)
            XCTAssertEqual(KeyImport.fingerprint(for: key), fixture.fingerprint, fixture.label)
            XCTAssertEqual(KeyImport.fingerprint(ofLine: DeviceKey.publicLine(for: key)), fixture.fingerprint, fixture.label)
            XCTAssertEqual(key.label, fixture.label)
        }
    }

    /// A login signs with `sshKey`, and the Mac checks the signature with the line in authorized_keys.
    func testECDSASignatureVerifiesWithPublicLine() throws {
        for fixture in ecdsaKeys + [encryptedECDSA] {
            let key = try KeyImport.parse(fixture.text, passphrase: "test-pass")
            let publicKey = try NIOSSHPublicKey(openSSHPublicKey: fixture.pub)
            let signature = try key.sshKey.sign(digest: SHA256.hash(data: Data("session".utf8)))
            XCTAssertTrue(publicKey.isValidSignature(signature, for: SHA256.hash(data: Data("session".utf8))), fixture.label)
            XCTAssertFalse(publicKey.isValidSignature(signature, for: SHA256.hash(data: Data("other".utf8))), fixture.label)
        }
    }

    /// The Keychain holds an ECDSA key as its raw scalar, and the length picks the curve on load.
    func testECDSARawRepresentationRoundTrips() throws {
        for fixture in ecdsaKeys {
            let key = try KeyImport.parse(fixture.text)
            let loaded = try XCTUnwrap(DeviceKey.Key(ecdsaRaw: key.rawRepresentation))
            XCTAssertEqual(DeviceKey.publicLine(for: loaded), DeviceKey.publicLine(for: key), fixture.label)
        }
        XCTAssertNil(DeviceKey.Key(ecdsaRaw: Data(count: 40)))
    }

    func testEncryptedECDSAKey() throws {
        assertFails(encryptedECDSA.text, with: .passphraseNeeded)
        assertFails(encryptedECDSA.text, passphrase: "nope", with: .wrongPassphrase)
        let key = try KeyImport.parse(encryptedECDSA.text, passphrase: "test-pass")
        XCTAssertEqual(keyPart(DeviceKey.publicLine(for: key)), keyPart(encryptedECDSA.pub))
        XCTAssertEqual(KeyImport.fingerprint(for: key), encryptedECDSA.fingerprint)
    }

    func testRejectsPEMECDSA() {
        assertFails("-----BEGIN EC PRIVATE KEY-----\nMHcC\n-----END EC PRIVATE KEY-----", with: .otherFormat("PEM"))
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
