import Foundation

// نماذج مطابقة لعقد خدمة المراجعة (الإصدار ١) — مدخلات/عقد-النتائج.ts.
// قواعد ثابتة:
// - النص القرآني يُفك ويُخزن ويُعرض كما ورد حرفيًا؛ لا تطبيع ولا تعديل.
// - الحقول الجديدة غير المعروفة تُتجاهل، والقيم النصية الجديدة للحالات تُحفظ كـ unknown دون فشل.

// MARK: - قيم نصية مرنة

/// حالة النتيجة: matched | choices | possible | not_found.
enum ReviewStatus: Hashable, Sendable {
    case matched
    case choices
    case possible
    case notFound
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "matched": self = .matched
        case "choices": self = .choices
        case "possible": self = .possible
        case "not_found": self = .notFound
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .matched: return "matched"
        case .choices: return "choices"
        case .possible: return "possible"
        case .notFound: return "not_found"
        case .unknown(let value): return value
        }
    }
}

/// نوع المرشح: full | partial | spanning | possible.
enum MatchKind: Hashable, Sendable {
    case full
    case partial
    case spanning
    case possible
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "full": self = .full
        case "partial": self = .partial
        case "spanning": self = .spanning
        case "possible": self = .possible
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .full: return "full"
        case .partial: return "partial"
        case .spanning: return "spanning"
        case .possible: return "possible"
        case .unknown(let value): return value
        }
    }
}

/// نوع جزء المقارنة: same | input | source.
enum DifferenceType: Hashable, Sendable {
    case same
    case input
    case source
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "same": self = .same
        case "input": self = .input
        case "source": self = .source
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .same: return "same"
        case .input: return "input"
        case .source: return "source"
        case .unknown(let value): return value
        }
    }
}

extension ReviewStatus: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension MatchKind: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension DifferenceType: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - الآية

struct Verse: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let surah: Int
    let surahName: String
    let ayah: Int
    /// النص الأصلي كما ورد من المصدر. لا يُعدل للعرض.
    let text: String
}

// MARK: - التفسير

struct TafsirEntry: Codable, Hashable, Sendable {
    let bookId: Int
    let bookName: String
    let author: String
    /// نص وليس عددًا بالضرورة.
    let part: String
    /// قد يكون null.
    let page: Int?
    let text: String
    /// قيمة غير موثوقة؛ لا تُفتح إلا عبر SafeLink (http/https فقط).
    let url: String

    init(bookId: Int, bookName: String, author: String, part: String, page: Int?, text: String, url: String) {
        self.bookId = bookId
        self.bookName = bookName
        self.author = author
        self.part = part
        self.page = page
        self.text = text
        self.url = url
    }
}

extension TafsirEntry {
    private enum CodingKeys: String, CodingKey {
        case bookId, bookName, author, part, page, text, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId = try c.decode(Int.self, forKey: .bookId)
        bookName = try c.decodeIfPresent(String.self, forKey: .bookName) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        // العقد يقول part نص؛ نتسامح إن وصل رقمًا دون افتراض ذلك.
        if let text = try? c.decodeIfPresent(String.self, forKey: .part) {
            part = text
        } else if let number = try? c.decodeIfPresent(Int.self, forKey: .part) {
            part = String(number)
        } else {
            part = ""
        }
        page = try? c.decodeIfPresent(Int.self, forKey: .page)
        text = try c.decode(String.self, forKey: .text)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

struct TafsirGroup: Codable, Hashable, Sendable {
    let verseId: String
    let entries: [TafsirEntry]

    init(verseId: String, entries: [TafsirEntry]) {
        self.verseId = verseId
        self.entries = entries
    }
}

extension TafsirGroup {
    private enum CodingKeys: String, CodingKey { case verseId, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verseId = try c.decode(String.self, forKey: .verseId)
        entries = try c.decodeIfPresent([TafsirEntry].self, forKey: .entries) ?? []
    }
}

// MARK: - المرشح

struct Candidate: Codable, Hashable, Identifiable, Sendable {
    /// معرف من الخدمة؛ يُعاد إرساله كما هو في selection.
    let id: String
    let kind: MatchKind
    let verses: [Verse]
    let note: String

    init(id: String, kind: MatchKind, verses: [Verse], note: String) {
        self.id = id
        self.kind = kind
        self.verses = verses
        self.note = note
    }
}

extension Candidate {
    private enum CodingKeys: String, CodingKey { case id, kind, verses, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(MatchKind.self, forKey: .kind)
        verses = try c.decodeIfPresent([Verse].self, forKey: .verses) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - مقارنة الألفاظ

struct Difference: Codable, Hashable, Sendable {
    let text: String
    let type: DifferenceType
}

// MARK: - مصادر النتيجة (إضافة اختيارية في العقد)

/// ما تعلنه الخدمة عن مصادرها لهذه النتيجة: نسخة النص القرآني، وكتب التفسير المحمّلة التي بُحث فيها
/// (ولو لم يرد فيها شيء للآية). غيابها (خدمة أقدم أو نتيجة محفوظة قديمة) لا يمنع العرض.
struct ResultSources: Codable, Hashable, Sendable {
    struct Quran: Codable, Hashable, Sendable {
        let name: String
        let version: String
    }
    struct TafsirBook: Codable, Hashable, Sendable {
        let bookId: Int
        let name: String
        let author: String
        let version: String
    }
    let quran: Quran?
    let tafsir: [TafsirBook]

    init(quran: Quran?, tafsir: [TafsirBook]) {
        self.quran = quran
        self.tafsir = tafsir
    }

    private enum CodingKeys: String, CodingKey { case quran, tafsir }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quran = try? c.decodeIfPresent(Quran.self, forKey: .quran)
        tafsir = (try? c.decodeIfPresent([TafsirBook].self, forKey: .tafsir)) ?? []
    }
}

/// كيف بحثت الخدمة: النسخة المهيأة للبحث (لا تُعرض بدل النص)، وما تجاهلته، وطريقة الوصول للمواضع.
struct ReviewSearchInfo: Codable, Hashable, Sendable {
    let query: String
    /// رموز غريبة أو عبارة تمهيدية مثل «قال تعالى» حُذفت من نسخة البحث فقط.
    let ignored: [String]
    /// exact | segments | similar | none
    let method: String

    init(query: String, ignored: [String], method: String) {
        self.query = query
        self.ignored = ignored
        self.method = method
    }

    private enum CodingKeys: String, CodingKey { case query, ignored, method }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = (try? c.decodeIfPresent(String.self, forKey: .query)) ?? ""
        ignored = ((try? c.decodeIfPresent([String].self, forKey: .ignored)) ?? []).filter { !$0.isEmpty }
        method = (try? c.decodeIfPresent(String.self, forKey: .method)) ?? ""
    }

    var foundBySegments: Bool { method == "segments" }
}

// MARK: - النتيجة

struct ReviewResult: Codable, Hashable, Sendable {
    let status: ReviewStatus
    let quote: String
    let candidates: [Candidate]
    let candidateCount: Int
    let selected: Candidate?
    let context: [Verse]
    let tafsir: [TafsirGroup]
    let differences: [Difference]
    let sourceVersion: String
    /// اختياري: مصادر النتيجة ونسخها كما تعلنها الخدمة.
    let sources: ResultSources?
    /// اختياري: بيانات البحث كما تعلنها الخدمة.
    let search: ReviewSearchInfo?

    init(
        status: ReviewStatus,
        quote: String,
        candidates: [Candidate],
        candidateCount: Int,
        selected: Candidate?,
        context: [Verse],
        tafsir: [TafsirGroup],
        differences: [Difference],
        sourceVersion: String,
        sources: ResultSources? = nil,
        search: ReviewSearchInfo? = nil
    ) {
        self.status = status
        self.quote = quote
        self.candidates = candidates
        self.candidateCount = candidateCount
        self.selected = selected
        self.context = context
        self.tafsir = tafsir
        self.differences = differences
        self.sourceVersion = sourceVersion
        self.sources = sources
        self.search = search
    }
}

extension ReviewResult {
    private enum CodingKeys: String, CodingKey {
        case status, quote, candidates, candidateCount, selected, context, tafsir, differences, sourceVersion, sources, search
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(ReviewStatus.self, forKey: .status)
        quote = try c.decode(String.self, forKey: .quote)
        let list = try c.decodeIfPresent([Candidate].self, forKey: .candidates) ?? []
        candidates = list
        candidateCount = try c.decodeIfPresent(Int.self, forKey: .candidateCount) ?? list.count
        selected = try c.decodeIfPresent(Candidate.self, forKey: .selected)
        context = try c.decodeIfPresent([Verse].self, forKey: .context) ?? []
        tafsir = try c.decodeIfPresent([TafsirGroup].self, forKey: .tafsir) ?? []
        differences = try c.decodeIfPresent([Difference].self, forKey: .differences) ?? []
        sourceVersion = try c.decodeIfPresent(String.self, forKey: .sourceVersion) ?? ""
        // حقل إضافي: صيغة غير متوقعة لا تُسقط النتيجة كلها.
        sources = try? c.decodeIfPresent(ResultSources.self, forKey: .sources)
        search = try? c.decodeIfPresent(ReviewSearchInfo.self, forKey: .search)
    }

    /// عدد المواضع التي لم تُرسل في القائمة (القائمة محدودة بـ ١٢).
    var hiddenCandidateCount: Int { max(0, candidateCount - candidates.count) }

    /// نتيجة يمكن عرضها كاملة وحفظها: مطابقة مع موضع مختار.
    var isDisplayableMatch: Bool { status == .matched && selected != nil }

    /// تشابه محتمل اختاره المستخدم؛ يبقى تشابهًا وليس مطابقة يقينية.
    var isSelectedPossible: Bool { selected?.kind == .possible }

    /// مجموعات التفسير التي تحتوي نصوصًا فعلًا.
    var tafsirWithEntries: [TafsirGroup] { tafsir.filter { !$0.entries.isEmpty } }
}

// MARK: - اتساق النتيجة (المرحلة ١٣)

/// سبب رفض نتيجة /api/review فُكت بنجاح لكنها متناقضة مع نفسها أو مع الطلب.
enum ReviewInconsistency: Error, Equatable {
    case quoteMismatch
    case selectionMismatch
    case missingSelected
    case selectedNotInCandidates
    case selectedWithoutVerses
    case unknownSelectedKind
    case emptyCandidateList
    case notFoundWithCandidates
    case duplicateCandidateIDs
    case verseIdentityMismatch
    case contextOutsideSelectedSurah
    case tafsirOutsideSelectedVerses
    case selectedKindMismatch
    case conflictingVerseContent
}

extension ReviewResult {
    /// يتحقق قبل العرض والحفظ أن النتيجة متسقة مع العقد والطلب، ويعيدها كما هي دون أي تعديل.
    /// القواعد مأخوذة من العقد والأمثلة الحقيقية فقط، ولا تمس ما لا يُعرض:
    /// - quote المُعاد هو المرسل (تُتجاهل فروق المسافات فقط).
    /// - selection مطلوب ⇒ selected هو ذلك الموضع نفسه.
    /// - matched ⇒ selected من المرشحات، بآيات، وبنوع معروف.
    /// - choices/possible ⇒ مرشح واحد على الأقل؛ not_found ⇒ لا مرشحات ولا selected.
    /// - معرفات المرشحات فريدة؛ معرف الآية «سورة:آية» يطابق رقميها.
    /// - مع selected: السياق من سورته، والتفسير لآياته فقط.
    /// - status المجهول يمر ليعرض «نتيجة غير مدعومة»، ولا يُعد مطابقة ولا يُحفظ.
    func verified(forQuote requested: String, selection: String?) throws -> ReviewResult {
        guard Self.collapsedWhitespace(quote) == Self.collapsedWhitespace(requested) else {
            throw ReviewInconsistency.quoteMismatch
        }
        if let selection, selected?.id != selection {
            throw ReviewInconsistency.selectionMismatch
        }

        var ids = Set<String>()
        for candidate in candidates where !ids.insert(candidate.id).inserted {
            throw ReviewInconsistency.duplicateCandidateIDs
        }

        switch status {
        case .matched:
            guard let selected else { throw ReviewInconsistency.missingSelected }
            // الخادم يرسل أول ١٢ مرشحًا فقط؛ الاختيار الصريح قد يخص موضعًا صحيحًا خارجها.
            let explicitHiddenSelection = selection == selected.id && candidateCount > candidates.count
            guard ids.contains(selected.id) || explicitHiddenSelection else {
                throw ReviewInconsistency.selectedNotInCandidates
            }
            guard !selected.verses.isEmpty else { throw ReviewInconsistency.selectedWithoutVerses }
            if case .unknown = selected.kind { throw ReviewInconsistency.unknownSelectedKind }
        case .choices, .possible:
            guard !candidates.isEmpty else { throw ReviewInconsistency.emptyCandidateList }
        case .notFound:
            guard candidates.isEmpty, selected == nil else { throw ReviewInconsistency.notFoundWithCandidates }
        case .unknown:
            break
        }

        let allVerses = candidates.flatMap(\.verses) + (selected?.verses ?? []) + context
        guard allVerses.allSatisfy(Self.identityMatches) else { throw ReviewInconsistency.verseIdentityMismatch }

        if let selected {
            let surahs = Set(selected.verses.map(\.surah))
            guard context.allSatisfy({ surahs.contains($0.surah) }) else {
                throw ReviewInconsistency.contextOutsideSelectedSurah
            }
            let verseIDs = Set(selected.verses.map(\.id))
            guard tafsir.allSatisfy({ verseIDs.contains($0.verseId) }) else {
                throw ReviewInconsistency.tafsirOutsideSelectedVerses
            }
        }
        // نسخ الآية المعروضة في المرشح/المختار/السياق يجب أن تحمل النص نفسه حرفيًا.
        var knownVerses: [String: Verse] = [:]
        for verse in allVerses {
            if let known = knownVerses[verse.id] {
                guard known.surah == verse.surah, known.ayah == verse.ayah,
                      Data(known.surahName.utf8) == Data(verse.surahName.utf8),
                      Data(known.text.utf8) == Data(verse.text.utf8) else {
                    throw ReviewInconsistency.conflictingVerseContent
                }
            } else {
                knownVerses[verse.id] = verse
            }
        }
        if let selected, let listed = candidates.first(where: { $0.id == selected.id }),
           selected.kind != listed.kind {
            throw ReviewInconsistency.selectedKindMismatch
        }
        return self
    }

    /// معرف بصيغة «سورة:آية» يجب أن يطابق الرقمين؛ أي صيغة أخرى لا يُحكم عليها.
    private static func identityMatches(_ verse: Verse) -> Bool {
        let parts = verse.id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let surah = Int(parts[0]), let ayah = Int(parts[1]) else { return true }
        return surah == verse.surah && ayah == verse.ayah
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

// MARK: - مصدر النتيجة

/// هل النتيجة من الخدمة الحية أم من أمثلة المعاينة المسجلة؟
enum ResultOrigin: String, Codable, Hashable, Sendable {
    case live
    case preview
}

struct ReviewOutcome: Hashable, Sendable {
    let result: ReviewResult
    let origin: ResultOrigin
}

// MARK: - ملخص المصادر للعرض (بطاقة «المصدر» ولوحة «التفسير»)

/// كل ما تعرضه بطاقة «المصدر» محسوبًا من النتيجة نفسها، بلا SwiftUI حتى يُختبر:
/// روابط الآيات المحددة، وروابط مواضع التفسير المعروض، وحالة التوفر الفعلية، ونسخ البيانات المعلنة.
struct ResultSourceSummary: Equatable {
    struct VerseLink: Equatable {
        let verseId: String
        let surah: Int
        let ayah: Int
        let location: String
        let url: URL?
    }

    struct TafsirLink: Equatable {
        let verseId: String
        let bookId: Int
        let bookName: String
        let author: String
        let reference: String
        let url: URL?
    }

    struct BookVersion: Equatable {
        let name: String
        let version: String
    }

    /// الآيات المحددة فقط، بترتيبها.
    let verses: [VerseLink]
    let quranSourceName: String
    /// نسخة النص كما أعلنتها الخدمة (sources.quran.version ثم sourceVersion)، أو "" إن لم تُعلن.
    let quranVersion: String
    /// موضع كل نص تفسير معروض، بلا تكرار، ولآيات النتيجة المحددة فقط.
    let tafsir: [TafsirLink]
    /// الآيات المحددة التي لا يوجد لها نص تفسير محفوظ.
    let versesWithoutTafsir: [VerseLink]
    /// أسماء الكتب التي بُحث فيها كما أعلنتها الخدمة؛ فارغة إن لم تعلنها.
    let searchedBooks: [String]
    let tafsirVersions: [BookVersion]

    init(result: ReviewResult, candidate: Candidate) {
        let verseLinks = candidate.verses.map {
            VerseLink(verseId: $0.id, surah: $0.surah, ayah: $0.ayah,
                      location: ArabicFormat.location(of: $0),
                      url: SourceLinks.verse(surah: $0.surah, ayah: $0.ayah))
        }
        verses = verseLinks
        quranSourceName = result.sources?.quran?.name.isEmpty == false
            ? result.sources!.quran!.name
            : "الموسوعة القرآنية"
        let declared = result.sources?.quran?.version ?? ""
        quranVersion = declared.isEmpty ? result.sourceVersion : declared

        let selectedIDs = Set(candidate.verses.map(\.id))
        var seen = Set<String>()
        var links: [TafsirLink] = []
        var withText = Set<String>()
        for group in result.tafsir where selectedIDs.contains(group.verseId) {
            guard let verse = candidate.verses.first(where: { $0.id == group.verseId }) else { continue }
            for entry in group.entries {
                withText.insert(group.verseId)
                let reference = ArabicFormat.reference(part: entry.part, page: entry.page)
                let key = "\(group.verseId)|\(entry.bookId)|\(entry.part)|\(entry.page.map(String.init) ?? "-")"
                guard seen.insert(key).inserted else { continue }
                links.append(TafsirLink(verseId: group.verseId, bookId: entry.bookId,
                                        bookName: entry.bookName.isEmpty ? "كتاب غير مسمى" : entry.bookName,
                                        author: entry.author, reference: reference,
                                        url: SourceLinks.tafsirAyah(bookId: entry.bookId, surah: verse.surah, ayah: verse.ayah)))
            }
        }
        tafsir = links
        versesWithoutTafsir = verseLinks.filter { !withText.contains($0.verseId) }
        searchedBooks = result.sources?.tafsir.map(\.name).filter { !$0.isEmpty } ?? []
        tafsirVersions = (result.sources?.tafsir ?? [])
            .filter { !$0.name.isEmpty && !$0.version.isEmpty }
            .map { BookVersion(name: $0.name, version: $0.version) }
    }

    /// سبب صادق لغياب التفسير عن آية، دون عرض تفسير آية أخرى.
    var missingTafsirReason: String {
        if searchedBooks.isEmpty {
            return "لا يوجد نص تفسير محفوظ لهذه الآية في بيانات الخدمة الحالية، ولم نعرض تفسير آية أخرى بدلًا منه."
        }
        return "لا يوجد نص تفسير محفوظ لهذه الآية في الكتب المحمّلة حاليًا (\(searchedBooks.joined(separator: "، "))). لم نعرض تفسير آية أخرى بدلًا منه."
    }
}

// MARK: - رسائل البحث (لم نجد / أخطاء قراءة الصورة / مواضع محتملة)

/// نصوص صادقة تفرّق بين: لم نجد تطابقًا، واحتمال أخطاء في قراءة الصورة، والمواضع المحتملة بالمقاطع.
/// انقطاع الخدمة له رسائل ReviewError المستقلة ولا يمر من هنا.
enum ReviewSearchNotice {
    struct Message: Equatable {
        let title: String
        let message: String
    }

    static func notFound(fromImage: Bool) -> Message {
        if fromImage {
            return Message(
                title: "لم نعثر على موضع مطابق.",
                message: "قد توجد أخطاء في قراءة الصورة. قارن النص بالصورة وصحّح الكلمات المختلفة، أو احذف ما ليس من الآية، ثم أعد المراجعة. لم نصحح النص تلقائيًا."
            )
        }
        return Message(
            title: "لم نعثر على موضع مطابق.",
            message: "لم نجد هذا الاقتباس في النص القرآني ضمن بيانات المصدر الحالية. تأكد من الكتابة، أو جرّب جزءًا أطول من الآية."
        )
    }

    static func possible(search: ReviewSearchInfo?, fromImage: Bool) -> Message {
        if search?.foundBySegments == true {
            return Message(
                title: "تشابه محتمل، وليس إثباتًا",
                message: fromImage
                    ? "لم يتطابق النص كاملًا، وقد توجد أخطاء في قراءة الصورة. وجدنا مقاطع عربية واضحة منه في هذه المواضع. اختر الموضع وقارن الكلمات بالنص الأصلي؛ لن يُعد مطابقة مؤكدة."
                    : "لم يتطابق النص كاملًا. وجدنا مقاطع عربية واضحة منه في هذه المواضع. اختر الموضع وقارن الكلمات بالنص الأصلي؛ لن يُعد مطابقة مؤكدة."
            )
        }
        return Message(
            title: "تشابه محتمل، وليس إثباتًا",
            message: "لم نجد مطابقة مؤكدة. هذه مواضع محتملة بسبب تشابه الألفاظ. قارن الكلمات بالنص الأصلي قبل الاختيار."
        )
    }

    /// رموز لاتينية أو أرقام أُهملت من البحث تدل غالبًا على قراءة صورة (كما في الموقع)؛ العبارة التمهيدية «قال تعالى» لا تدل.
    static func looksLikeImageText(_ search: ReviewSearchInfo?) -> Bool {
        (search?.ignored ?? []).contains { !$0.hasPrefix("«") }
    }

    /// ما تجاهله البحث من نسخة البحث فقط؛ nil إن لم يُتجاهل شيء.
    static func ignored(_ search: ReviewSearchInfo?) -> String? {
        guard let items = search?.ignored, !items.isEmpty else { return nil }
        let shown = items.prefix(8).joined(separator: "، ")
        let more = items.count > 8 ? "، وغيرها" : ""
        return "تجاهل البحث ما ليس من نص الآية: \(shown)\(more). نصك المعروض لم يتغير."
    }
}
