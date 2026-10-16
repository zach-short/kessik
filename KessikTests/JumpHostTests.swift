import XCTest
import CryptoKit
import Citadel
import NIOCore
import NIOPosix
import NIOSSH
@testable import Kessik

final class JumpHostTests: XCTestCase {
    private let suiteName = "JumpHostTests"
    private var defaults: UserDefaults!

    private let jump = JumpHost(hostname: "bastion.example.com", port: 2222, username: "ops")
    /// One id for every use, so list rules see the same Mac.
    private let mac = Host(id: UUID(), name: "Studio", hostname: "studio.lan", username: "zach",
                           jump: JumpHost(hostname: "bastion.example.com", port: 2222, username: "ops"))

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Model and decoding

    /// A Mac saved before jump hosts has no `jump` key. It must still load.
    func testHostSavedWithoutJumpKeyDecodes() throws {
        let old = """
        {"id":"6F1C3B2A-1D2E-4F50-8A6B-7C8D9E0F1A2B","name":"Mac","hostname":"mac.tailnet.ts.net",
         "port":22,"username":"zach","status":"unknown"}
        """
        let host = try JSONDecoder().decode(Host.self, from: Data(old.utf8))
        XCTAssertNil(host.jump)
        XCTAssertEqual(host.hostname, "mac.tailnet.ts.net")
        XCTAssertEqual(host.username, "zach")
    }

    func testOldMacListWithoutJumpKeyLoads() throws {
        let old = """
        [{"id":"6F1C3B2A-1D2E-4F50-8A6B-7C8D9E0F1A2B","name":"Mac","hostname":"mac.local",
          "port":2200,"username":"zach","status":"unknown"}]
        """
        defaults.set(Data(old.utf8), forKey: SavedMacs.listKey)
        let list = SavedMacs(defaults: defaults).load()
        XCTAssertEqual(list.macs.count, 1)
        XCTAssertNil(list.macs[0].jump)
        XCTAssertEqual(list.macs[0].port, 2200)
    }

    func testHostWithJumpRoundTrips() throws {
        let data = try JSONEncoder().encode(mac)
        let decoded = try JSONDecoder().decode(Host.self, from: data)
        XCTAssertEqual(decoded, mac)
        XCTAssertEqual(decoded.jump, jump)
    }

    func testJumpLoginIsItsOwnTarget() {
        XCTAssertEqual(jump.address, "ops@bastion.example.com:2222")
        XCTAssertEqual(JumpHost(hostname: "b", username: "u").address, "u@b")
        let login = jump.login
        XCTAssertEqual(login.hostname, "bastion.example.com")
        XCTAssertEqual(login.port, 2222)
        XCTAssertEqual(login.username, "ops")
        XCTAssertFalse(login.sameLogin(as: mac))
    }

    func testMacListTracksWhoUsesAJumpLogin() {
        var other = Host(name: "Other", hostname: "other.lan", username: "zach")
        other.jump = jump
        let bastion = Host(name: "Bastion", hostname: "bastion.example.com", port: 2222, username: "ops")
        let plain = Host(name: "Plain", hostname: "plain.lan", username: "zach")

        let shared = MacList(macs: [mac, other])
        XCTAssertTrue(shared.sharesJumpLogin(with: mac))
        XCTAssertFalse(MacList(macs: [mac, plain]).sharesJumpLogin(with: mac))
        // A Mac whose own login is the jump host keeps the password too.
        XCTAssertTrue(MacList(macs: [mac, bastion]).sharesJumpLogin(with: mac))
        XCTAssertFalse(MacList(macs: [mac]).sharesJumpLogin(with: plain))

        XCTAssertTrue(MacList(macs: [mac, bastion]).jumpsThrough(bastion))
        XCTAssertFalse(MacList(macs: [plain, bastion]).jumpsThrough(bastion))
    }

    // MARK: Form draft

    func testEmptyDraftIsNoJumpHost() {
        XCTAssertEqual(JumpHostDraft().result, .none)
        XCTAssertNil(JumpHostDraft().problem)
        XCTAssertEqual(JumpHostDraft(nil), JumpHostDraft())
    }

    func testDraftBuildsJumpHostWithDefaultPort() {
        var draft = JumpHostDraft()
        draft.hostname = " bastion.example.com "
        draft.username = "ops"
        XCTAssertEqual(draft.jump, JumpHost(hostname: "bastion.example.com", port: 22, username: "ops"))
        draft.port = "2222"
        XCTAssertEqual(draft.jump?.port, 2222)
    }

    func testDraftLoadsSavedJumpHost() {
        let draft = JumpHostDraft(jump)
        XCTAssertEqual(draft.hostname, "bastion.example.com")
        XCTAssertEqual(draft.port, "2222")
        XCTAssertEqual(draft.username, "ops")
        XCTAssertEqual(draft.password, "")
        XCTAssertEqual(draft.jump, jump)
        XCTAssertEqual(JumpHostDraft(JumpHost(hostname: "b", username: "u")).port, "")
    }

    func testDraftProblems() {
        var draft = JumpHostDraft()
        draft.username = "ops"
        XCTAssertNotNil(draft.problem, "a username with no hostname")
        draft.hostname = "bastion"
        XCTAssertNil(draft.problem)
        draft.port = "70000"
        XCTAssertNotNil(draft.problem)
        draft.port = "abc"
        XCTAssertNotNil(draft.problem)
        draft.port = ""
        draft.hostname = "ops@bastion"
        XCTAssertNotNil(draft.problem)
        draft.hostname = "bas tion"
        XCTAssertNotNil(draft.problem)
        draft.hostname = "bastion"
        draft.username = ""
        XCTAssertNotNil(draft.problem)
        XCTAssertNil(draft.jump)
    }

    // MARK: Hops and host key checks

    func testDirectMacHasOneHopKeyedToTheMac() {
        let direct = Host(name: "Mac", hostname: "mac.local", port: 2200, username: "zach")
        let hops = LoginRoute.hops(to: direct, defaults: defaults)
        XCTAssertEqual(hops.map(\.role), [.mac])
        XCTAssertEqual(hops[0].validator.storageKey, "hostKey.mac.local:2200")
        // The same key as before jump hosts, so trusted Macs stay trusted.
        XCTAssertEqual(hops[0].validator.storageKey,
                       TOFUHostKeyValidator(host: "mac.local", port: 2200).storageKey)
    }

    /// Each hop gets its own validator, keyed by that hop's own hostname and port.
    func testJumpRouteChecksBothHostKeysSeparately() {
        let hops = LoginRoute.hops(to: mac, defaults: defaults)
        XCTAssertEqual(hops.map(\.role), [.jumpHost, .mac])
        XCTAssertEqual(hops[0].validator.storageKey, "hostKey.bastion.example.com:2222")
        XCTAssertEqual(hops[1].validator.storageKey, "hostKey.bastion.example.com:2222/studio.lan:22")
        XCTAssertFalse(hops[0].validator === hops[1].validator)
        XCTAssertTrue(hops[0].target.sameLogin(as: jump.login))
        XCTAssertTrue(hops[1].target.sameLogin(as: mac))
    }

    func testSettingsPointEachHopAtItsOwnHost() {
        let hops = LoginRoute.hops(to: mac, defaults: defaults)
        let jumpSettings = hops[0].settings(key: nil, password: "a")
        let macSettings = hops[1].settings(key: nil, password: "b")
        XCTAssertEqual(jumpSettings.host, "bastion.example.com")
        XCTAssertEqual(jumpSettings.port, 2222)
        XCTAssertEqual(macSettings.host, "studio.lan")
        XCTAssertEqual(macSettings.port, 22)
    }

    /// The validators do the real check: a changed key on either hop is refused, naming that host.
    func testChangedKeyOnEitherHopIsRefusedNamingThatHost() throws {
        let first = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        let second = NIOSSHPrivateKey(ed25519Key: .init()).publicKey

        for (index, name) in [(0, "bastion.example.com"), (1, "studio.lan")] {
            // Trust on first use, then the same key again.
            XCTAssertNoThrow(try validate(first, hop: index))
            XCTAssertNoThrow(try validate(first, hop: index))
            XCTAssertThrowsError(try validate(second, hop: index)) { error in
                let mismatch = error as? TOFUHostKeyValidator.Mismatch
                XCTAssertEqual(mismatch?.host, name)
            }
        }
    }

    /// The same inner name behind another jump host, or reached directly, is a different Mac.
    func testMacBehindJumpHostIsTrustedPerJumpHost() {
        var other = mac
        other.jump?.hostname = "other-bastion.example.com"
        var direct = mac
        direct.jump = nil
        let keys = [mac, other, direct].map { LoginRoute.hops(to: $0, defaults: defaults).last!.validator.storageKey }
        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(keys[2], "hostKey.studio.lan:22")
    }

    /// The jump host's trusted key does not make the Mac trusted, and the other way round.
    func testTrustOnOneHopDoesNotCoverTheOther() throws {
        let jumpKey = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        let macKey = NIOSSHPrivateKey(ed25519Key: .init()).publicKey
        try validate(jumpKey, hop: 0)
        XCTAssertNil(defaults.string(forKey: "hostKey.bastion.example.com:2222/studio.lan:22"))
        try validate(macKey, hop: 1)
        XCTAssertThrowsError(try validate(jumpKey, hop: 1))
        XCTAssertThrowsError(try validate(macKey, hop: 0))
    }

    private func validate(_ key: NIOSSHPublicKey, hop index: Int) throws {
        let validator = LoginRoute.hops(to: mac, defaults: defaults)[index].validator
        let promise = MultiThreadedEventLoopGroup.singleton.next().makePromise(of: Void.self)
        validator.validateHostKey(hostKey: key, validationCompletePromise: promise)
        try promise.futureResult.wait()
    }

    // MARK: Secrets

    func testGateReadsTheJumpHostsOwnSavedPassword() async throws {
        let gate = LoginGate(
            isRequired: { false },
            authenticator: DeviceOwnerAuthenticator(),
            readKey: { nil },
            readSavedPassword: { host in "pw-for-\(host.username)@\(host.hostname):\(host.port)" }
        )
        let secrets = try await gate.secrets(for: mac, typed: nil)
        XCTAssertEqual(secrets.password, "pw-for-zach@studio.lan:22")
        XCTAssertEqual(secrets.jumpPassword, "pw-for-ops@bastion.example.com:2222")

        let typed = try await gate.secrets(for: mac, typed: "typed")
        XCTAssertEqual(typed.password, "typed", "a typed password is for the Mac only")
        XCTAssertEqual(typed.jumpPassword, "pw-for-ops@bastion.example.com:2222")

        let direct = try await gate.secrets(for: .unset, typed: nil)
        XCTAssertNil(direct.jumpPassword)
    }

    // MARK: Errors

    private struct Plain: Error {}

    private func describe(_ error: Error, _ host: Host) -> String {
        "\(host.hostname) failed."
    }

    func testJumpHostFailureSaysJumpHost() {
        let failure = HopFailure(role: .jumpHost, target: jump.login, jumpName: "bastion.example.com", underlying: Plain())
        XCTAssertEqual(failure.text(describe), "Jump host: bastion.example.com failed.")
    }

    func testJumpHostLoginFailureNamesTheJumpHost() {
        let failure = HopFailure(role: .jumpHost, target: jump.login, jumpName: "bastion.example.com",
                                 underlying: SSHClientError.allAuthenticationOptionsFailed)
        let text = failure.text(describe)
        XCTAssertTrue(text.hasPrefix("Jump host: bastion.example.com refused the login."), text)
        XCTAssertFalse(text.contains("The Mac refused"))
    }

    func testMacFailureSaysMacThroughTheJumpHost() {
        let failure = HopFailure(role: .mac, target: mac, jumpName: "bastion.example.com", underlying: Plain())
        XCTAssertEqual(failure.text(describe), "Mac, through bastion.example.com: studio.lan failed.")
    }

    func testHostKeyChangeOnTheJumpHostNamesIt() {
        let mismatch = TOFUHostKeyValidator.Mismatch(host: "bastion.example.com")
        let failure = HopFailure(role: .jumpHost, target: jump.login, jumpName: "bastion.example.com", underlying: mismatch)
        let text = failure.text { error, _ in (error as? LocalizedError)?.errorDescription ?? "" }
        XCTAssertEqual(text, "Jump host: The host key for bastion.example.com changed since the last connection. The connection was stopped.")
    }

    func testCancelIsNotWrapped() {
        let wrapped = HopFailure.wrap(CancellationError(), role: .mac, target: mac, jumpName: "b")
        XCTAssertTrue(wrapped is CancellationError)
        XCTAssertTrue(HopFailure.wrap(Plain(), role: .mac, target: mac, jumpName: "b") is HopFailure)
    }
}
