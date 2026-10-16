import XCTest
@testable import Kessik

final class MacListTests: XCTestCase {
    private let suiteName = "MacListTests"
    private var defaults: UserDefaults!
    private var saved: SavedMacs { SavedMacs(defaults: defaults) }

    private let home = Host(name: "Home", hostname: "home.tailnet.ts.net", username: "zach")
    private let work = Host(name: "Work", hostname: "10.0.0.5", port: 2222, username: "zs")

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

    // MARK: Migration

    func testLegacySavedMacBecomesFirstAndActiveEntry() throws {
        var legacy = Host(name: "Studio", hostname: "studio.local", port: 2200, username: "zach",
                          lastConnected: Date(timeIntervalSince1970: 1_700_000_000))
        legacy.status = .unknown
        defaults.set(try JSONEncoder().encode(legacy), forKey: SavedMacs.legacyKey)

        let list = saved.load()

        XCTAssertEqual(list.macs, [legacy])
        XCTAssertEqual(list.activeID, legacy.id)
        let active = try XCTUnwrap(list.active)
        XCTAssertTrue(active.sameLogin(as: legacy))
        XCTAssertEqual(active.address, legacy.address)
    }

    func testMigrationIsStoredAndRunsOnce() throws {
        defaults.set(try JSONEncoder().encode(home), forKey: SavedMacs.legacyKey)
        let first = saved.load()
        XCTAssertNotNil(defaults.data(forKey: SavedMacs.listKey))

        var list = first
        list.save(work)
        saved.save(list)
        XCTAssertEqual(saved.load().macs, [home, work])
    }

    func testTypedSessionsAddressMigratesWhenNoSavedMac() {
        defaults.set("zach@mac.tailnet.ts.net:2022", forKey: SettingsKey.sessionsAddress)

        let list = saved.load()

        XCTAssertEqual(list.macs.count, 1)
        let active = list.active
        XCTAssertEqual(active?.name, "Mac")
        XCTAssertEqual(active?.hostname, "mac.tailnet.ts.net")
        XCTAssertEqual(active?.port, 2022)
        XCTAssertEqual(active?.username, "zach")
    }

    func testFreshInstallHasNoMacs() {
        let list = saved.load()
        XCTAssertTrue(list.macs.isEmpty)
        XCTAssertNil(list.active)
        XCTAssertNil(defaults.data(forKey: SavedMacs.listKey))
    }

    func testDeletingEveryMacDoesNotMigrateTheLegacyMacAgain() throws {
        defaults.set(try JSONEncoder().encode(home), forKey: SavedMacs.legacyKey)
        var list = saved.load()
        list.remove(home.id)
        saved.save(list)

        XCTAssertTrue(saved.load().macs.isEmpty)
        XCTAssertNil(defaults.data(forKey: SavedMacs.legacyKey))
    }

    // MARK: Storage

    func testSaveAndLoadKeepTheListAndActiveMac() {
        var list = MacList()
        list.save(home)
        list.save(work)
        list.setActive(work.id)
        saved.save(list)

        let loaded = saved.load()
        XCTAssertEqual(loaded.macs, [home, work])
        XCTAssertEqual(loaded.activeID, work.id)
    }

    func testSaveKeepsTheLegacyKeyEqualToTheActiveMac() throws {
        var list = MacList(macs: [home, work])
        list.setActive(work.id)
        saved.save(list)

        let data = try XCTUnwrap(defaults.data(forKey: SavedMacs.legacyKey))
        XCTAssertEqual(try JSONDecoder().decode(Host.self, from: data), work)
    }

    func testSaveResetsStatus() {
        var online = home
        online.status = .online
        saved.save(MacList(macs: [online]))
        XCTAssertEqual(saved.load().active?.status, .unknown)
    }

    func testStaleActiveIDFallsBackToFirstMac() {
        saved.save(MacList(macs: [home, work]))
        defaults.set(UUID().uuidString, forKey: SavedMacs.activeKey)
        XCTAssertEqual(saved.load().activeID, home.id)
    }

    // MARK: List rules

    func testFirstMacBecomesActiveAndLaterOnesDoNot() {
        var list = MacList()
        list.save(home)
        list.save(work)
        XCTAssertEqual(list.activeID, home.id)
    }

    func testSaveReplacesTheMacWithTheSameID() {
        var list = MacList(macs: [home, work])
        var renamed = work
        renamed.name = "Office"
        renamed.hostname = "office.tailnet.ts.net"
        list.save(renamed)
        XCTAssertEqual(list.macs, [home, renamed])
    }

    func testSetActiveIgnoresUnknownID() {
        var list = MacList(macs: [home, work])
        list.setActive(work.id)
        list.setActive(UUID())
        XCTAssertEqual(list.activeID, work.id)
    }

    func testDeletingTheActiveMacMakesTheFirstOneLeftActive() {
        let third = Host(name: "Third", hostname: "third.local", username: "zach")
        var list = MacList(macs: [home, work, third])
        list.setActive(work.id)
        list.remove(work.id)
        XCTAssertEqual(list.macs, [home, third])
        XCTAssertEqual(list.activeID, home.id)
    }

    func testDeletingAnotherMacKeepsTheActiveOne() {
        var list = MacList(macs: [home, work])
        list.setActive(work.id)
        list.remove(home.id)
        XCTAssertEqual(list.activeID, work.id)
    }

    func testDeletingTheLastMacLeavesNoActiveMac() {
        var list = MacList(macs: [home])
        list.remove(home.id)
        XCTAssertTrue(list.macs.isEmpty)
        XCTAssertNil(list.active)
    }

    func testSharesLoginFindsAnotherMacWithTheSameTarget() {
        var alias = home
        alias.id = UUID()
        alias.name = "Home again"
        XCTAssertFalse(MacList(macs: [home, work]).sharesLogin(with: home))
        XCTAssertTrue(MacList(macs: [home, alias]).sharesLogin(with: home))
    }
}
