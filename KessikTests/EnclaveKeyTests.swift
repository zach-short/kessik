import XCTest
import CryptoKit
import NIOSSH
@testable import Kessik

final class EnclaveKeyTests: XCTestCase {
    /// A throwaway P-256 key made with `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256`.
    private let pem = """
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgZh7YIa0QRT+OMj9U
    J18nK0GGY8m8npko4iPlJIGhY7uhRANCAAS3cFCdxTndGvae4fxTsB3JyjaVypu6
    U8DI9zFB5Lh7O0LW9sJbLrh7K1mP3nnCnFsjxMo70NC5S29fyC+xUljY
    -----END PRIVATE KEY-----
    """

    /// The Secure Enclave key gives NIOSSH the same `ecdsaP256` public key as a plain P-256 key,
    /// so a plain key checks the encoding. The expected line comes from
    /// `openssl pkey -pubout | ssh-keygen -i -m PKCS8 -f /dev/stdin` on the same key.
    func testP256PublicLineMatchesSSHKeygen() throws {
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        let line = EnclaveKey.publicLine(for: NIOSSHPrivateKey(p256Key: key))
        XCTAssertEqual(line, "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLdwUJ3FOd0a9p7h/FOwHcnKNpXKm7pTwMj3MUHkuHs7Qtb2wlsuuHsrWY/eecKcWyPEyjvQ0LlLb1/IL7FSWNg= kessik")
    }

    func testPublicLineParsesBack() throws {
        let key = P256.Signing.PrivateKey()
        let line = EnclaveKey.publicLine(for: NIOSSHPrivateKey(p256Key: key))
        let parsed = try NIOSSHPublicKey(openSSHPublicKey: line)
        XCTAssertEqual(parsed, NIOSSHPrivateKey(p256Key: key).publicKey)
    }

    func testInstallCommandKeepsTheWholeLine() throws {
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        let line = EnclaveKey.publicLine(for: NIOSSHPrivateKey(p256Key: key))
        XCTAssertTrue(DeviceKey.installCommand(for: line).contains("'\(line)'"))
    }

    func testKindFallsBackToEd25519WithoutEnclave() {
        XCTAssertEqual(LoginKeyKind.resolve(.secureEnclave, enclaveAvailable: false), .ed25519)
        XCTAssertEqual(LoginKeyKind.resolve(.secureEnclave, enclaveAvailable: true), .secureEnclave)
        XCTAssertEqual(LoginKeyKind.resolve(.ed25519, enclaveAvailable: true), .ed25519)
        XCTAssertEqual(LoginKeyKind.resolve(nil, enclaveAvailable: true), .ed25519)
    }

    func testUnknownSavedKindIsEd25519() {
        XCTAssertNil(LoginKeyKind(rawValue: "rsa"))
        XCTAssertEqual(LoginKeyKind.resolve(LoginKeyKind(rawValue: "rsa"), enclaveAvailable: true), .ed25519)
    }

    // MARK: Gate order

    private struct Passing: Authenticator {
        func authenticate(reason: String) async throws {}
    }

    private struct Failing: Authenticator {
        func authenticate(reason: String) async throws { throw LoginGate.Failure.canceled }
    }

    private final class Counter: @unchecked Sendable {
        var unlocks = 0
    }

    private func gate(_ authenticator: Authenticator, _ counter: Counter, required: Bool = true,
                      usesEnclave: Bool = false, saved: String? = "saved",
                      unlock: @escaping () throws -> SecureEnclave.P256.Signing.PrivateKey? = { nil }) -> LoginGate {
        LoginGate(
            isRequired: { required },
            authenticator: authenticator,
            readKey: { nil },
            readSavedPassword: { _ in saved },
            usesEnclaveKey: { usesEnclave },
            unlockEnclaveKey: { _ in counter.unlocks += 1; return try unlock() }
        )
    }

    func testEnclaveKeyUnlocksOnceAfterTheGate() async throws {
        let counter = Counter()
        let secrets = try await gate(Passing(), counter).secrets(for: .unset, typed: nil)
        XCTAssertEqual(counter.unlocks, 1)
        XCTAssertNil(secrets.enclaveKey)
        XCTAssertEqual(secrets.password, "saved")
    }

    func testFailedGateDoesNotAskForTheEnclaveKey() async {
        let counter = Counter()
        _ = try? await gate(Failing(), counter).secrets(for: .unset, typed: nil)
        XCTAssertEqual(counter.unlocks, 0)
    }

    /// With the Secure Enclave key in use, its own Face ID check is the gate: one prompt, not two.
    /// The gate's authenticator here would throw `.canceled`, so `.failed` shows it never ran, and a
    /// failed check reads no password.
    func testEnclaveCheckStandsInForTheGate() async {
        let counter = Counter()
        do {
            _ = try await gate(Failing(), counter, usesEnclave: true, unlock: { throw LoginGate.Failure.failed })
                .secrets(for: .unset, typed: nil)
            XCTFail("Expected the login to stop")
        } catch {
            XCTAssertEqual(error as? LoginGate.Failure, .failed)
        }
        XCTAssertEqual(counter.unlocks, 1)
    }

    /// Without the gate, a canceled Face ID check falls back to the saved password.
    func testCanceledEnclaveCheckFallsBackToSavedPassword() async throws {
        let counter = Counter()
        let secrets = try await gate(Passing(), counter, required: false, usesEnclave: true,
                                     unlock: { throw LoginGate.Failure.canceled }).secrets(for: .unset, typed: nil)
        XCTAssertNil(secrets.enclaveKey)
        XCTAssertEqual(secrets.password, "saved")
    }

    /// With no password to fall back to, the Face ID reason is the error, not "the Mac refused the login".
    func testCanceledEnclaveCheckWithoutPasswordSaysWhy() async {
        let counter = Counter()
        do {
            _ = try await gate(Passing(), counter, required: false, usesEnclave: true, saved: nil,
                               unlock: { throw LoginGate.Failure.enclaveKeyLocked }).secrets(for: .unset, typed: nil)
            XCTFail("Expected the login to stop")
        } catch {
            XCTAssertEqual(error as? LoginGate.Failure, .enclaveKeyLocked)
        }
    }
}
