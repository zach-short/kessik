import XCTest
import NIOCore

@testable import Kessik

final class TailscaleSocketTests: XCTestCase {
    func testATailscaleAddressSkipsTheResolver() throws {
        let address = try XCTUnwrap(TailscaleSocket.address(for: "100.107.82.118", port: 2222))
        XCTAssertEqual(address.protocol, .inet)
        XCTAssertEqual(address.ipAddress, "100.107.82.118")
        XCTAssertEqual(address.port, 2222)
    }

    /// A public IPv4 address on an IPv6-only network needs the resolver's NAT64 address, and a name needs the resolver.
    func testEveryOtherHostKeepsTheResolver() {
        for host in ["192.168.1.20", "203.0.113.9", "my-mac.local", "my-mac.tail00746f.ts.net", "fd7a:115c:a1e0::1", "100.64.0.256"] {
            XCTAssertNil(TailscaleSocket.address(for: host, port: 22), host)
        }
    }
}
