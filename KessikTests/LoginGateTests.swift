import XCTest
import CryptoKit
@testable import Kessik

final class LoginGateTests: XCTestCase {
    /// Records each call and answers with `result`.
    private final class FakeAuthenticator: Authenticator {
        var result: LoginGate.Failure?
        var reasons: [String] = []

        init(result: LoginGate.Failure?) {
            self.result = result
        }

        func authenticate(reason: String) async throws {
            reasons.append(reason)
            if let result { throw result }
        }
    }

    private let key = Curve25519.Signing.PrivateKey()
    private var keyReads = 0
    private var passwordReads = 0

    private func gate(required: Bool, _ authenticator: Authenticator) -> LoginGate {
        LoginGate(
            isRequired: { required },
            authenticator: authenticator,
            readKey: { [unowned self] in keyReads += 1; return .ed25519(key) },
            readSavedPassword: { [unowned self] _ in passwordReads += 1; return "saved" }
        )
    }

    func testOffReadsWithoutAsking() async throws {
        let auth = FakeAuthenticator(result: .failed)
        let secrets = try await gate(required: false, auth).secrets(for: .unset, typed: nil)
        XCTAssertTrue(auth.reasons.isEmpty)
        XCTAssertEqual(secrets.key?.rawRepresentation, key.rawRepresentation)
        XCTAssertEqual(secrets.password, "saved")
    }

    func testOnAsksOnceThenReads() async throws {
        let auth = FakeAuthenticator(result: nil)
        let secrets = try await gate(required: true, auth).secrets(for: .unset, typed: nil)
        XCTAssertEqual(auth.reasons.count, 1)
        XCTAssertEqual(secrets.key?.rawRepresentation, key.rawRepresentation)
        XCTAssertEqual(secrets.password, "saved")
        XCTAssertEqual(keyReads, 1)
    }

    func testTypedPasswordSkipsSavedOne() async throws {
        let secrets = try await gate(required: true, FakeAuthenticator(result: nil)).secrets(for: .unset, typed: "typed")
        XCTAssertEqual(secrets.password, "typed")
        XCTAssertEqual(passwordReads, 0)
    }

    func testFailureStopsLoginWithoutReading() async {
        await assertStops(with: .failed)
    }

    func testCancelStopsLoginWithoutReading() async {
        await assertStops(with: .canceled)
    }

    func testNoPasscodeStopsLoginWithoutReading() async {
        await assertStops(with: .noPasscode)
    }

    @MainActor
    func testFailureMessagesAreShown() {
        for failure in [LoginGate.Failure.canceled, .failed, .noPasscode] {
            XCTAssertEqual(SSHSession.message(for: failure, host: .unset), failure.errorDescription)
        }
    }

    private func assertStops(with failure: LoginGate.Failure, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await gate(required: true, FakeAuthenticator(result: failure)).secrets(for: .unset, typed: nil)
            XCTFail("Expected \(failure)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LoginGate.Failure, failure, file: file, line: line)
        }
        XCTAssertEqual(keyReads, 0, "The key was read after the check failed", file: file, line: line)
        XCTAssertEqual(passwordReads, 0, "The password was read after the check failed", file: file, line: line)
    }
}
