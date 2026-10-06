import XCTest
@testable import Siyaq

/// المرحلة ٧: متانة المحفوظات عبر التحديثات والملفات الناقصة أو التالفة، ومنع التكرار، والمشاركة.
/// لا تغيير لأي نص قرآني: كل النصوص من ملفات أمثلة المحرك كما هي.
final class PersistenceRobustnessTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyaqRobust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent(SavedResultsStore.fileName) }

    private func sampleJSON(_ name: String) throws -> String {
        String(decoding: try Samples.data(name), as: UTF8.self)
    }

    private func entryJSON(id: String, savedAt: Int, origin: String = "live", result: String) -> String {
        #"{"id":"\#(id)","origin":"\#(origin)","result":\#(result),"savedAt":\#(savedAt)}"#
    }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: التحديث من إصدار سابق

    /// مسار الملف واسمه عقد مع الإصدارات المنشورة؛ تغييرهما يفقد محفوظات المستخدمين بعد التحديث.
    func testStorageLocationIsStable() {
        XCTAssertEqual(SavedResultsStore.fileName, "saved-results.json")
        XCTAssertEqual(SavedResultsStore.defaultDirectory().lastPathComponent, "Siyaq")
    }

    /// ملف بصيغة الإصدار ١ كما يكتبها التسليم الأول (مفاتيح مرتبة، تاريخ بالثواني) يُقرأ كاملًا.
    func testVersionOneArchiveLoadsAfterUpdate() throws {
        let id = "8F0D3F43-6C42-4C59-9E44-0C1E3A7B2D10"
        let archive = #"{"entries":["# + entryJSON(id: id, savedAt: 1790000000, result: try sampleJSON("05-full-no-tafsir")) + #"],"schemaVersion":1}"#
        try Data(archive.utf8).write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .loaded)
        XCTAssertNil(store.lastError)
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.id.uuidString, id)
        XCTAssertEqual(entry.savedAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(entry.result, try Samples.result("05-full-no-tafsir"))
    }

    /// ملف من إصدار أحدث فيه حقول إضافية: يُقرأ ولا يُنقل جانبًا (والحماية من الكتابة في Stage9DataProtectionTests).
    func testNewerArchiveWithExtraFieldsStillLoads() throws {
        let entry = entryJSON(id: UUID().uuidString, savedAt: 1790000100, result: try sampleJSON("01-partial"))
            .replacingOccurrences(of: #""origin":"live""#, with: #""origin":"live","note":"حقل مستقبلي","tags":["x"]"#)
        try Data((#"{"schemaVersion":2,"exportedBy":"future","entries":["# + entry + "]}").utf8).write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .newerFormat(version: 2))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try names(), [SavedResultsStore.fileName])
    }

    // MARK: ملفات ناقصة أو تالفة

    /// مدخل واحد تالف لا يُسقط البقية، ويُحفظ الملف الأصلي كاملًا قبل أي كتابة.
    func testOneCorruptEntryKeepsTheRestAndBacksUpOriginal() throws {
        let good = entryJSON(id: UUID().uuidString, savedAt: 1790000200, result: try sampleJSON("01-partial"))
        let broken = #"{"id":"not-a-uuid","origin":"live","result":{"status":"matched"},"savedAt":"yesterday"}"#
        let original = Data((#"{"entries":["# + good + "," + broken + #"],"schemaVersion":1}"#).utf8)
        try original.write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .recoveredPartially(dropped: 1))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertNotNil(store.lastError)

        let backup = try XCTUnwrap(try names().first { $0.hasPrefix("saved-results.backup-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), original, "النسخة الاحتياطية مطابقة بايتًا")

        // الحفظ التالي يكتب السليم فقط، والنسخة الاحتياطية تبقى.
        store.save(ReviewOutcome(result: try Samples.result("05-full-no-tafsir"), origin: .live))
        XCTAssertEqual(SavedResultsStore(directory: directory).entries.count, 2)
        XCTAssertTrue(try names().contains(backup))
    }

    /// ملف مقطوع في منتصفه (كتابة ناقصة): يُنقل جانبًا كما هو ولا يُحذف.
    func testTruncatedFileIsMovedAsideIntact() throws {
        let full = #"{"entries":["# + entryJSON(id: UUID().uuidString, savedAt: 1790000300, result: try sampleJSON("01-partial")) + #"],"schemaVersion":1}"#
        let truncated = Data(full.utf8).prefix(Data(full.utf8).count / 2)
        try truncated.write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .movedAside)
        XCTAssertTrue(store.entries.isEmpty)
        let aside = try XCTUnwrap(try names().first { $0.hasPrefix("saved-results.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(aside)), Data(truncated))
    }

    /// ملف فارغ (صفر بايت) لا يُعد خطأ ولا يُنقل.
    func testEmptyFileIsTreatedAsNoSavedResults() throws {
        try Data().write(to: file)
        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .empty)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(try names(), [SavedResultsStore.fileName])
    }

    /// تلف متكرر في الثانية نفسها لا يكتب فوق نسخة جانبية سابقة.
    func testRepeatedCorruptionKeepsEveryAsideCopy() throws {
        for marker in ["first", "second"] {
            try Data("garbage-\(marker)".utf8).write(to: file)
            _ = SavedResultsStore(directory: directory)
        }
        let asides = try names().filter { $0.hasPrefix("saved-results.unreadable-") }
        XCTAssertEqual(asides.count, 2)
        let contents = try Set(asides.map { String(decoding: try Data(contentsOf: directory.appendingPathComponent($0)), as: UTF8.self) })
        XCTAssertEqual(contents, ["garbage-first", "garbage-second"])
    }

    /// ملف لا يمكن فتحه (صلاحيات) لا يُنقل ولا يُكتب فوقه؛ الحفظ يُرفض بوضوح.
    func testUnreadableFileIsNeverOverwritten() throws {
        let original = Data((#"{"entries":[],"schemaVersion":1}"#).utf8)
        try original.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        // root يتجاوز الصلاحيات؛ عندها لا يمكن محاكاة الحالة.
        if FileManager.default.isReadableFile(atPath: file.path) {
            throw XCTSkip("لا يمكن محاكاة ملف غير مقروء بصلاحيات المستخدم الحالي.")
        }

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .readBlocked)
        XCTAssertNil(store.save(ReviewOutcome(result: try Samples.result("01-partial"), origin: .live)))
        XCTAssertNotNil(store.lastError)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(try Data(contentsOf: file), original, "لم يُكتب فوق الملف")
        XCTAssertEqual(try names(), [SavedResultsStore.fileName], "لم يُنقل جانبًا")

        // بعد زوال المانع: الحفظ ينجح ويحفظ القديم والجديد.
        XCTAssertNotNil(store.save(ReviewOutcome(result: try Samples.result("01-partial"), origin: .live)))
        XCTAssertEqual(store.loadStatus, .loaded)
    }

    // MARK: التكرار

    /// ملف فيه تكرار (من نسخة قديمة أو كتابتين متزامنتين) يُعرض دون تكرار، ويبقى الأحدث.
    func testDuplicatesInFileAreCollapsedKeepingNewest() throws {
        let result = try sampleJSON("01-partial")
        let older = entryJSON(id: UUID().uuidString, savedAt: 1790000000, result: result)
        let newerID = UUID().uuidString
        let newer = entryJSON(id: newerID, savedAt: 1790000500, result: result)
        let sameIDOther = entryJSON(id: newerID, savedAt: 1790000400, result: try sampleJSON("05-full-no-tafsir"))
        try Data((#"{"entries":["# + [older, newer, sameIDOther].joined(separator: ",") + #"],"schemaVersion":1}"#).utf8).write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id.uuidString, newerID)
        XCTAssertEqual(store.loadStatus, .loaded)
    }

    /// نفس النتيجة من الوضع الحي ومن المعاينة مدخلان مختلفان (المصدر جزء من الهوية).
    func testSameResultFromLiveAndPreviewAreDistinct() throws {
        let store = SavedResultsStore(directory: directory)
        let result = try Samples.result("01-partial")
        XCTAssertNotNil(store.save(ReviewOutcome(result: result, origin: .live)))
        XCTAssertNotNil(store.save(ReviewOutcome(result: result, origin: .preview)))
        XCTAssertEqual(SavedResultsStore(directory: directory).entries.count, 2)
    }

    // MARK: المشاركة بعد الحفظ

    /// نص المشاركة من نتيجة محفوظة بعد إعادة الفتح مطابق بايتًا لنص المشاركة قبل الحفظ.
    func testShareTextIsIdenticalBeforeAndAfterRelaunch() throws {
        for name in ["01-partial", "05-full-no-tafsir", "06-selected-possible"] {
            let result = try Samples.result(name)
            let before = ShareText.make(result: result, candidate: try XCTUnwrap(result.selected))

            let dir = directory.appendingPathComponent(name, isDirectory: true)
            SavedResultsStore(directory: dir).save(ReviewOutcome(result: result, origin: .live))
            let saved = try XCTUnwrap(SavedResultsStore(directory: dir).entries.first)
            let after = ShareText.make(result: saved.result, candidate: try XCTUnwrap(saved.candidate))
            XCTAssertEqual(Array(after.unicodeScalars), Array(before.unicodeScalars), name)
        }
    }

    /// آيات متجاورة (من سياق المثال الفعلي): كل النصوص بترتيبها، وموضع مدى صحيح، ورابط غير صالح لا يُشارك.
    func testShareForSpanningVersesAndUnsafeLink() throws {
        let base = try Samples.result("01-partial")
        let verses = Array(base.context.prefix(2)) // ٤:٤٢ و٤:٤٣ كما وردت
        let spanning = Candidate(id: "4:42-4:43", kind: .spanning, verses: verses, note: "")
        let entry = base.tafsir[0].entries[0]
        let unsafe = TafsirEntry(bookId: entry.bookId, bookName: entry.bookName, author: entry.author,
                                 part: entry.part, page: entry.page, text: entry.text, url: "javascript:alert(1)")
        let result = ReviewResult(status: .matched, quote: base.quote, candidates: [spanning], candidateCount: 1,
                                  selected: spanning, context: base.context,
                                  tafsir: [TafsirGroup(verseId: "4:43", entries: [unsafe])],
                                  differences: [], sourceVersion: base.sourceVersion)

        let text = ShareText.make(result: result, candidate: spanning)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], verses[0].text)
        XCTAssertEqual(lines[1], verses[1].text)
        XCTAssertEqual(lines[2], "سورة النساء · الآيات ٤٢–٤٣")
        XCTAssertTrue(text.contains("التفسير المنقول: تفسير مجاهد — مجاهد بن جبر"))
        XCTAssertFalse(text.contains("javascript"), "الرابط غير الآمن لا يُشارك")
        XCTAssertFalse(text.contains("تنبيه"), "لا تحذير تشابه لمطابقة ممتدة")
    }
}

/// ثبات الإلغاء والخروج من الشاشات.
@MainActor
final class CancellationStabilityTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// الخروج إلى الرئيسية أثناء انتظار نتيجة الموضع (cancelAll): لا تحديث متأخر لأي حالة.
    func testLeavingDuringSelectionIgnoresLateResponses() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("03-possible"))),
            .init(delay: .milliseconds(300), result: .success(try Samples.result("06-selected-possible"))),
        ])
        let session = ReviewSession()
        session.start(quote: "لا تقربوا الصلاه وانتم سكارى", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }
        session.select(candidateID: "4:43")
        XCTAssertEqual(session.selection, .loading)

        session.cancelAll()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.primary, .idle)
        XCTAssertEqual(session.selection, .idle)
        XCTAssertNil(session.selectedCandidateID)
    }

    /// الرجوع من شاشة الموضع فقط (cancelSelection) يبقي نتيجة الاقتباس كما هي.
    func testBackFromSelectionKeepsPrimaryResult() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("02-choices"))),
            .init(delay: .milliseconds(300), result: .success(try Samples.result("01-partial"))),
        ])
        let session = ReviewSession()
        session.start(quote: "غفور رحيم", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }
        session.select(candidateID: "2:173")
        session.cancelSelection()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(session.primary.outcome?.result.status, .choices)
        XCTAssertEqual(session.selection, .idle)
    }

    /// إعادة المحاولة بعد الإلغاء ترسل الطلب نفسه مرة واحدة وتكتمل.
    func testRetryAfterCancelSendsSameRequestOnce() async throws {
        let service = ScriptedService([
            .init(delay: .milliseconds(300), result: .success(try Samples.result("05-full-no-tafsir"))),
            .init(delay: .zero, result: .success(try Samples.result("05-full-no-tafsir"))),
        ])
        let session = ReviewSession()
        session.start(quote: "قل هو الله أحد", using: ServiceChoice(service: service, origin: .live))
        session.cancelPrimary()
        XCTAssertEqual(session.primary, .failed(.cancelled))
        session.retryPrimary()
        await waitUntil { session.primary.outcome != nil }
        XCTAssertEqual(session.primary.outcome?.result.selected?.id, "112:1")
        XCTAssertEqual(service.calls.map(\.quote), ["قل هو الله أحد", "قل هو الله أحد"])
        XCTAssertEqual(service.calls.map(\.selection), [nil, nil])
    }
}
