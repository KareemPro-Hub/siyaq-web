import XCTest
@testable import Siyaq

/// المرحلة ٩: حماية بيانات المحفوظات.
/// كل اختبار في مجلد مؤقت معزول خاص به؛ لا مساس بمحفوظات المستخدم. النصوص من أمثلة المحرك كما هي.
/// اختبارات الصلاحيات تُتخطى تحت root (يتجاوز الصلاحيات) وتُشغَّل كمستخدم عادي.
final class Stage9DataProtectionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyaqStage9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent(SavedResultsStore.fileName) }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func sampleJSON(_ name: String) throws -> String {
        String(decoding: try Samples.data(name), as: UTF8.self)
    }

    private func entryJSON(id: String = UUID().uuidString, savedAt: Int, result: String) -> String {
        #"{"id":"\#(id)","origin":"live","result":\#(result),"savedAt":\#(savedAt)}"#
    }

    /// أرشيف فيه مدخل سليم وآخر تالف.
    private func partiallyCorruptArchive() throws -> Data {
        let good = entryJSON(savedAt: 1790000200, result: try sampleJSON("01-partial"))
        let broken = #"{"id":"broken","origin":"live","result":{"status":"matched"},"savedAt":"x"}"#
        return Data((#"{"entries":["# + good + "," + broken + #"],"schemaVersion":1}"#).utf8)
    }

    private func outcome(_ name: String) throws -> ReviewOutcome {
        ReviewOutcome(result: try Samples.result(name), origin: .live)
    }

    /// يجعل المجلد للقراءة فقط (فيفشل النسخ الاحتياطي وأي كتابة) ويتحقق أن ذلك فعّال فعلًا.
    private func lockDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let probe = directory.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            throw XCTSkip("لا يمكن محاكاة مجلد للقراءة فقط بصلاحيات المستخدم الحالي (root).")
        }
    }

    private func unlockDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    }

    // MARK: ١ — فشل النسخ الاحتياطي يمنع أي كتابة فوق الأصل

    func testFailedBackupBlocksEveryWriteAndKeepsOriginalBytes() throws {
        let original = try partiallyCorruptArchive()
        try original.write(to: file)
        try lockDirectory()

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .recoveredWithoutBackup(dropped: 1))
        XCTAssertEqual(store.writeProtection, .backupFailed)
        XCTAssertEqual(store.entries.count, 1, "السليم قابل للقراءة")
        XCTAssertEqual(store.entries.first?.result, try Samples.result("01-partial"))
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.lastError?.contains("تعذر حفظ نسخة احتياطية") == true, "رسالة صادقة")
        XCTAssertNotNil(store.readOnlyReason)

        // كل كتابة تُرفض: حفظ وحذف.
        XCTAssertNil(store.save(try outcome("05-full-no-tafsir")))
        let existing = try XCTUnwrap(store.entries.first)
        XCTAssertFalse(store.delete(id: existing.id))
        XCTAssertFalse(store.delete(atOffsets: IndexSet(integer: 0)))
        XCTAssertEqual(store.entries.count, 1)

        // حتى بعد فتح المجلد: لا يُعاد ترتيب الملف إلا بعد نسخ احتياطي ناجح.
        try unlockDirectory()
        XCTAssertEqual(try Data(contentsOf: file), original, "بايتات الأصل لم تتغير")
        XCTAssertEqual(try names(), [SavedResultsStore.fileName], "لا ملفات جانبية ولا نقل")
    }

    /// بعد زوال المانع: الكتابة التالية تنسخ الأصل أولًا (مطابقًا بايتًا) ثم تحفظ.
    func testBackupIsRetriedBeforeFirstWriteAfterRecovery() throws {
        let original = try partiallyCorruptArchive()
        try original.write(to: file)
        try lockDirectory()
        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.writeProtection, .backupFailed)
        try unlockDirectory()

        XCTAssertNotNil(store.save(try outcome("05-full-no-tafsir")))
        XCTAssertNil(store.writeProtection)
        XCTAssertEqual(store.loadStatus, .recoveredPartially(dropped: 1))
        XCTAssertNil(store.lastError, "لا رسالة قديمة بعد نجاح المحاولة")

        let backup = try XCTUnwrap(try names().first { $0.hasPrefix("saved-results.backup-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), original)
        XCTAssertEqual(SavedResultsStore(directory: directory).entries.count, 2)
    }

    // MARK: ٢ — صيغة أحدث من المدعوم

    func testNewerSchemaIsReadOnlyAndNeverRewritten() throws {
        let entry = entryJSON(savedAt: 1790000100, result: try sampleJSON("01-partial"))
            .replacingOccurrences(of: #""origin":"live""#, with: #""origin":"live","folder":"حقل من إصدار أحدث""#)
        let original = Data((#"{"schemaVersion":2,"settings":{"sort":"date"},"entries":["# + entry + "]}").utf8)
        try original.write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .newerFormat(version: 2))
        XCTAssertEqual(store.writeProtection, .newerFormat(version: 2))
        XCTAssertEqual(store.entries.count, 1, "يُعرض ما أمكن قراءته")
        XCTAssertNotNil(store.readOnlyReason)

        XCTAssertNil(store.save(try outcome("05-full-no-tafsir")))
        XCTAssertFalse(store.delete(id: try XCTUnwrap(store.entries.first).id))
        XCTAssertNotNil(store.lastError)

        // إعادة الفتح لا تغيّر شيئًا.
        _ = SavedResultsStore(directory: directory)
        XCTAssertEqual(try Data(contentsOf: file), original, "لم يُكتب بصيغة أقدم")
        XCTAssertEqual(try names(), [SavedResultsStore.fileName], "لم يُنقل جانبًا")
    }

    /// صيغة أحدث ببنية لا يفهمها هذا الإصدار: لا تُعد تلفًا، لا تُنقل، لا يُكتب فوقها.
    func testNewerSchemaWithUnknownStructureIsNotMovedOrOverwritten() throws {
        let original = Data(#"{"schemaVersion":5,"items":{"a":[1,2,3]}}"#.utf8)
        try original.write(to: file)

        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .newerFormat(version: 5))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.save(try outcome("01-partial")))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try names(), [SavedResultsStore.fileName])
    }

    /// الإصدار الحالي وما قبله (بلا رقم صيغة) يبقيان قابلين للكتابة.
    func testCurrentAndLegacySchemasStayWritable() throws {
        for header in [#""schemaVersion":1,"#, ""] {
            let dir = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let archive = "{" + header + #""entries":["# + entryJSON(savedAt: 1790000000, result: try sampleJSON("01-partial")) + "]}"
            try Data(archive.utf8).write(to: dir.appendingPathComponent(SavedResultsStore.fileName))

            let store = SavedResultsStore(directory: dir)
            XCTAssertEqual(store.loadStatus, .loaded, header)
            XCTAssertNil(store.writeProtection)
            XCTAssertNotNil(store.save(try outcome("05-full-no-tafsir")), header)
            XCTAssertEqual(SavedResultsStore(directory: dir).entries.count, 2)
        }
    }

    // MARK: ٣ — الرسائل بعد إعادة المحاولة

    /// قراءة فاشلة ثم ناجحة (عند العودة للواجهة): لا تبقى الرسالة القديمة.
    func testSuccessfulReloadClearsStaleReadMessage() throws {
        try Data((#"{"entries":[],"schemaVersion":1}"#).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        if FileManager.default.isReadableFile(atPath: file.path) {
            throw XCTSkip("لا يمكن محاكاة ملف غير مقروء تحت root.")
        }
        let store = SavedResultsStore(directory: directory)
        XCTAssertEqual(store.loadStatus, .readBlocked)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.shouldRetryOnForeground)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        store.reload()
        XCTAssertEqual(store.loadStatus, .loaded)
        XCTAssertNil(store.lastError, "رسالة القراءة القديمة مُسحت")
        XCTAssertNil(store.readOnlyReason)
        XCTAssertFalse(store.shouldRetryOnForeground)
    }

    /// فشل قائم لا يُخفى: إغلاق التنبيه لا يزيل السبب الدائم، وكل محاولة فاشلة تعيد الرسالة.
    func testOngoingFailureStaysVisibleAfterDismissingAlert() throws {
        try Data(#"{"schemaVersion":9,"entries":[]}"#.utf8).write(to: file)
        let store = SavedResultsStore(directory: directory)
        store.lastError = nil // المستخدم أغلق التنبيه
        XCTAssertNotNil(store.readOnlyReason)

        XCTAssertNil(store.save(try outcome("01-partial")))
        XCTAssertEqual(store.lastError, store.readOnlyReason)

        store.reload()
        XCTAssertNotNil(store.lastError, "إعادة القراءة لا تُخفي فشلًا قائمًا")
        XCTAssertNotNil(store.readOnlyReason)
    }

    /// فشل كتابة ثم نجاحها: تُمسح الرسالة. وإعادة قراءة ناجحة لا تمسح فشل كتابة لم يُحل.
    func testWriteFailureMessageLifecycle() throws {
        let store = SavedResultsStore(directory: directory)
        try lockDirectory()

        XCTAssertNil(store.save(try outcome("01-partial")))
        let writeError = try XCTUnwrap(store.lastError)

        store.reload() // قراءة ناجحة (لا ملف) أثناء بقاء فشل الكتابة
        XCTAssertEqual(store.lastError, writeError, "لا تُخفى رسالة فشل كتابة لم يُحل")

        try unlockDirectory()
        XCTAssertNotNil(store.save(try outcome("01-partial")))
        XCTAssertNil(store.lastError, "لا رسالة قديمة بعد نجاح المحاولة")
    }
}
