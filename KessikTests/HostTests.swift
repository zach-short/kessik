import XCTest
@testable import Kessik

final class HostTests: XCTestCase {
    func testUnsetHostRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Host.unset)
        XCTAssertEqual(try JSONDecoder().decode(Host.self, from: data), Host.unset)
    }
}
