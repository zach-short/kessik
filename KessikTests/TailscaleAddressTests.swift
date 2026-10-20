import XCTest
import NIOCore

@testable import Kessik

final class TailscaleAddressTests: XCTestCase {
    func testParseTakesTheFirstLineInTailscalesRange() {
        XCTAssertEqual(TailscaleAddress.parse("100.107.82.118\n100.107.82.118\n"), "100.107.82.118")
        XCTAssertEqual(TailscaleAddress.parse("fd7a:115c:a1e0::1\n 192.168.1.4\n100.101.2.3 \n"), "100.101.2.3")
        XCTAssertNil(TailscaleAddress.parse("\n"))
    }

    func testTailscaleRangeIs100_64Slash10() {
        for inside in ["100.64.0.1", "100.107.82.118", "100.127.255.254"] {
            XCTAssertTrue(TailscaleAddress.isTailscale(inside), inside)
        }
        for outside in ["100.63.0.1", "100.128.0.1", "100.64.0", "100.64.0.1.5", "100.64.0.256", "100.64..1", "my-mac"] {
            XCTAssertFalse(TailscaleAddress.isTailscale(outside), outside)
        }
    }

    func testBonjourNamesAndPrivateAddressesAreLanOnly() {
        for lan in ["my-mac.local", "MY-MAC.LOCAL", "10.0.0.5", "172.16.0.1", "172.31.255.1", "192.168.1.20", "169.254.3.4"] {
            XCTAssertTrue(TailscaleAddress.isLanOnly(lan), lan)
        }
        for other in ["100.107.82.118", "172.32.0.1", "8.8.8.8", "my-mac.tail00746f.ts.net", "my-mac", "fd7a:115c:a1e0::1", "local"] {
            XCTAssertFalse(TailscaleAddress.isLanOnly(other), other)
        }
    }

    /// Campus Wi-Fi can give a Mac a 100.x address that is not its Tailscale one, so a 100.x
    /// hostname is checked against the Mac. A tailnet name is never LAN only.
    func testA100AddressIsCheckedAgainstTheMac() {
        XCTAssertTrue(TailscaleAddress.mayBeLanOnly("100.69.39.207"))
        XCTAssertTrue(TailscaleAddress.mayBeLanOnly("my-mac.local"))
        XCTAssertFalse(TailscaleAddress.mayBeLanOnly("my-mac.tail00746f.ts.net"))
        XCTAssertFalse(TailscaleAddress.mayBeLanOnly("203.0.113.9"))
    }

    func testTheLookupFallbackReadsOnlyUtunInterfaces() {
        XCTAssertTrue(TailscaleAddress.command.contains("utun*)"))
        XCTAssertFalse(TailscaleAddress.command.contains("ifconfig 2>/dev/null | awk"))
    }
}

@MainActor
final class LanAddressMessageTests: XCTestCase {
    private let timeout = ChannelError.connectTimeout(.seconds(10))

    func testALanAddressThatDoesNotAnswerPointsAtTheTailscaleAddress() {
        let host = Host(name: "Mac", hostname: "192.168.1.20", username: "me")
        XCTAssertEqual(SSHSession.message(for: timeout, host: host),
                       "192.168.1.20 did not answer. This address works only on the Mac's own network. Away from it, use the Mac's Tailscale address, which the Tailscale app lists.")
    }

    func testABonjourNameWithNoRoutePointsAtTheTailscaleAddress() {
        let host = Host(name: "Mac", hostname: "my-mac.local", username: "me")
        let text = SSHSession.message(for: IOError(errnoCode: ENETUNREACH, reason: "connect"), host: host)
        XCTAssertTrue(text.hasSuffix("use the Mac's Tailscale address, which the Tailscale app lists."), text)
    }

    func testATailscaleAddressKeepsTheTailscaleCheck() {
        let host = Host(name: "Mac", hostname: "100.107.82.118", username: "me")
        XCTAssertEqual(SSHSession.message(for: timeout, host: host),
                       "100.107.82.118 did not answer. The Mac can be asleep, offline, or off Tailscale.")
    }

    /// Through a jump host, the jump host reaches the LAN name, so the hint about this phone's network does not apply.
    func testALanNameBehindAJumpHostKeepsTheOldHint() {
        var host = Host(name: "Mac", hostname: "192.168.1.20", username: "me")
        host.jump = JumpHost(hostname: "bastion.example.com", username: "ops")
        XCTAssertEqual(SSHSession.message(for: timeout, host: host),
                       "192.168.1.20 did not answer. The Mac can be asleep, offline, or off Tailscale.")
    }
}
