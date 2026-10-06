import Foundation
import Observation

/// نتيجة محفوظة محليًا مع تاريخ الحفظ ومصدرها. النتيجة تُحفظ كاملة كما وصلت من الخدمة.
struct SavedEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let savedAt: Date
    let origin: ResultOrigin
    let result: ReviewResult

    var candidate: Candidate? { result.selected }
    var sourceVersion: String { result.sourceVersion }
}

/// ملف المحفوظات على القرص.
struct SavedArchive: Codable {
    var schemaVersion: Int
    var entries: [SavedEntry]
}

/// حفظ وحذف النتائج على الجهاز فقط (Application Support). لا مزامنة ولا رفع.
/// القراءة لا تحتاج اتصالًا.
@Observable
final class SavedResultsStore {
    static let schemaVersion = 1
    static let fileName = "saved-results.json"

    /// حالة آخر تحميل من القرص.
    enum LoadStatus: Equatable {
        /// لا ملف بعد، أو ملف فارغ.
        case empty
        case loaded
        /// قُرئت المدخلات السليمة، وأُسقط عدد منها لا يُقرأ، مع نسخة احتياطية من الملف الأصلي.
        case recoveredPartially(dropped: Int)
        /// الملف ليس أرشيف محفوظات صالحًا؛ نُقل جانبًا دون حذف.
        case movedAside
        /// تعذر فتح الملف (مثل حماية الملفات أثناء القفل). لا يُكتب فوقه حتى تنجح القراءة.
        case readBlocked
        /// أُسقطت مدخلات تالفة وتعذر حفظ نسخة احتياطية من الأصل؛ السليم يُقرأ، والملف محمي من الكتابة.
        case recoveredWithoutBackup(dropped: Int)
        /// الملف من إصدار أحدث من التطبيق؛ يُقرأ ما أمكن ولا يُكتب فوقه بصيغة أقدم.
        case newerFormat(version: Int)
    }

    /// سبب منع الكتابة فوق ملف المحفوظات الحالي. ما دام قائمًا تُرفض كل كتابة.
    enum WriteProtection: Equatable {
        case unreadable
        case backupFailed
        case newerFormat(version: Int)
    }

    private(set) var entries: [SavedEntry] = []
    private(set) var loadStatus: LoadStatus = .empty
    private(set) var writeProtection: WriteProtection? = nil
    /// رسالة عربية تُعرض عند فشل القراءة أو الكتابة (تنبيه لمرة واحدة؛ يمسحه المستخدم).
    var lastError: String? = nil

    /// مصدر الرسالة الحالية حتى لا تمسح قراءة ناجحة فشل كتابة لم يُحل، ولا تبقى رسالة قراءة قديمة.
    private enum MessageSource { case load, write }
    @ObservationIgnored private var messageSource: MessageSource? = nil

    /// شرح دائم (لا يختفي بإغلاق التنبيه) ما دامت الكتابة ممنوعة.
    var readOnlyReason: String? {
        switch writeProtection {
        case .none:
            return nil
        case .unreadable:
            return "تعذر فتح ملف المحفوظات، فهو محمي من الكتابة حتى تنجح القراءة. لن يُحفظ أو يُحذف شيء الآن."
        case .backupFailed:
            return "بعض المحفوظات تالف، وتعذر حفظ نسخة احتياطية من الملف الأصلي، فهو محمي من الكتابة. المحفوظات السليمة معروضة للقراءة."
        case .newerFormat:
            return "المحفوظات محفوظة بصيغة إصدار أحدث من هذا التطبيق، فهي معروضة للقراءة فقط ولا يُكتب فوقها. حدّث التطبيق لتعديلها."
        }
    }

    /// هل تفيد إعادة المحاولة عند عودة التطبيق للواجهة؟
    var shouldRetryOnForeground: Bool {
        writeProtection == .unreadable || writeProtection == .backupFailed
    }

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        load()
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Siyaq", isDirectory: true)
    }

    // MARK: قراءة

    func entry(id: UUID) -> SavedEntry? {
        entries.first { $0.id == id }
    }

    func entry(matching outcome: ReviewOutcome) -> SavedEntry? {
        let result = outcome.result
        return entries.first {
            $0.origin == outcome.origin
                && $0.result.quote == result.quote
                && $0.result.selected?.id == result.selected?.id
                && $0.result.sourceVersion == result.sourceVersion
        }
    }

    func isSaved(_ outcome: ReviewOutcome) -> Bool {
        entry(matching: outcome) != nil
    }

    // MARK: كتابة

    /// يحفظ نتيجة مطابقة مختارة فقط. يعيد المدخل المحفوظ أو nil عند الرفض أو الفشل.
    @discardableResult
    func save(_ outcome: ReviewOutcome, now: Date = Date()) -> SavedEntry? {
        guard outcome.result.isDisplayableMatch else { return nil }
        guard ensureWritable() else { return nil }
        if let existing = entry(matching: outcome) { return existing }
        let entry = SavedEntry(id: UUID(), savedAt: now, origin: outcome.origin, result: outcome.result)
        let updated = [entry] + entries
        do {
            try persist(updated)
            entries = updated
            clearMessage()
            return entry
        } catch {
            report("تعذر حفظ النتيجة على الجهاز. تحقق من المساحة المتاحة ثم حاول مرة أخرى.", from: .write)
            return nil
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard entries.contains(where: { $0.id == id }) else { return false }
        return replace(with: entries.filter { $0.id != id })
    }

    @discardableResult
    func delete(atOffsets offsets: IndexSet) -> Bool {
        var updated = entries
        for index in offsets.sorted(by: >) where updated.indices.contains(index) {
            updated.remove(at: index)
        }
        return replace(with: updated)
    }

    @discardableResult
    func remove(_ outcome: ReviewOutcome) -> Bool {
        guard let existing = entry(matching: outcome) else { return false }
        return delete(id: existing.id)
    }

    // MARK: داخلي

    private func replace(with updated: [SavedEntry]) -> Bool {
        guard ensureWritable() else { return false }
        do {
            try persist(updated)
            entries = updated
            clearMessage()
            return true
        } catch {
            report("تعذر تحديث المحفوظات على الجهاز.", from: .write)
            return false
        }
    }

    private func persist(_ list: [SavedEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(SavedArchive(schemaVersion: Self.schemaVersion, entries: list))
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    // MARK: الرسائل

    private func report(_ message: String, from source: MessageSource) {
        lastError = message
        messageSource = source
    }

    /// نجاح كتابة: لا فشل قائم بعدها (الكتابة لا تنجح أصلًا ما دامت هناك حماية).
    private func clearMessage() {
        lastError = nil
        messageSource = nil
    }

    /// نجاح قراءة: تُمسح رسائل القراءة القديمة فقط، ويبقى أي فشل كتابة لم يُحل.
    private func clearLoadMessage() {
        if messageSource == .load {
            lastError = nil
            messageSource = nil
        }
    }

    // MARK: الحماية من الكتابة

    /// لا كتابة فوق ملف لم نقرأه كاملًا، أو لم نحفظ نسخة احتياطية منه، أو من إصدار أحدث.
    private func ensureWritable() -> Bool {
        switch writeProtection {
        case .none:
            return true
        case .unreadable:
            load()
        case .backupFailed:
            // الملف على القرص ما زال الأصل (لم نكتب فوقه)، فنعيد محاولة النسخ الاحتياطي.
            if copyAside(fileURL) {
                writeProtection = nil
                if case .recoveredWithoutBackup(let dropped) = loadStatus {
                    loadStatus = .recoveredPartially(dropped: dropped)
                }
            }
        case .newerFormat:
            break
        }
        guard let reason = readOnlyReason else { return true }
        report(reason, from: .write)
        return false
    }

    /// يعيد القراءة من القرص (مثلًا بعد عودة التطبيق للواجهة).
    func reload() {
        load()
    }

    // MARK: التحميل

    private func load() {
        let url = fileURL
        writeProtection = nil
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            loadStatus = .empty
            clearLoadMessage()
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // تعذر فتح الملف ليس دليلًا على تلفه: لا ننقله ولا نكتب فوقه.
            entries = []
            loadStatus = .readBlocked
            writeProtection = .unreadable
            report("تعذر فتح المحفوظات الآن. لن يُكتب فوقها؛ أعد فتح التطبيق.", from: .load)
            return
        }

        if data.isEmpty {
            entries = []
            loadStatus = .empty
            clearLoadMessage()
            return
        }

        // صيغة أحدث من المدعوم: لا نقل ولا كتابة بصيغة أقدم قد تفقد حقولها.
        if let version = (try? Self.decoder.decode(SchemaPeek.self, from: data))?.schemaVersion,
           version > Self.schemaVersion {
            let readable = (try? Self.decoder.decode(LossyArchive.self, from: data))?.entries.compactMap(\.value) ?? []
            entries = Self.deduplicated(readable)
            loadStatus = .newerFormat(version: version)
            writeProtection = .newerFormat(version: version)
            report(readOnlyReason ?? "", from: .load)
            return
        }

        guard let archive = try? Self.decoder.decode(LossyArchive.self, from: data) else {
            // ليس أرشيفًا صالحًا: ننقله جانبًا باسم فريد، ولا نحذفه.
            entries = []
            if moveAside(url) {
                loadStatus = .movedAside
                report("تعذرت قراءة المحفوظات السابقة، فحُفظت نسخة منها جانبًا على الجهاز.", from: .load)
            } else {
                loadStatus = .readBlocked
                writeProtection = .unreadable
                report("تعذرت قراءة المحفوظات السابقة، ولم يُكتب فوقها.", from: .load)
            }
            return
        }

        let readable = archive.entries.compactMap(\.value)
        let dropped = archive.entries.count - readable.count
        entries = Self.deduplicated(readable)

        guard dropped > 0 else {
            loadStatus = .loaded
            clearLoadMessage()
            return
        }

        // نسخة كاملة من الأصل قبل أي كتابة لاحقة؛ إن فشلت يُمنع أي كتابة فوقه.
        let count = ArabicFormat.number(dropped)
        if copyAside(url) {
            loadStatus = .recoveredPartially(dropped: dropped)
            report("تعذرت قراءة \(count) من المحفوظات، وحُفظت نسخة من الملف الأصلي جانبًا. بقية المحفوظات سليمة.", from: .load)
        } else {
            loadStatus = .recoveredWithoutBackup(dropped: dropped)
            writeProtection = .backupFailed
            report("تعذرت قراءة \(count) من المحفوظات، وتعذر حفظ نسخة احتياطية من الملف الأصلي، فلن يُكتب فوقه. بقية المحفوظات معروضة للقراءة.", from: .load)
        }
    }

    /// يزيل التكرار (نفس المعرف، أو نفس الاقتباس والموضع والإصدار والمصدر) ويبقي الأحدث.
    static func deduplicated(_ list: [SavedEntry]) -> [SavedEntry] {
        var seenIDs = Set<UUID>()
        var seenKeys = Set<String>()
        var result: [SavedEntry] = []
        for entry in list.sorted(by: { $0.savedAt > $1.savedAt }) {
            let key = [entry.origin.rawValue, entry.result.quote, entry.result.selected?.id ?? "-", entry.result.sourceVersion]
                .joined(separator: "\u{1F}")
            guard seenIDs.insert(entry.id).inserted, seenKeys.insert(key).inserted else { continue }
            result.append(entry)
        }
        return result
    }

    private func asideURL(_ kind: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return directory.appendingPathComponent("saved-results.\(kind)-\(stamp)-\(UUID().uuidString.prefix(8)).json")
    }

    private func moveAside(_ url: URL) -> Bool {
        (try? FileManager.default.moveItem(at: url, to: asideURL("unreadable"))) != nil
    }

    private func copyAside(_ url: URL) -> Bool {
        (try? FileManager.default.copyItem(at: url, to: asideURL("backup"))) != nil
    }

    /// قراءة رقم الصيغة وحده قبل أي فك كامل.
    private struct SchemaPeek: Decodable {
        let schemaVersion: Int?
    }

    /// فك متسامح: مدخل تالف لا يُسقط بقية المحفوظات.
    private struct LossyArchive: Decodable {
        let schemaVersion: Int?
        let entries: [LossyEntry]

        private enum CodingKeys: String, CodingKey { case schemaVersion, entries }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            entries = try c.decode([LossyEntry].self, forKey: .entries)
        }
    }

    private struct LossyEntry: Decodable {
        let value: SavedEntry?
        init(from decoder: Decoder) throws {
            value = try? SavedEntry(from: decoder)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
