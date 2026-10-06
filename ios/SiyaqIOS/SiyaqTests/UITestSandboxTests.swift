import XCTest
@testable import Siyaq

#if DEBUG
/// تهيئة اختبارات الواجهة: معزولة، Debug فقط، ولا تمس بيانات المستخدم.
final class UITestSandboxTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyaqSandboxRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNoEnvironmentMeansNoSandbox() {
        XCTAssertNil(UITestSandbox.configuration(environment: [:], applicationSupport: root))
        XCTAssertNil(UITestSandbox.configuration(environment: ["SIYAQ_UITEST_MODE": "preview"], applicationSupport: root))
    }

    func testUnsafeNamesAreRejected() {
        for bad in ["", "   ", "../Siyaq", "a/b", "مساحة", String(repeating: "a", count: 49)] {
            XCTAssertNil(UITestSandbox.configuration(environment: ["SIYAQ_UITEST_SANDBOX": bad], applicationSupport: root), bad)
        }
    }

    func testSandboxIsSeparateFromUserData() throws {
        let name = "t-\(UUID().uuidString.prefix(8))"
        let config = try XCTUnwrap(UITestSandbox.configuration(environment: ["SIYAQ_UITEST_SANDBOX": name], applicationSupport: root))
        XCTAssertEqual(config.directory, root.appendingPathComponent("SiyaqUITests/\(name)", isDirectory: true))
        XCTAssertNotEqual(config.directory.standardizedFileURL, root.appendingPathComponent("Siyaq", isDirectory: true).standardizedFileURL)
        XCTAssertNotEqual(config.directory.lastPathComponent, SavedResultsStore.defaultDirectory().lastPathComponent)
        XCTAssertEqual(config.suiteName, "siyaq.uitest.\(name)")
        config.defaults.removePersistentDomain(forName: config.suiteName)
    }

    /// المسح يطال مساحة الاختبار وحدها؛ ملف «المستخدم» المجاور يبقى بايتًا بايتًا.
    func testResetClearsOnlyTheSandbox() throws {
        let userDir = root.appendingPathComponent("Siyaq", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        let userFile = userDir.appendingPathComponent(SavedResultsStore.fileName)
        let userBytes = Data("user-data".utf8)
        try userBytes.write(to: userFile)

        let name = "t-\(UUID().uuidString.prefix(8))"
        let first = try XCTUnwrap(UITestSandbox.configuration(environment: ["SIYAQ_UITEST_SANDBOX": name], applicationSupport: root))
        let store = SavedResultsStore(directory: first.directory)
        store.save(ReviewOutcome(result: try Samples.result("01-partial"), origin: .preview))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))

        _ = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name, "SIYAQ_UITEST_RESET": "1"],
            applicationSupport: root
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), "مساحة الاختبار مُسحت")
        XCTAssertEqual(try Data(contentsOf: userFile), userBytes, "بيانات المستخدم لم تُمس")
        first.defaults.removePersistentDomain(forName: first.suiteName)
    }

    /// بديل الاتصال في اختبارات الواجهة يبقى في الذاكرة: لا يُكتب في أي UserDefaults ولا يظهر في الواجهة.
    func testServiceOverrideStaysInMemoryAndOutOfDefaults() throws {
        let name = "t-\(UUID().uuidString.prefix(8))"
        let config = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name, "SIYAQ_UITEST_MODE": "preview", "SIYAQ_UITEST_BASE_URL": "http://127.0.0.1:9"],
            applicationSupport: root
        ))
        XCTAssertEqual(config.service, ServiceConfiguration(source: .recordedSamples))
        XCTAssertNil(config.defaults.string(forKey: "siyaq.reviewMode"))
        XCTAssertNil(config.defaults.string(forKey: "siyaq.serviceBaseURL"))

        let live = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name + "l", "SIYAQ_UITEST_MODE": "live", "SIYAQ_UITEST_BASE_URL": " http://127.0.0.1:9 "],
            applicationSupport: root
        ))
        XCTAssertEqual(live.service, ServiceConfiguration(source: .live(baseURL: "http://127.0.0.1:9")))

        // قيمة غير معروفة أو غائبة ⇒ إعداد البناء نفسه.
        let other = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name + "x", "SIYAQ_UITEST_MODE": "everything"],
            applicationSupport: root
        ))
        XCTAssertNil(other.service)
        for c in [config, live, other] { c.defaults.removePersistentDomain(forName: c.suiteName) }
    }

    // MARK: المرحلة ١٤ — تهيئة حالات حماية المحفوظات

    private func seeded(_ name: String, _ extra: [String: String]) throws -> UITestSandbox.Configuration {
        let result = try Samples.result("01-partial")
        let config = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name].merging(extra) { $1 },
            applicationSupport: root,
            seedResult: { result }
        ))
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: config.directory.path)
            config.defaults.removePersistentDomain(forName: config.suiteName)
        }
        return config
    }

    /// صيغة أحدث: المتجر للقراءة فقط، والمدخل من مثال المحرك كما هو.
    func testNewerFormatSeedMakesTheStoreReadOnly() throws {
        let config = try seeded("seed-newer", ["SIYAQ_UITEST_RESET": "1", "SIYAQ_UITEST_SEED": "newer-format"])
        let store = SavedResultsStore(directory: config.directory)
        XCTAssertEqual(store.loadStatus, .newerFormat(version: 99))
        XCTAssertEqual(store.entries.first?.result, try Samples.result("01-partial"))
        XCTAssertTrue(store.isSaved(ReviewOutcome(result: try Samples.result("01-partial"), origin: .preview)))
        XCTAssertFalse(store.remove(ReviewOutcome(result: try Samples.result("01-partial"), origin: .preview)))
    }

    /// تالف جزئيًا + قفل: فشل النسخ الاحتياطي وقراءة فقط؛ تشغيل لاحق بلا قفل يتعافى وينسخ ثم يكتب.
    func testPartialCorruptSeedWithLockThenRecoveryOnNextLaunch() throws {
        let name = "seed-lock"
        let locked = try seeded(name, ["SIYAQ_UITEST_RESET": "1", "SIYAQ_UITEST_SEED": "partial-corrupt", "SIYAQ_UITEST_LOCK_STORE": "1"])
        let probe = locked.directory.appendingPathComponent("probe")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            throw XCTSkip("لا يمكن محاكاة مجلد للقراءة فقط بصلاحيات المستخدم الحالي (root).")
        }
        let first = SavedResultsStore(directory: locked.directory)
        XCTAssertEqual(first.writeProtection, .backupFailed)
        XCTAssertEqual(first.entries.count, 1)
        let outcome = ReviewOutcome(result: try Samples.result("01-partial"), origin: .preview)
        XCTAssertFalse(first.remove(outcome), "لا إزالة ناجحة")
        XCTAssertTrue(first.isSaved(outcome))

        // التشغيل التالي بلا قفل وبلا مسح: المجلد يعود قابلًا للكتابة.
        let next = try seeded(name, [:])
        let second = SavedResultsStore(directory: next.directory)
        XCTAssertNil(second.writeProtection)
        XCTAssertEqual(second.loadStatus, .recoveredPartially(dropped: 1))
        XCTAssertTrue(second.remove(outcome))
        let names = try FileManager.default.contentsOfDirectory(atPath: next.directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("saved-results.backup-") }, "نسخة احتياطية قبل الكتابة")
    }

    /// المسح ينجح حتى بعد قفل تشغيل سابق؛ والتهيئة لا تكتب خارج مساحة الاختبار.
    func testResetAfterLockAndSeedsStayInsideTheSandbox() throws {
        let userDir = root.appendingPathComponent("Siyaq", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        let userFile = userDir.appendingPathComponent(SavedResultsStore.fileName)
        try Data("user-data".utf8).write(to: userFile)

        let name = "seed-reset"
        _ = try seeded(name, ["SIYAQ_UITEST_SEED": "newer-format", "SIYAQ_UITEST_LOCK_STORE": "1"])
        let fresh = try seeded(name, ["SIYAQ_UITEST_RESET": "1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.directory.appendingPathComponent(SavedResultsStore.fileName).path))
        XCTAssertEqual(try Data(contentsOf: userFile), Data("user-data".utf8), "بيانات المستخدم لم تُمس")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: userDir.path), [SavedResultsStore.fileName])
    }

    func testUnknownSeedIsIgnored() throws {
        let config = try seeded("seed-unknown", ["SIYAQ_UITEST_RESET": "1", "SIYAQ_UITEST_SEED": "everything"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.directory.appendingPathComponent(SavedResultsStore.fileName).path))
    }

    /// تشغيل الاختبارات العادية (بلا متغير البيئة) لا يفعّل المساحة.
    func testCurrentIsNilWithoutEnvironment() {
        if ProcessInfo.processInfo.environment["SIYAQ_UITEST_SANDBOX"] == nil {
            XCTAssertNil(UITestSandbox.current)
        }
    }
}
#endif
