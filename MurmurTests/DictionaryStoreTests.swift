import XCTest
@testable import Murmur

final class DictionaryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-dict-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @MainActor
    func testStartsEmpty() {
        XCTAssertEqual(DictionaryStore(directory: directory).words, [])
    }

    @MainActor
    func testAddTrimsAndIgnoresEmpty() {
        let store = DictionaryStore(directory: directory)
        store.add("  Trajekt  ")
        store.add("   ")
        store.add("")
        XCTAssertEqual(store.words, ["Trajekt"])
    }

    @MainActor
    func testAddDedupesCaseInsensitivelyKeepingFirstCasing() {
        let store = DictionaryStore(directory: directory)
        store.add("GStack")
        store.add("gstack")
        XCTAssertEqual(store.words, ["GStack"])
    }

    @MainActor
    func testRemoveAndPersistAcrossInstances() {
        let first = DictionaryStore(directory: directory)
        first.add("Trajekt")
        first.add("GStack")
        first.remove("Trajekt")

        let second = DictionaryStore(directory: directory)
        XCTAssertEqual(second.words, ["GStack"])
    }
}
