import XCTest
@testable import Siyaq

/// الحفظ والحذف يبقيان بعد إعادة التشغيل (إعادة إنشاء المخزن من القرص).
final class SavedResultsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyaqStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func outcome(_ name: String, origin: ResultOrigin = .live) throws -> ReviewOutcome {
        ReviewOutcome(result: try Samples.result(name), origin: origin)
    }

    func testStartsEmptyWithoutFile() {
        let store = SavedResultsStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testSavePersistsAcrossRelaunchWithDateAndVersion() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.5)
        let store = SavedResultsStore(directory: directory)
        let saved = try XCTUnwrap(store.save(try outcome("01-partial"), now: date))

        let relaunched = SavedResultsStore(directory: directory)
        XCTAssertEqual(relaunched.entries.count, 1)
        let entry = try XCTUnwrap(relaunched.entries.first)
        XCTAssertEqual(entry.id, saved.id)
        XCTAssertEqual(entry.savedAt, date)
        XCTAssertEqual(entry.sourceVersion, "2026-10-01")
        XCTAssertEqual(entry.origin, .live)
        XCTAssertEqual(entry.result, try Samples.result("01-partial"))
    }

    func testSavedVerseTextIsByteIdentical() throws {
        let original = try Samples.result("06-selected-possible")
        let store = SavedResultsStore(directory: directory)
        store.save(ReviewOutcome(result: original, origin: .preview))

        let relaunched = SavedResultsStore(directory: directory)
        let restored = try XCTUnwrap(relaunched.entries.first?.result)
        for (a, b) in zip(restored.context, original.context) {
            XCTAssertEqual(Array(a.text.unicodeScalars), Array(b.text.unicodeScalars))
        }
        for (a, b) in zip(restored.tafsir[0].entries, original.tafsir[0].entries) {
            XCTAssertEqual(Array(a.text.unicodeScalars), Array(b.text.unicodeScalars))
            XCTAssertEqual(a.url, b.url)
        }
        XCTAssertEqual(restored.differences, original.differences)
    }

    func testOnlyMatchedWithSelectionCanBeSaved() throws {
        let store = SavedResultsStore(directory: directory)
        XCTAssertNil(store.save(try outcome("02-choices")))
        XCTAssertNil(store.save(try outcome("03-possible")))
        XCTAssertNil(store.save(try outcome("04-not-found")))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testSavingSameResultTwiceDoesNotDuplicate() throws {
        let store = SavedResultsStore(directory: directory)
        let first = store.save(try outcome("01-partial"))
        let second = store.save(try outcome("01-partial"))
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(store.isSaved(try outcome("01-partial")))
        XCTAssertFalse(store.isSaved(try outcome("01-partial", origin: .preview)))
    }

    func testNewestFirst() throws {
        let store = SavedResultsStore(directory: directory)
        store.save(try outcome("01-partial"), now: Date(timeIntervalSince1970: 100))
        store.save(try outcome("05-full-no-tafsir"), now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(store.entries.map(\.result.quote), ["قل هو الله أحد", "لا تقربوا الصلاة"])
    }

    func testDeletePersistsAcrossRelaunch() throws {
        let store = SavedResultsStore(directory: directory)
        let a = try XCTUnwrap(store.save(try outcome("01-partial")))
        store.save(try outcome("05-full-no-tafsir"))
        XCTAssertTrue(store.delete(id: a.id))

        let relaunched = SavedResultsStore(directory: directory)
        XCTAssertEqual(relaunched.entries.count, 1)
        XCTAssertEqual(relaunched.entries.first?.result.quote, "قل هو الله أحد")
        XCTAssertNil(relaunched.entry(id: a.id))
    }

    func testDeleteAtOffsetsAndRemoveByOutcome() throws {
        let store = SavedResultsStore(directory: directory)
        store.save(try outcome("01-partial"))
        store.save(try outcome("05-full-no-tafsir"))
        store.save(try outcome("06-selected-possible", origin: .preview))
        XCTAssertTrue(store.delete(atOffsets: IndexSet(integer: 0)))
        XCTAssertTrue(store.remove(try outcome("01-partial")))

        let relaunched = SavedResultsStore(directory: directory)
        XCTAssertEqual(relaunched.entries.map(\.result.quote), ["قل هو الله أحد"])
    }

    func testUnreadableFileIsMovedAsideNotDeleted() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(SavedResultsStore.fileName)
        try Data("not json".utf8).write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.lastError)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("saved-results.unreadable-") })
    }
}
