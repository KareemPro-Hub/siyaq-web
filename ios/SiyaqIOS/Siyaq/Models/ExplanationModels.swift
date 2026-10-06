import Foundation

// نماذج /api/explain مطابقة لـ متابعة-من-Codex/2026-10-02-المرحلة-3/عقد-الشرح-والتحقق.ts:
//   Evidence = Tafsir & {id, verseId}
//   Explanation = {status: "ready"|"abstained", claims: {text, evidence, excerpt}[], sourceVersion, model?, notice, reason?}
// المادة العلمية الوحيدة هنا هي evidence وexcerpt كما أعادهما الخادم. claims[].text شرح مولّد مساعد.

enum ExplanationStatus: Hashable, Sendable {
    case ready
    case abstained
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "ready": self = .ready
        case "abstained": self = .abstained
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .ready: return "ready"
        case .abstained: return "abstained"
        case .unknown(let value): return value
        }
    }
}

extension ExplanationStatus: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// دليل من التفسير المنقول كما أعاده الخادم (النص الأصلي والكتاب والموضع والرابط).
struct Evidence: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let verseId: String
    let bookId: Int
    let bookName: String
    let author: String
    let part: String
    let page: Int?
    let text: String
    /// قيمة غير موثوقة؛ تُعرض عبر SafeLink فقط، وتُخفى بأمان إن لم تصلح.
    let url: String

    init(id: String, verseId: String, bookId: Int, bookName: String, author: String, part: String, page: Int?, text: String, url: String) {
        self.id = id
        self.verseId = verseId
        self.bookId = bookId
        self.bookName = bookName
        self.author = author
        self.part = part
        self.page = page
        self.text = text
        self.url = url
    }
}

extension Evidence {
    private enum CodingKeys: String, CodingKey {
        case id, verseId, bookId, bookName, book, author, part, page, text, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        verseId = try c.decode(String.self, forKey: .verseId)
        bookId = try c.decode(Int.self, forKey: .bookId)
        // العقد: bookName (من Tafsir). نقبل book احتياطًا إن ورد بهذا الاسم.
        bookName = try c.decodeIfPresent(String.self, forKey: .bookName)
            ?? c.decodeIfPresent(String.self, forKey: .book)
            ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(verseId, forKey: .verseId)
        try c.encode(bookId, forKey: .bookId)
        try c.encode(bookName, forKey: .bookName)
        try c.encode(author, forKey: .author)
        try c.encode(part, forKey: .part)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encode(text, forKey: .text)
        try c.encode(url, forKey: .url)
    }
}

struct ExplanationClaim: Codable, Hashable, Sendable {
    /// شرح مولّد مساعد — ليس نصًا قرآنيًا ولا تفسيرًا منقولًا.
    let text: String
    /// اقتباس حرفي من نص الدليل.
    let excerpt: String
    let evidence: Evidence
}

struct Explanation: Codable, Hashable, Sendable {
    let status: ExplanationStatus
    let claims: [ExplanationClaim]
    let sourceVersion: String
    let model: String?
    let notice: String
    let reason: String?

    init(status: ExplanationStatus, claims: [ExplanationClaim], sourceVersion: String, model: String?, notice: String, reason: String?) {
        self.status = status
        self.claims = claims
        self.sourceVersion = sourceVersion
        self.model = model
        self.notice = notice
        self.reason = reason
    }
}

extension Explanation {
    private enum CodingKeys: String, CodingKey {
        case status, claims, sourceVersion, model, notice, reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(ExplanationStatus.self, forKey: .status)
        claims = try c.decodeIfPresent([ExplanationClaim].self, forKey: .claims) ?? []
        sourceVersion = try c.decodeIfPresent(String.self, forKey: .sourceVersion) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model)
        notice = try c.decodeIfPresent(String.self, forKey: .notice) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    /// يتحقق دفاعيًا من الشرح مقابل النتيجة المعروضة نفسها، ولا يعدّل أي نص.
    /// أي مخالفة ترفض الاستجابة كلها؛ لا عرض جزئي لاستجابة فشلت في التحقق.
    /// القواعد تطابق validateDraft/renderExplanation في عقد-الشرح-والتحقق.ts، مع شروط العرض في العميل.
    func verified(for result: ReviewResult) throws -> Explanation {
        // ١) الحالة ومعناها.
        switch status {
        case .unknown:
            throw ExplanationRejection.unknownStatus
        case .ready:
            guard !claims.isEmpty else { throw ExplanationRejection.contradictory }
        case .abstained:
            guard claims.isEmpty else { throw ExplanationRejection.contradictory }
        }
        guard claims.count <= Self.maxClaims else { throw ExplanationRejection.tooManyClaims }
        guard !notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExplanationRejection.missingNotice
        }

        // ٢) نفس إصدار بيانات النتيجة المعروضة.
        guard !sourceVersion.isEmpty, sourceVersion == result.sourceVersion else {
            throw ExplanationRejection.versionMismatch
        }

        // ٣) موضع مؤكد مختار.
        guard result.status == .matched, let selected = result.selected,
              selected.kind != .possible else {
            throw ExplanationRejection.notEligible
        }
        if case .unknown = selected.kind { throw ExplanationRejection.notEligible }
        let verseIDs = Set(selected.verses.map(\.id))

        for claim in claims {
            let evidence = claim.evidence
            // ٤) الدليل للموضع المختار، ومطابق تمامًا لتفسير معروض في النتيجة نفسها.
            guard verseIDs.contains(evidence.verseId) else { throw ExplanationRejection.evidenceOutsideSelection }
            guard Self.matchesDisplayedTafsir(evidence, in: result) else { throw ExplanationRejection.evidenceNotInResult }

            // ٥) الاقتباس الحرفي: بايتات UTF-8 متطابقة داخل نص الدليل (لا تكافؤ Unicode ولا تطبيع).
            let trimmedExcerpt = claim.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedExcerpt.utf16.count >= Self.minExcerptUTF16,
                  claim.excerpt.utf16.count <= Self.maxExcerptUTF16 else {
                throw ExplanationRejection.excerptLength
            }
            guard Self.containsBytes(evidence.text, claim.excerpt) else { throw ExplanationRejection.excerptNotVerbatim }

            // ٦) نص الشرح المولد: غير فارغ، محدود، بلا روابط أو وسوم أو أقواس قرآنية.
            let text = claim.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, claim.text.utf16.count <= Self.maxClaimUTF16,
                  !Self.containsForbiddenMarkup(claim.text) else {
                throw ExplanationRejection.unsupportedText
            }
        }
        return self
    }

    static let maxClaims = 3
    static let minExcerptUTF16 = 12
    static let maxExcerptUTF16 = 1500
    static let maxClaimUTF16 = 700

    /// مقارنة بالبايت؛ String.contains في Swift تعتبر الصيغ المتكافئة (NFC/NFD) متساوية، فلا تصلح هنا.
    static func containsBytes(_ haystack: String, _ needle: String) -> Bool {
        let n = Data(needle.utf8)
        guard !n.isEmpty else { return false }
        return Data(haystack.utf8).range(of: n) != nil
    }

    static func containsForbiddenMarkup(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("http:") || lowered.contains("https:") || lowered.contains("www.") { return true }
        return text.unicodeScalars.contains { ["<", ">", "\u{FD3E}", "\u{FD3F}"].contains($0) }
    }

    /// الدليل يطابق مدخلًا معروضًا في النتيجة بايتًا بايتًا (النص والكتاب والمؤلف والجزء والصفحة والرابط).
    static func matchesDisplayedTafsir(_ evidence: Evidence, in result: ReviewResult) -> Bool {
        result.tafsir
            .filter { $0.verseId == evidence.verseId }
            .flatMap(\.entries)
            .contains { entry in
                entry.bookId == evidence.bookId
                    && Data(entry.text.utf8) == Data(evidence.text.utf8)
                    && Data(entry.bookName.utf8) == Data(evidence.bookName.utf8)
                    && Data(entry.author.utf8) == Data(evidence.author.utf8)
                    && entry.part == evidence.part
                    && entry.page == evidence.page
                    && entry.url == evidence.url
            }
    }

}

/// أسباب رفض شرح في العميل (للاختبار وللتشخيص؛ لا تُعرض نصًا للمستخدم).
enum ExplanationRejection: Error, Equatable {
    case unknownStatus
    case contradictory
    case tooManyClaims
    case missingNotice
    case versionMismatch
    case notEligible
    case evidenceOutsideSelection
    case evidenceNotInResult
    case excerptLength
    case excerptNotVerbatim
    case unsupportedText
}
