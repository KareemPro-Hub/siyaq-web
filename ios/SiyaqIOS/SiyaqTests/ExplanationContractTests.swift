import XCTest
import Foundation
@testable import Siyaq

/// المرحلة ١٠: التحقق الدفاعي من الشرح مقابل النتيجة المعروضة.
/// الأدلة من تفسير مجاهد في المثال الفعلي 01-partial دون تعديل؛ كل «تعديل» هنا حالة تقنية في الاختبار فقط
/// (لا تدخل موارد التطبيق ولا تُعرض مرجعًا علميًا). نص الشرح المولد نص اختباري صريح.
final class ExplanationContractTests: XCTestCase {
    private var result: ReviewResult!
    private var evidence: Evidence!
    private var excerpt: String!

    override func setUpWithError() throws {
        result = try Samples.result("01-partial")
        evidence = try ExplanationFixtures.evidence(from: result)
        excerpt = String(evidence.text.prefix(40))
    }

    private func make(
        status: ExplanationStatus = .ready,
        claims: [ExplanationClaim]? = nil,
        version: String = "2026-10-01",
        notice: String = "إشعار اختباري"
    ) -> Explanation {
        Explanation(
            status: status,
            claims: claims ?? [ExplanationClaim(text: ExplanationFixtures.generatedText, excerpt: excerpt, evidence: evidence)],
            sourceVersion: version,
            model: nil,
            notice: notice,
            reason: nil
        )
    }

    private func claim(text: String = ExplanationFixtures.generatedText, excerpt: String? = nil, evidence: Evidence? = nil) -> ExplanationClaim {
        ExplanationClaim(text: text, excerpt: excerpt ?? self.excerpt, evidence: evidence ?? self.evidence)
    }

    private func assertRejected(_ explanation: Explanation, _ reason: ExplanationRejection, against result: ReviewResult? = nil,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try explanation.verified(for: result ?? self.result), file: file, line: line) {
            XCTAssertEqual($0 as? ExplanationRejection, reason, file: file, line: line)
        }
    }

    private func evidenceVariant(text: String? = nil, bookId: Int? = nil, url: String? = nil, page: Int?? = nil, verseId: String? = nil) -> Evidence {
        Evidence(id: evidence.id, verseId: verseId ?? evidence.verseId, bookId: bookId ?? evidence.bookId,
                 bookName: evidence.bookName, author: evidence.author, part: evidence.part,
                 page: page ?? evidence.page, text: text ?? evidence.text, url: url ?? evidence.url)
    }

    // MARK: الأساس

    /// استجابة صحيحة تمر كما هي دون أي تعديل للنص.
    func testValidExplanationPassesUnchanged() throws {
        let explanation = make()
        let checked = try explanation.verified(for: result)
        XCTAssertEqual(checked, explanation)
        XCTAssertEqual(Data(checked.claims[0].evidence.text.utf8), Data(result.tafsir[0].entries[0].text.utf8))
    }

    // MARK: الإصدار

    func testVersionMustMatchDisplayedResult() {
        assertRejected(make(version: "2026-10-02"), .versionMismatch)
        assertRejected(make(version: ""), .versionMismatch)
        assertRejected(make(status: .abstained, claims: [], version: "older"), .versionMismatch)
    }

    @MainActor
    func testVersionMismatchHasItsOwnHonestMessage() async {
        let state = ExplanationController.state(for: make(version: "2026-10-02"), displayed: result)
        XCTAssertEqual(state, .failed(.explanationVersionMismatch))
        XCTAssertTrue(ReviewError.explanationVersionMismatch.message.contains("أعد المراجعة"))
    }

    // MARK: الاقتباس الحرفي بالبايت

    /// صيغة NFD مكافئة قانونيًا للنص لكنها ليست البايتات نفسها؛ تُرفض.
    func testCanonicallyEquivalentButDifferentBytesIsRejected() {
        let nfd = excerpt.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Data(nfd.utf8), Data(excerpt.utf8), "المقتطف يحوي محرفًا مركبًا (مثل أ)")
        assertRejected(make(claims: [claim(excerpt: nfd)]), .excerptNotVerbatim)
    }

    /// حذف التشكيل يغير البايتات؛ يُرفض.
    func testExcerptWithoutDiacriticsIsRejected() {
        let stripped = String(String.UnicodeScalarView(excerpt.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }))
        XCTAssertNotEqual(stripped, excerpt)
        assertRejected(make(claims: [claim(excerpt: stripped)]), .excerptNotVerbatim)
    }

    /// محارف غير مرئية مدسوسة داخل الاقتباس تُرفض.
    func testInvisibleCharactersInExcerptAreRejected() {
        let middle = excerpt.index(excerpt.startIndex, offsetBy: 10)
        for invisible in ["\u{200F}", "\u{200D}", "\u{FEFF}", "\u{200B}", "\u{0640}"] {
            var tampered = excerpt!
            tampered.insert(contentsOf: invisible, at: middle)
            assertRejected(make(claims: [claim(excerpt: tampered)]), .excerptNotVerbatim)
        }
    }

    func testWhitespaceVariantIsRejected() {
        let doubled = excerpt.replacingOccurrences(of: " ", with: "  ")
        XCTAssertNotEqual(doubled, excerpt)
        assertRejected(make(claims: [claim(excerpt: doubled)]), .excerptNotVerbatim)
    }

    func testExcerptLengthLimits() {
        assertRejected(make(claims: [claim(excerpt: String(evidence.text.prefix(5)))]), .excerptLength)
        assertRejected(make(claims: [claim(excerpt: "            ")]), .excerptLength)
        assertRejected(make(claims: [claim(excerpt: String(repeating: "ب", count: 1501))]), .excerptLength)
    }

    // MARK: الدليل يخص الموضع المختار ومطابق للمعروض

    func testEvidenceMustBelongToSelectedVerse() {
        assertRejected(make(claims: [claim(evidence: evidenceVariant(verseId: "4:42"))]), .evidenceOutsideSelection)
    }

    func testEvidenceMustMatchDisplayedTafsirExactly() {
        assertRejected(make(claims: [claim(evidence: evidenceVariant(text: evidence.text + " "))]), .evidenceNotInResult)
        assertRejected(make(claims: [claim(evidence: evidenceVariant(bookId: 27758))]), .evidenceNotInResult)
        assertRejected(make(claims: [claim(evidence: evidenceVariant(url: "https://quranpedia.net/"))]), .evidenceNotInResult)
        assertRejected(make(claims: [claim(evidence: evidenceVariant(page: .some(nil)))]), .evidenceNotInResult)
        let nfdEvidence = evidenceVariant(text: evidence.text.decomposedStringWithCanonicalMapping)
        assertRejected(make(claims: [claim(excerpt: String(nfdEvidence.text.prefix(40)), evidence: nfdEvidence)]), .evidenceNotInResult)
    }

    /// لا شرح لمواضع غير مؤكدة، حتى لو كان الدليل نفسه صحيحًا.
    func testUnconfirmedPositionsAreNeverExplained() throws {
        assertRejected(make(), .notEligible, against: try Samples.result("06-selected-possible"))
        assertRejected(make(), .notEligible, against: try Samples.result("02-choices"))
        assertRejected(make(), .notEligible, against: try Samples.result("03-possible"))
        assertRejected(make(), .notEligible, against: try Samples.result("04-not-found"))
    }

    // MARK: الاستجابات المجهولة أو المتناقضة أو الناقصة

    func testContradictoryOrUnknownResponsesAreRejected() {
        assertRejected(make(status: .ready, claims: []), .contradictory)
        assertRejected(make(status: .abstained), .contradictory)
        assertRejected(make(status: .unknown("partial")), .unknownStatus)
        assertRejected(make(claims: Array(repeating: claim(), count: 4)), .tooManyClaims)
        assertRejected(make(notice: "  "), .missingNotice)
    }

    func testIncompleteClaimsDoNotDecode() {
        let missingEvidence = #"{"status":"ready","claims":[{"text":"x","excerpt":"y"}],"sourceVersion":"2026-10-01","notice":"n"}"#
        let missingExcerpt = #"{"status":"ready","claims":[{"text":"x","evidence":{"id":"a","verseId":"4:43","bookId":269,"text":"t"}}],"sourceVersion":"2026-10-01","notice":"n"}"#
        for json in [missingEvidence, missingExcerpt] {
            XCTAssertThrowsError(try JSONDecoder().decode(Explanation.self, from: Data(json.utf8)))
        }
    }

    func testGeneratedTextRules() {
        for bad in ["انظر https://example.invalid", "انظر http://x", "www.example", "<b>نص</b>", "نص ﴿آية﴾", "   ",
                    String(repeating: "ن", count: 701)] {
            assertRejected(make(claims: [claim(text: bad)]), .unsupportedText)
        }
    }

    /// كل المخالفات تُرفض كاملة؛ لا عرض لادعاء صحيح بجوار ادعاء مخالف.
    func testOneBadClaimRejectsTheWholeExplanation() {
        let good = claim()
        let bad = claim(excerpt: excerpt.decomposedStringWithCanonicalMapping)
        assertRejected(make(claims: [good, bad]), .excerptNotVerbatim)
    }
}
