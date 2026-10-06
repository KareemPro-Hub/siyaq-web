import Foundation

/// مساحة معزولة لاختبارات الواجهة (XCUITest) — **Debug فقط**.
///
/// - تُفعَّل فقط بمتغير البيئة `SIYAQ_UITEST_SANDBOX=<اسم>` الذي يمرره هدف الاختبار عند التشغيل.
/// - المحفوظات في `Application Support/SiyaqUITests/<اسم>` والإعدادات في نطاق `siyaq.uitest.<اسم>`؛
///   لا تلمس أبدًا `Application Support/Siyaq` ولا `UserDefaults.standard` الخاصة بالمستخدم.
/// - `SIYAQ_UITEST_RESET=1` يمسح مساحة الاختبار نفسها فقط.
/// - `SIYAQ_UITEST_SEED=partial-corrupt|newer-format` يكتب ملف محفوظات اختباريًا في مساحة الاختبار وحدها
///   (مدخل من مثال المحرك المضمن كما هو + مدخل تالف تقني، أو صيغة أحدث). `SIYAQ_UITEST_LOCK_STORE=1`
///   يجعل مجلد مساحة الاختبار للقراءة فقط فيفشل النسخ الاحتياطي؛ بدونه يُعاد المجلد قابلًا للكتابة عند كل تشغيل.
/// - `SIYAQ_UITEST_OCR=sample|unreadable|unsupported` يستبدل منتقي الصور بصورة اختبار مولّدة في الذاكرة
///   (اقتباس المستخدم المثال، لا مورد علمي)، أو بيانات ليست صورة، أو يعطّل القارئ؛ لا يمس مكتبة الصور.
/// - `SIYAQ_UITEST_MODE=preview` يستخدم الأمثلة المسجلة بدل الخدمة، و`live` مع `SIYAQ_UITEST_BASE_URL` يستخدم عنوان اختبار؛
///   القيمة تبقى في ذاكرة العملية ولا تُحفظ، ولا يوجد ما يقابلها في واجهة التطبيق.
/// - في Release لا يُقرأ أي متغير بيئة، و`current` دائمًا nil.
enum UITestSandbox {
    struct Configuration {
        let name: String
        let directory: URL
        let suiteName: String
        let defaults: UserDefaults
        /// بديل منتقي الصور في اختبارات الواجهة (Debug فقط).
        var ocrFixture: OCRFixture? = nil
        /// بديل اتصال الخدمة في اختبارات الواجهة (Debug فقط): أمثلة مسجلة أو عنوان اختبار. nil ⇒ إعداد البناء.
        var service: ServiceConfiguration? = nil
    }

    enum OCRFixture: String {
        case sample, unreadable, unsupported
    }

    #if DEBUG
    enum Environment {
        static let sandbox = "SIYAQ_UITEST_SANDBOX"
        static let reset = "SIYAQ_UITEST_RESET"
        static let mode = "SIYAQ_UITEST_MODE"
        static let baseURL = "SIYAQ_UITEST_BASE_URL"
        static let seed = "SIYAQ_UITEST_SEED"
        static let lockStore = "SIYAQ_UITEST_LOCK_STORE"
        static let ocr = "SIYAQ_UITEST_OCR"
    }

    /// ملفات محفوظات اختبارية لحالات الحماية (المرحلة ١٤).
    enum Seed: String {
        case partialCorrupt = "partial-corrupt"
        case newerFormat = "newer-format"
    }

    static let rootFolderName = "SiyaqUITests"
    static let suitePrefix = "siyaq.uitest."
    #endif

    /// التهيئة الحالية للعملية، أو nil (دائمًا nil في Release).
    static let current: Configuration? = {
        #if DEBUG
        return configuration(environment: ProcessInfo.processInfo.environment)
        #else
        return nil
        #endif
    }()

    #if DEBUG
    /// دالة نقية قابلة للاختبار: تبني مساحة الاختبار من متغيرات البيئة.
    static func configuration(
        environment: [String: String],
        applicationSupport: URL? = nil,
        fileManager: FileManager = .default,
        seedResult: () -> ReviewResult? = { PreviewLibrary.bundled?.samples.first { $0.file == "01-partial" }?.result }
    ) -> Configuration? {
        guard let raw = environment[Environment.sandbox], let name = sanitizedName(raw) else { return nil }
        let base = applicationSupport
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base
            .appendingPathComponent(rootFolderName, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let suiteName = suitePrefix + name
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }

        // قفل تشغيل سابق لا يبقى إلا إن طُلب من جديد، ولا يمنع المسح.
        if fileManager.fileExists(atPath: directory.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        if environment[Environment.reset] == "1" {
            // يمسح مساحة هذا الاختبار وحدها.
            try? fileManager.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let raw = environment[Environment.seed], let seed = Seed(rawValue: raw), let result = seedResult(),
           let data = try? seedArchive(seed, result: result) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent(SavedResultsStore.fileName))
        }
        if environment[Environment.lockStore] == "1" {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }
        return Configuration(name: name, directory: directory, suiteName: suiteName, defaults: defaults,
                             ocrFixture: environment[Environment.ocr].flatMap(OCRFixture.init(rawValue:)),
                             service: serviceOverride(environment: environment))
    }

    /// بديل الاتصال لاختبار الواجهة: preview ⇒ أمثلة مسجلة؛ live ⇒ العنوان الممرر (ولو فارغًا)؛ غير ذلك ⇒ إعداد البناء.
    static func serviceOverride(environment: [String: String]) -> ServiceConfiguration? {
        switch environment[Environment.mode] {
        case "preview":
            return ServiceConfiguration(source: .recordedSamples)
        case "live":
            return ServiceConfiguration(source: .live(baseURL: ServiceConfiguration.cleaned(environment[Environment.baseURL])))
        default:
            return nil
        }
    }

    /// أرشيف اختباري: مدخل سليم من نتيجة المحرك كما هي، مع مدخل تالف تقني أو رقم صيغة أحدث.
    static func seedArchive(_ seed: Seed, result: ReviewResult) throws -> Data {
        let entry = SavedEntry(id: UUID(uuidString: "00000000-0000-4000-8000-000000000014")!,
                               savedAt: Date(timeIntervalSince1970: 1_790_000_000), origin: .preview, result: result)
        let good = String(decoding: try SavedResultsStore.encoder.encode(entry), as: UTF8.self)
        switch seed {
        case .partialCorrupt:
            let broken = #"{"id":"uitest-broken","origin":"preview","result":{"status":"matched"},"savedAt":"x"}"#
            return Data((#"{"schemaVersion":1,"entries":["# + good + "," + broken + "]}").utf8)
        case .newerFormat:
            return Data((#"{"schemaVersion":99,"entries":["# + good + "]}").utf8)
        }
    }
    #endif

    /// أحرف آمنة فقط حتى لا يخرج المسار عن مجلد الاختبارات.
    static func sanitizedName(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { return nil }
        return trimmed
    }
}
