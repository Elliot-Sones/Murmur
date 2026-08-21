import XCTest
@testable import Murmur

final class ProfileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-profile-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @MainActor
    func testResolveMissReturnsNil() {
        let store = ProfileStore(directory: directory)
        XCTAssertNil(store.resolve(bundleId: "com.apple.mail"))
        XCTAssertNil(store.resolve(bundleId: nil))
    }

    @MainActor
    func testUpsertThenResolveIsCaseInsensitive() {
        let store = ProfileStore(directory: directory)
        let profile = AppProfile(bundleId: "com.apple.Mail", appName: "Mail", toneHint: "formal")
        store.upsert(profile)
        XCTAssertEqual(store.resolve(bundleId: "com.apple.mail"), profile)
    }

    @MainActor
    func testUpsertReplacesExistingProfileForSameBundleId() {
        let store = ProfileStore(directory: directory)
        store.upsert(AppProfile(bundleId: "com.tinyspeck.slackmacgap", toneHint: "casual"))
        store.upsert(AppProfile(bundleId: "com.tinyspeck.slackmacgap", toneHint: "very casual"))
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.resolve(bundleId: "com.tinyspeck.slackmacgap")?.toneHint, "very casual")
    }

    @MainActor
    func testRemoveAndPersistAcrossInstances() {
        let first = ProfileStore(directory: directory)
        first.upsert(AppProfile(bundleId: "com.apple.mail", toneHint: "formal"))
        first.upsert(AppProfile(bundleId: "com.apple.Notes", rawMode: true))
        first.remove(bundleId: "com.apple.mail")

        let second = ProfileStore(directory: directory)
        XCTAssertEqual(second.profiles.count, 1)
        XCTAssertEqual(second.resolve(bundleId: "com.apple.notes")?.rawMode, true)
    }
}
