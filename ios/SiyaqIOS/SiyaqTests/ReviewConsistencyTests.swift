import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Siyaq

/// المرحلة ١٣: اتساق نتيجة /api/review قبل العرض والحفظ، عبر حدود الخدمة الحية نفسها (StubURLProtocol، بلا شبكة).
/// الأمثلة الحقيقية الستة تمر كما هي. كل «تعديل» هنا تحويل تقني لنسخة في الذاكرة داخل الاختبار فقط،
/// لا يدخل موارد التطبيق ولا يُعرض مرجعًا علميًا.
final class ReviewConsistencyTests: XCTestCase {
    private let endpoint = URL(string: "https://service.invalid/api/review")!

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// يمرر الجسم عبر LiveReviewService كما لو جاء من الخادم.
    private func review(_ body: Data, quote: String, selection: String? = nil) async -> Result<ReviewResult, ReviewError> {
        StubURLProtocol.handler = { _ in .init(status: 200, body: body) }
        do {
            let service = LiveReviewService(endpoint: endpoint, session: StubURLProtocol.session())
            return .success(try await service.review(quote: quote, selection: selection))
        } catch {
            return .failure(error as? ReviewError ?? .invalidResponse)
        }
    }

    /// نسخة JSON قابلة للتحويل من مثال حقيقي.
    private func json(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Samples.data(name)) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func assertRejected(_ object: [String: Any], quote: String, selection: String? = nil,
                                _ reason: ReviewInconsistency, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) async throws {
        // السبب نفسه، لا مجرد أي فشل.
        let decoded = try JSONDecoder().decode(ReviewResult.self, from: try data(object))
        XCTAssertThrowsError(try decoded.verified(forQuote: quote, selection: selection), message, file: file, line: line) {
            XCTAssertEqual($0 as? ReviewInconsistency, reason, message, file: file, line: line)
        }
        let outcome = await review(try data(object), quote: quote, selection: selection)
        switch outcome {
        case .success(let result):
            XCTFail("قُبلت نتيجة غير متسقة (\(message)): status=\(result.status.rawValue) selected=\(result.selected?.id ?? "nil")",
                    file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, .invalidResponse, message, file: file, line: line)
        }
    }

    private static let partialQuote = "لا تقربوا الصلاة"

    // MARK: الأمثلة الحقيقية

    /// الأمثلة الستة كما وردت من المحرك تمر دون تعديل، بالاقتباس وselection الذي أنتجها.
    func testRealSamplesPassUnchanged() async throws {
        for item in PreviewLibrary.manifest {
            let raw = try Samples.data(item.file)
            let expected = try Samples.result(item.file)
            let outcome = await review(raw, quote: expected.quote, selection: item.selection)
            XCTAssertEqual(try outcome.get(), expected, item.file)
        }
    }

    /// فروق المسافات فقط بين المرسل والمُعاد ليست تناقضًا.
    func testWhitespaceOnlyEchoDifferenceIsAccepted() async throws {
        let raw = try Samples.data("01-partial")
        let outcome = await review(raw, quote: "لا  تقربوا\nالصلاة")
        XCTAssertNoThrow(try outcome.get())
    }

    // MARK: علاقة النتيجة بالطلب

    func testEchoedQuoteMustMatchRequest() async throws {
        try await assertRejected(try json("01-partial"), quote: "قل هو الله أحد", .quoteMismatch, "الاقتباس المُعاد لاقتباس آخر")
    }

    func testSelectedMustBeTheRequestedPosition() async throws {
        try await assertRejected(try json("01-partial"), quote: Self.partialQuote, selection: "4:42", .selectionMismatch, "الموضع المعروض غير المطلوب")
        var notMatched = try json("02-choices")
        notMatched["quote"] = "غفور رحيم"
        try await assertRejected(notMatched, quote: "غفور رحيم", selection: "2:173", .selectionMismatch, "طلب موضع وعادت قائمة بلا موضع")
    }

    // MARK: الحالة والموضع المختار

    func testMatchedNeedsASelectedCandidateFromTheList() async throws {
        var noSelected = try json("01-partial")
        noSelected["selected"] = NSNull()
        try await assertRejected(noSelected, quote: Self.partialQuote, .missingSelected, "matched بلا selected")

        var outsideList = try json("01-partial")
        outsideList["candidates"] = try json("05-full-no-tafsir")["candidates"]
        try await assertRejected(outsideList, quote: Self.partialQuote, .selectedNotInCandidates, "selected ليس من المرشحات")
    }

    func testSelectedNeedsVersesAndAKnownKind() async throws {
        var noVerses = try json("01-partial")
        var selected = try XCTUnwrap(noVerses["selected"] as? [String: Any])
        selected["verses"] = [Any]()
        noVerses["selected"] = selected
        try await assertRejected(noVerses, quote: Self.partialQuote, .selectedWithoutVerses, "selected بلا آيات")

        var unknownKind = try json("01-partial")
        var kindSelected = try XCTUnwrap(unknownKind["selected"] as? [String: Any])
        kindSelected["kind"] = "technical-unknown-kind"
        unknownKind["selected"] = kindSelected
        try await assertRejected(unknownKind, quote: Self.partialQuote, .unknownSelectedKind, "نوع مطابقة مجهول يُعرض كنتيجة")
    }

    func testListStatusesNeedConsistentCandidates() async throws {
        var emptyChoices = try json("02-choices")
        emptyChoices["candidates"] = [Any]()
        try await assertRejected(emptyChoices, quote: "غفور رحيم", .emptyCandidateList, "choices بلا مرشحات")

        var foundButNotFound = try json("04-not-found")
        foundButNotFound["candidates"] = try json("01-partial")["candidates"]
        let quote = try XCTUnwrap(foundButNotFound["quote"] as? String)
        try await assertRejected(foundButNotFound, quote: quote, .notFoundWithCandidates, "not_found مع مرشحات")

        var duplicates = try json("02-choices")
        let list = try XCTUnwrap(duplicates["candidates"] as? [Any])
        duplicates["candidates"] = [list[0], list[0]] + list.dropFirst()
        try await assertRejected(duplicates, quote: "غفور رحيم", .duplicateCandidateIDs, "معرف مرشح مكرر")
    }

    // MARK: الآيات والسياق والتفسير

    func testVerseIdentityMustMatchSurahAndAyah() async throws {
        var wrong = try json("01-partial")
        var selected = try XCTUnwrap(wrong["selected"] as? [String: Any])
        var verses = try XCTUnwrap(selected["verses"] as? [[String: Any]])
        verses[0]["ayah"] = 44
        selected["verses"] = verses
        wrong["selected"] = selected
        try await assertRejected(wrong, quote: Self.partialQuote, .verseIdentityMismatch, "معرف الآية لا يطابق رقمها")
    }

    func testContextMustStayInTheSelectedSurah() async throws {
        var foreign = try json("01-partial")
        var context = try XCTUnwrap(foreign["context"] as? [Any])
        let otherSurah = try XCTUnwrap(try json("05-full-no-tafsir")["context"] as? [Any])
        context.append(otherSurah[0])
        foreign["context"] = context
        try await assertRejected(foreign, quote: Self.partialQuote, .contextOutsideSelectedSurah, "سياق من سورة أخرى")
    }

    func testTafsirMustBelongToTheSelectedVerses() async throws {
        var shifted = try json("01-partial")
        var groups = try XCTUnwrap(shifted["tafsir"] as? [[String: Any]])
        groups[0]["verseId"] = "4:44"
        shifted["tafsir"] = groups
        try await assertRejected(shifted, quote: Self.partialQuote, .tafsirOutsideSelectedVerses, "تفسير آية غير المعروضة")
    }

    // MARK: ما لا يُرفض

    /// حالة مجهولة لا تُعد مطابقة؛ تمر لتعرض الواجهة «نتيجة غير مدعومة» ولا تُحفظ.
    func testUnknownStatusIsNotAMatchAndIsNotSaved() async throws {
        var unknown = try json("01-partial")
        unknown["status"] = "technical-unknown-status"
        let result = try await review(try data(unknown), quote: Self.partialQuote).get()
        XCTAssertFalse(result.isDisplayableMatch)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SiyaqUnknown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(SavedResultsStore(directory: directory).save(ReviewOutcome(result: result, origin: .live)))
    }

    /// candidateCount أكبر من المعروض مسموح في العقد.
    func testLimitedListIsAccepted() async throws {
        let result = try await review(try Samples.data("02-choices"), quote: "غفور رحيم").get()
        XCTAssertGreaterThan(result.candidateCount, result.candidates.count)
    }
    // مراجعة Codex: استجابة أصلية من الخادم المحلي + حالات تناقض تقنية لا تدخل موارد التطبيق.
    func testExplicitSelectionOutsideTheTruncatedListIsAccepted() async throws {
        let raw = try XCTUnwrap(Data(base64Encoded: "eyJzdGF0dXMiOiJtYXRjaGVkIiwicXVvdGUiOiLYutmB2YjYsSDYsdit2YrZhSIsImNhbmRpZGF0ZXMiOlt7ImlkIjoiMjoxNzMiLCJraW5kIjoicGFydGlhbCIsInZlcnNlcyI6W3siaWQiOiIyOjE3MyIsInN1cmFoIjoyLCJzdXJhaE5hbWUiOiLYp9mE2KjZgtix2KkiLCJheWFoIjoxNzMsInRleHQiOiLvu7/YpdmQ2YbZkdmO2YXZjtinINit2Y7YsdmR2Y7ZhdmOINi52Y7ZhNmO2YrZktmD2Y/ZhdmPINin2YTZktmF2Y7ZitmS2KrZjtip2Y4g2YjZjtin2YTYr9mR2Y7ZhdmOINmI2Y7ZhNmO2K3ZktmF2Y4g2KfZhNmS2K7ZkNmG2ZLYstmQ2YrYsdmQINmI2Y7ZhdmO2Kcg2KPZj9mH2ZDZhNmR2Y4g2KjZkNmH2ZAg2YTZkNi62Y7ZitmS2LHZkCDYp9mE2YTZkdmO2YfZkCDbliDZgdmO2YXZjtmG2ZAg2KfYttmS2LfZj9ix2ZHZjiDYutmO2YrZktix2Y4g2KjZjtin2LrZjSDZiNmO2YTZjtinINi52Y7Yp9iv2Y0g2YHZjtmE2Y7YpyDYpdmQ2KvZktmF2Y4g2LnZjtmE2Y7ZitmS2YfZkCDbmiDYpdmQ2YbZkdmOINin2YTZhNmR2Y7Zh9mOINi62Y7ZgdmP2YjYsdmMINix2Y7YrdmQ2YrZhdmMIn1dLCJub3RlIjoi2KfZhNin2YLYqtio2KfYsyDYrNiy2KEg2YXZhiDYp9mE2KLZitipLiDZhNinINmK2LnZhtmKINin2YTYp9iu2KrYtdin2LEg2YjYrdiv2Ycg2KPZhiDYp9mE2KfZgtiq2KjYp9izINiu2KfYt9im2Jsg2LHYp9is2Lkg2KjZgtmK2Kkg2KfZhNii2YrYqSDZiNiq2YHYs9mK2LHZh9inLiJ9LHsiaWQiOiIyOjE4MiIsImtpbmQiOiJwYXJ0aWFsIiwidmVyc2VzIjpbeyJpZCI6IjI6MTgyIiwic3VyYWgiOjIsInN1cmFoTmFtZSI6Itin2YTYqNmC2LHYqSIsImF5YWgiOjE4MiwidGV4dCI6Iu+7v9mB2Y7ZhdmO2YbZkiDYrtmO2KfZgdmOINmF2ZDZhtmSINmF2Y/ZiNi12Y0g2KzZjtmG2Y7ZgdmL2Kcg2KPZjtmI2ZIg2KXZkNir2ZLZhdmL2Kcg2YHZjtij2Y7YtdmS2YTZjtit2Y4g2KjZjtmK2ZLZhtmO2YfZj9mF2ZIg2YHZjtmE2Y7YpyDYpdmQ2KvZktmF2Y4g2LnZjtmE2Y7ZitmS2YfZkCDbmiDYpdmQ2YbZkdmOINin2YTZhNmR2Y7Zh9mOINi62Y7ZgdmP2YjYsdmMINix2Y7YrdmQ2YrZhdmMIn1dLCJub3RlIjoi2KfZhNin2YLYqtio2KfYsyDYrNiy2KEg2YXZhiDYp9mE2KLZitipLiDZhNinINmK2LnZhtmKINin2YTYp9iu2KrYtdin2LEg2YjYrdiv2Ycg2KPZhiDYp9mE2KfZgtiq2KjYp9izINiu2KfYt9im2Jsg2LHYp9is2Lkg2KjZgtmK2Kkg2KfZhNii2YrYqSDZiNiq2YHYs9mK2LHZh9inLiJ9LHsiaWQiOiIyOjE5MiIsImtpbmQiOiJwYXJ0aWFsIiwidmVyc2VzIjpbeyJpZCI6IjI6MTkyIiwic3VyYWgiOjIsInN1cmFoTmFtZSI6Itin2YTYqNmC2LHYqSIsImF5YWgiOjE5MiwidGV4dCI6Iu+7v9mB2Y7YpdmQ2YbZkCDYp9mG2ZLYqtmO2YfZjtmI2ZLYpyDZgdmO2KXZkNmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDYutmO2YHZj9mI2LHZjCDYsdmO2K3ZkNmK2YXZjCJ9XSwibm90ZSI6Itin2YTYp9mC2KrYqNin2LMg2KzYstihINmF2YYg2KfZhNii2YrYqS4g2YTYpyDZiti52YbZiiDYp9mE2KfYrtiq2LXYp9ixINmI2K3Yr9mHINij2YYg2KfZhNin2YLYqtio2KfYsyDYrtin2LfYptibINix2KfYrNi5INio2YLZitipINin2YTYotmK2Kkg2YjYqtmB2LPZitix2YfYpy4ifSx7ImlkIjoiMjoxOTkiLCJraW5kIjoicGFydGlhbCIsInZlcnNlcyI6W3siaWQiOiIyOjE5OSIsInN1cmFoIjoyLCJzdXJhaE5hbWUiOiLYp9mE2KjZgtix2KkiLCJheWFoIjoxOTksInRleHQiOiLvu7/Yq9mP2YXZkdmOINij2Y7ZgdmQ2YrYttmP2YjYpyDZhdmQ2YbZkiDYrdmO2YrZktir2Y8g2KPZjtmB2Y7Yp9i22Y4g2KfZhNmG2ZHZjtin2LPZjyDZiNmO2KfYs9mS2KrZjti62ZLZgdmQ2LHZj9mI2Kcg2KfZhNmE2ZHZjtmH2Y4g25og2KXZkNmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDYutmO2YHZj9mI2LHZjCDYsdmO2K3ZkNmK2YXZjCJ9XSwibm90ZSI6Itin2YTYp9mC2KrYqNin2LMg2KzYstihINmF2YYg2KfZhNii2YrYqS4g2YTYpyDZiti52YbZiiDYp9mE2KfYrtiq2LXYp9ixINmI2K3Yr9mHINij2YYg2KfZhNin2YLYqtio2KfYsyDYrtin2LfYptibINix2KfYrNi5INio2YLZitipINin2YTYotmK2Kkg2YjYqtmB2LPZitix2YfYpy4ifSx7ImlkIjoiMjoyMTgiLCJraW5kIjoicGFydGlhbCIsInZlcnNlcyI6W3siaWQiOiIyOjIxOCIsInN1cmFoIjoyLCJzdXJhaE5hbWUiOiLYp9mE2KjZgtix2KkiLCJheWFoIjoyMTgsInRleHQiOiLvu7/YpdmQ2YbZkdmOINin2YTZkdmO2LDZkNmK2YbZjiDYotmF2Y7ZhtmP2YjYpyDZiNmO2KfZhNmR2Y7YsNmQ2YrZhtmOINmH2Y7Yp9is2Y7YsdmP2YjYpyDZiNmO2KzZjtin2YfZjtiv2Y/ZiNinINmB2ZDZiiDYs9mO2KjZkNmK2YTZkCDYp9mE2YTZkdmO2YfZkCDYo9mP2YjZhNmO2bDYptmQ2YPZjiDZitmO2LHZktis2Y/ZiNmG2Y4g2LHZjtit2ZLZhdmO2KrZjiDYp9mE2YTZkdmO2YfZkCDbmiDZiNmO2KfZhNmE2ZHZjtmH2Y8g2LrZjtmB2Y/ZiNix2Ywg2LHZjtit2ZDZitmF2YwifV0sIm5vdGUiOiLYp9mE2KfZgtiq2KjYp9izINis2LLYoSDZhdmGINin2YTYotmK2KkuINmE2Kcg2YrYudmG2Yog2KfZhNin2K7Yqti12KfYsSDZiNit2K/ZhyDYo9mGINin2YTYp9mC2KrYqNin2LMg2K7Yp9i32KbYmyDYsdin2KzYuSDYqNmC2YrYqSDYp9mE2KLZitipINmI2KrZgdiz2YrYsdmH2KcuIn0seyJpZCI6IjI6MjI2Iiwia2luZCI6InBhcnRpYWwiLCJ2ZXJzZXMiOlt7ImlkIjoiMjoyMjYiLCJzdXJhaCI6Miwic3VyYWhOYW1lIjoi2KfZhNio2YLYsdipIiwiYXlhaCI6MjI2LCJ0ZXh0Ijoi77u/2YTZkNmE2ZHZjtiw2ZDZitmG2Y4g2YrZj9ik2ZLZhNmP2YjZhtmOINmF2ZDZhtmSINmG2ZDYs9mO2KfYptmQ2YfZkNmF2ZIg2KrZjtix2Y7YqNmR2Y/YtdmPINij2Y7YsdmS2KjZjti52Y7YqdmQINij2Y7YtNmS2YfZj9ix2Y0g25Yg2YHZjtil2ZDZhtmSINmB2Y7Yp9ih2Y/ZiNinINmB2Y7YpdmQ2YbZkdmOINin2YTZhNmR2Y7Zh9mOINi62Y7ZgdmP2YjYsdmMINix2Y7YrdmQ2YrZhdmMIn1dLCJub3RlIjoi2KfZhNin2YLYqtio2KfYsyDYrNiy2KEg2YXZhiDYp9mE2KLZitipLiDZhNinINmK2LnZhtmKINin2YTYp9iu2KrYtdin2LEg2YjYrdiv2Ycg2KPZhiDYp9mE2KfZgtiq2KjYp9izINiu2KfYt9im2Jsg2LHYp9is2Lkg2KjZgtmK2Kkg2KfZhNii2YrYqSDZiNiq2YHYs9mK2LHZh9inLiJ9LHsiaWQiOiIzOjMxIiwia2luZCI6InBhcnRpYWwiLCJ2ZXJzZXMiOlt7ImlkIjoiMzozMSIsInN1cmFoIjozLCJzdXJhaE5hbWUiOiLYotmEINi52YXYsdin2YYiLCJheWFoIjozMSwidGV4dCI6Iu+7v9mC2Y/ZhNmSINil2ZDZhtmSINmD2Y/ZhtmS2KrZj9mF2ZIg2KrZj9it2ZDYqNmR2Y/ZiNmG2Y4g2KfZhNmE2ZHZjtmH2Y4g2YHZjtin2KrZkdmO2KjZkNi52Y/ZiNmG2ZDZiiDZitmP2K3Zktio2ZDYqNmS2YPZj9mF2Y8g2KfZhNmE2ZHZjtmH2Y8g2YjZjtmK2Y7YutmS2YHZkNix2ZIg2YTZjtmD2Y/ZhdmSINiw2Y/ZhtmP2YjYqNmO2YPZj9mF2ZIg25cg2YjZjtin2YTZhNmR2Y7Zh9mPINi62Y7ZgdmP2YjYsdmMINix2Y7YrdmQ2YrZhdmMIn1dLCJub3RlIjoi2KfZhNin2YLYqtio2KfYsyDYrNiy2KEg2YXZhiDYp9mE2KLZitipLiDZhNinINmK2LnZhtmKINin2YTYp9iu2KrYtdin2LEg2YjYrdiv2Ycg2KPZhiDYp9mE2KfZgtiq2KjYp9izINiu2KfYt9im2Jsg2LHYp9is2Lkg2KjZgtmK2Kkg2KfZhNii2YrYqSDZiNiq2YHYs9mK2LHZh9inLiJ9LHsiaWQiOiIzOjg5Iiwia2luZCI6InBhcnRpYWwiLCJ2ZXJzZXMiOlt7ImlkIjoiMzo4OSIsInN1cmFoIjozLCJzdXJhaE5hbWUiOiLYotmEINi52YXYsdin2YYiLCJheWFoIjo4OSwidGV4dCI6Iu+7v9il2ZDZhNmR2Y7YpyDYp9mE2ZHZjtiw2ZDZitmG2Y4g2KrZjtin2KjZj9mI2Kcg2YXZkNmG2ZIg2KjZjti52ZLYr9mQINiw2Y7ZsNmE2ZDZg9mOINmI2Y7Yo9mO2LXZktmE2Y7YrdmP2YjYpyDZgdmO2KXZkNmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDYutmO2YHZj9mI2LHZjCDYsdmO2K3ZkNmK2YXZjCJ9XSwibm90ZSI6Itin2YTYp9mC2KrYqNin2LMg2KzYstihINmF2YYg2KfZhNii2YrYqS4g2YTYpyDZiti52YbZiiDYp9mE2KfYrtiq2LXYp9ixINmI2K3Yr9mHINij2YYg2KfZhNin2YLYqtio2KfYsyDYrtin2LfYptibINix2KfYrNi5INio2YLZitipINin2YTYotmK2Kkg2YjYqtmB2LPZitix2YfYpy4ifSx7ImlkIjoiMzoxMjkiLCJraW5kIjoicGFydGlhbCIsInZlcnNlcyI6W3siaWQiOiIzOjEyOSIsInN1cmFoIjozLCJzdXJhaE5hbWUiOiLYotmEINi52YXYsdin2YYiLCJheWFoIjoxMjksInRleHQiOiLvu7/ZiNmO2YTZkNmE2ZHZjtmH2ZAg2YXZjtinINmB2ZDZiiDYp9mE2LPZkdmO2YXZjtin2YjZjtin2KrZkCDZiNmO2YXZjtinINmB2ZDZiiDYp9mE2ZLYo9mO2LHZkti22ZAg25og2YrZjti62ZLZgdmQ2LHZjyDZhNmQ2YXZjtmG2ZIg2YrZjti02Y7Yp9ih2Y8g2YjZjtmK2Y/YudmO2LDZkdmQ2KjZjyDZhdmO2YbZkiDZitmO2LTZjtin2KHZjyDbmiDZiNmO2KfZhNmE2ZHZjtmH2Y8g2LrZjtmB2Y/ZiNix2Ywg2LHZjtit2ZDZitmF2YwifV0sIm5vdGUiOiLYp9mE2KfZgtiq2KjYp9izINis2LLYoSDZhdmGINin2YTYotmK2KkuINmE2Kcg2YrYudmG2Yog2KfZhNin2K7Yqti12KfYsSDZiNit2K/ZhyDYo9mGINin2YTYp9mC2KrYqNin2LMg2K7Yp9i32KbYmyDYsdin2KzYuSDYqNmC2YrYqSDYp9mE2KLZitipINmI2KrZgdiz2YrYsdmH2KcuIn0seyJpZCI6IjQ6MjUiLCJraW5kIjoicGFydGlhbCIsInZlcnNlcyI6W3siaWQiOiI0OjI1Iiwic3VyYWgiOjQsInN1cmFoTmFtZSI6Itin2YTZhtiz2KfYoSIsImF5YWgiOjI1LCJ0ZXh0Ijoi77u/2YjZjtmF2Y7ZhtmSINmE2Y7ZhdmSINmK2Y7Ys9mS2KrZjti32ZDYudmSINmF2ZDZhtmS2YPZj9mF2ZIg2LfZjtmI2ZLZhNmL2Kcg2KPZjtmG2ZIg2YrZjtmG2ZLZg9mQ2K3ZjiDYp9mE2ZLZhdmP2K3Zkti12Y7ZhtmO2KfYqtmQINin2YTZktmF2Y/YpNmS2YXZkNmG2Y7Yp9iq2ZAg2YHZjtmF2ZDZhtmSINmF2Y7YpyDZhdmO2YTZjtmD2Y7YqtmSINij2Y7ZitmS2YXZjtin2YbZj9mD2Y/ZhdmSINmF2ZDZhtmSINmB2Y7YqtmO2YrZjtin2KrZkNmD2Y/ZhdmPINin2YTZktmF2Y/YpNmS2YXZkNmG2Y7Yp9iq2ZAg25og2YjZjtin2YTZhNmR2Y7Zh9mPINij2Y7YudmS2YTZjtmF2Y8g2KjZkNil2ZDZitmF2Y7Yp9mG2ZDZg9mP2YXZkiDbmiDYqNmO2LnZkti22Y/Zg9mP2YXZkiDZhdmQ2YbZkiDYqNmO2LnZkti22Y0g25og2YHZjtin2YbZktmD2ZDYrdmP2YjZh9mP2YbZkdmOINio2ZDYpdmQ2LDZktmG2ZAg2KPZjtmH2ZLZhNmQ2YfZkNmG2ZHZjiDZiNmO2KLYqtmP2YjZh9mP2YbZkdmOINij2Y/YrNmP2YjYsdmO2YfZj9mG2ZHZjiDYqNmQ2KfZhNmS2YXZjti52ZLYsdmP2YjZgdmQINmF2Y/YrdmS2LXZjtmG2Y7Yp9iq2Y0g2LrZjtmK2ZLYsdmOINmF2Y/Ys9mO2KfZgdmQ2K3Zjtin2KrZjSDZiNmO2YTZjtinINmF2Y/YqtmR2Y7YrtmQ2LDZjtin2KrZkCDYo9mO2K7Zktiv2Y7Yp9mG2Y0g25og2YHZjtil2ZDYsNmO2Kcg2KPZj9it2ZLYtdmQ2YbZkdmOINmB2Y7YpdmQ2YbZkiDYo9mO2KrZjtmK2ZLZhtmOINio2ZDZgdmO2KfYrdmQ2LTZjtip2Y0g2YHZjti52Y7ZhNmO2YrZktmH2ZDZhtmR2Y4g2YbZkNi12ZLZgdmPINmF2Y7YpyDYudmO2YTZjtmJINin2YTZktmF2Y/YrdmS2LXZjtmG2Y7Yp9iq2ZAg2YXZkNmG2Y4g2KfZhNmS2LnZjtiw2Y7Yp9io2ZAg25og2LDZjtmw2YTZkNmD2Y4g2YTZkNmF2Y7ZhtmSINiu2Y7YtNmQ2YrZjiDYp9mE2ZLYudmO2YbZjtiq2Y4g2YXZkNmG2ZLZg9mP2YXZkiDbmiDZiNmO2KPZjtmG2ZIg2KrZjti12ZLYqNmQ2LHZj9mI2Kcg2K7ZjtmK2ZLYsdmMINmE2Y7Zg9mP2YXZkiDblyDZiNmO2KfZhNmE2ZHZjtmH2Y8g2LrZjtmB2Y/ZiNix2Ywg2LHZjtit2ZDZitmF2YwifV0sIm5vdGUiOiLYp9mE2KfZgtiq2KjYp9izINis2LLYoSDZhdmGINin2YTYotmK2KkuINmE2Kcg2YrYudmG2Yog2KfZhNin2K7Yqti12KfYsSDZiNit2K/ZhyDYo9mGINin2YTYp9mC2KrYqNin2LMg2K7Yp9i32KbYmyDYsdin2KzYuSDYqNmC2YrYqSDYp9mE2KLZitipINmI2KrZgdiz2YrYsdmH2KcuIn0seyJpZCI6IjU6MyIsImtpbmQiOiJwYXJ0aWFsIiwidmVyc2VzIjpbeyJpZCI6IjU6MyIsInN1cmFoIjo1LCJzdXJhaE5hbWUiOiLYp9mE2YXYp9im2K/YqSIsImF5YWgiOjMsInRleHQiOiLvu7/YrdmP2LHZkdmQ2YXZjtiq2ZIg2LnZjtmE2Y7ZitmS2YPZj9mF2Y8g2KfZhNmS2YXZjtmK2ZLYqtmO2KnZjyDZiNmO2KfZhNiv2ZHZjtmF2Y8g2YjZjtmE2Y7YrdmS2YXZjyDYp9mE2ZLYrtmQ2YbZktiy2ZDZitix2ZAg2YjZjtmF2Y7YpyDYo9mP2YfZkNmE2ZHZjiDZhNmQ2LrZjtmK2ZLYsdmQINin2YTZhNmR2Y7Zh9mQINio2ZDZh9mQINmI2Y7Yp9mE2ZLZhdmP2YbZktiu2Y7ZhtmQ2YLZjtip2Y8g2YjZjtin2YTZktmF2Y7ZiNmS2YLZj9mI2LDZjtip2Y8g2YjZjtin2YTZktmF2Y/YqtmO2LHZjtiv2ZHZkNmK2Y7YqdmPINmI2Y7Yp9mE2YbZkdmO2LfZkNmK2K3Zjtip2Y8g2YjZjtmF2Y7YpyDYo9mO2YPZjtmE2Y4g2KfZhNiz2ZHZjtio2Y/YudmPINil2ZDZhNmR2Y7YpyDZhdmO2Kcg2LDZjtmD2ZHZjtmK2ZLYqtmP2YXZkiDZiNmO2YXZjtinINiw2Y/YqNmQ2K3ZjiDYudmO2YTZjtmJINin2YTZhtmR2Y/YtdmP2KjZkCDZiNmO2KPZjtmG2ZIg2KrZjtiz2ZLYqtmO2YLZktiz2ZDZhdmP2YjYpyDYqNmQ2KfZhNmS2KPZjtiy2ZLZhNmO2KfZhdmQINuaINiw2Y7ZsNmE2ZDZg9mP2YXZkiDZgdmQ2LPZktmC2Ywg25cg2KfZhNmS2YrZjtmI2ZLZhdmOINmK2Y7YptmQ2LPZjiDYp9mE2ZHZjtiw2ZDZitmG2Y4g2YPZjtmB2Y7YsdmP2YjYpyDZhdmQ2YbZkiDYr9mQ2YrZhtmQ2YPZj9mF2ZIg2YHZjtmE2Y7YpyDYqtmO2K7Zkti02Y7ZiNmS2YfZj9mF2ZIg2YjZjtin2K7Zkti02Y7ZiNmS2YbZkCDbmiDYp9mE2ZLZitmO2YjZktmF2Y4g2KPZjtmD2ZLZhdmO2YTZktiq2Y8g2YTZjtmD2Y/ZhdmSINiv2ZDZitmG2Y7Zg9mP2YXZkiDZiNmO2KPZjtiq2ZLZhdmO2YXZktiq2Y8g2LnZjtmE2Y7ZitmS2YPZj9mF2ZIg2YbZkNi52ZLZhdmO2KrZkNmKINmI2Y7YsdmO2LbZkNmK2KrZjyDZhNmO2YPZj9mF2Y8g2KfZhNmS2KXZkNiz2ZLZhNmO2KfZhdmOINiv2ZDZitmG2YvYpyDbmiDZgdmO2YXZjtmG2ZAg2KfYttmS2LfZj9ix2ZHZjiDZgdmQ2Yog2YXZjtiu2ZLZhdmO2LXZjtip2Y0g2LrZjtmK2ZLYsdmOINmF2Y/YqtmO2KzZjtin2YbZkNmB2Y0g2YTZkNil2ZDYq9mS2YXZjSDbmSDZgdmO2KXZkNmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDYutmO2YHZj9mI2LHZjCDYsdmO2K3ZkNmK2YXZjCJ9XSwibm90ZSI6Itin2YTYp9mC2KrYqNin2LMg2KzYstihINmF2YYg2KfZhNii2YrYqS4g2YTYpyDZiti52YbZiiDYp9mE2KfYrtiq2LXYp9ixINmI2K3Yr9mHINij2YYg2KfZhNin2YLYqtio2KfYsyDYrtin2LfYptibINix2KfYrNi5INio2YLZitipINin2YTYotmK2Kkg2YjYqtmB2LPZitix2YfYpy4ifSx7ImlkIjoiNTozNCIsImtpbmQiOiJwYXJ0aWFsIiwidmVyc2VzIjpbeyJpZCI6IjU6MzQiLCJzdXJhaCI6NSwic3VyYWhOYW1lIjoi2KfZhNmF2KfYptiv2KkiLCJheWFoIjozNCwidGV4dCI6Iu+7v9il2ZDZhNmR2Y7YpyDYp9mE2ZHZjtiw2ZDZitmG2Y4g2KrZjtin2KjZj9mI2Kcg2YXZkNmG2ZIg2YLZjtio2ZLZhNmQINij2Y7ZhtmSINiq2Y7ZgtmS2K/ZkNix2Y/ZiNinINi52Y7ZhNmO2YrZktmH2ZDZhdmSINuWINmB2Y7Yp9i52ZLZhNmO2YXZj9mI2Kcg2KPZjtmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDYutmO2YHZj9mI2LHZjCDYsdmO2K3ZkNmK2YXZjCJ9XSwibm90ZSI6Itin2YTYp9mC2KrYqNin2LMg2KzYstihINmF2YYg2KfZhNii2YrYqS4g2YTYpyDZiti52YbZiiDYp9mE2KfYrtiq2LXYp9ixINmI2K3Yr9mHINij2YYg2KfZhNin2YLYqtio2KfYsyDYrtin2LfYptibINix2KfYrNi5INio2YLZitipINin2YTYotmK2Kkg2YjYqtmB2LPZitix2YfYpy4ifV0sImNhbmRpZGF0ZUNvdW50Ijo0Miwic2VsZWN0ZWQiOnsiaWQiOiI1OjM5Iiwia2luZCI6InBhcnRpYWwiLCJ2ZXJzZXMiOlt7ImlkIjoiNTozOSIsInN1cmFoIjo1LCJzdXJhaE5hbWUiOiLYp9mE2YXYp9im2K/YqSIsImF5YWgiOjM5LCJ0ZXh0Ijoi77u/2YHZjtmF2Y7ZhtmSINiq2Y7Yp9io2Y4g2YXZkNmG2ZIg2KjZjti52ZLYr9mQINi42Y/ZhNmS2YXZkNmH2ZAg2YjZjtij2Y7YtdmS2YTZjtit2Y4g2YHZjtil2ZDZhtmR2Y4g2KfZhNmE2ZHZjtmH2Y4g2YrZjtiq2Y/ZiNio2Y8g2LnZjtmE2Y7ZitmS2YfZkCDblyDYpdmQ2YbZkdmOINin2YTZhNmR2Y7Zh9mOINi62Y7ZgdmP2YjYsdmMINix2Y7YrdmQ2YrZhdmMIn1dLCJub3RlIjoi2KfZhNin2YLYqtio2KfYsyDYrNiy2KEg2YXZhiDYp9mE2KLZitipLiDZhNinINmK2LnZhtmKINin2YTYp9iu2KrYtdin2LEg2YjYrdiv2Ycg2KPZhiDYp9mE2KfZgtiq2KjYp9izINiu2KfYt9im2Jsg2LHYp9is2Lkg2KjZgtmK2Kkg2KfZhNii2YrYqSDZiNiq2YHYs9mK2LHZh9inLiJ9LCJjb250ZXh0IjpbeyJpZCI6IjU6MzgiLCJzdXJhaCI6NSwic3VyYWhOYW1lIjoi2KfZhNmF2KfYptiv2KkiLCJheWFoIjozOCwidGV4dCI6Iu+7v9mI2Y7Yp9mE2LPZkdmO2KfYsdmQ2YLZjyDZiNmO2KfZhNiz2ZHZjtin2LHZkNmC2Y7YqdmPINmB2Y7Yp9mC2ZLYt9mO2LnZj9mI2Kcg2KPZjtmK2ZLYr9mQ2YrZjtmH2Y/ZhdmO2Kcg2KzZjtiy2Y7Yp9ih2Ysg2KjZkNmF2Y7YpyDZg9mO2LPZjtio2Y7YpyDZhtmO2YPZjtin2YTZi9inINmF2ZDZhtmOINin2YTZhNmR2Y7Zh9mQINuXINmI2Y7Yp9mE2YTZkdmO2YfZjyDYudmO2LLZkNmK2LLZjCDYrdmO2YPZkNmK2YXZjCJ9LHsiaWQiOiI1OjM5Iiwic3VyYWgiOjUsInN1cmFoTmFtZSI6Itin2YTZhdin2KbYr9ipIiwiYXlhaCI6MzksInRleHQiOiLvu7/ZgdmO2YXZjtmG2ZIg2KrZjtin2KjZjiDZhdmQ2YbZkiDYqNmO2LnZktiv2ZAg2LjZj9mE2ZLZhdmQ2YfZkCDZiNmO2KPZjti12ZLZhNmO2K3ZjiDZgdmO2KXZkNmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDZitmO2KrZj9mI2KjZjyDYudmO2YTZjtmK2ZLZh9mQINuXINil2ZDZhtmR2Y4g2KfZhNmE2ZHZjtmH2Y4g2LrZjtmB2Y/ZiNix2Ywg2LHZjtit2ZDZitmF2YwifSx7ImlkIjoiNTo0MCIsInN1cmFoIjo1LCJzdXJhaE5hbWUiOiLYp9mE2YXYp9im2K/YqSIsImF5YWgiOjQwLCJ0ZXh0Ijoi77u/2KPZjtmE2Y7ZhdmSINiq2Y7YudmS2YTZjtmF2ZIg2KPZjtmG2ZHZjiDYp9mE2YTZkdmO2YfZjiDZhNmO2YfZjyDZhdmP2YTZktmD2Y8g2KfZhNiz2ZHZjtmF2Y7Yp9mI2Y7Yp9iq2ZAg2YjZjtin2YTZktij2Y7YsdmS2LbZkCDZitmP2LnZjtiw2ZHZkNio2Y8g2YXZjtmG2ZIg2YrZjti02Y7Yp9ih2Y8g2YjZjtmK2Y7YutmS2YHZkNix2Y8g2YTZkNmF2Y7ZhtmSINmK2Y7YtNmO2KfYodmPINuXINmI2Y7Yp9mE2YTZkdmO2YfZjyDYudmO2YTZjtmJ2bAg2YPZj9mE2ZHZkCDYtNmO2YrZktih2Y0g2YLZjtiv2ZDZitix2YwifV0sInRhZnNpciI6W3sidmVyc2VJZCI6IjU6MzkiLCJlbnRyaWVzIjpbeyJib29rSWQiOjI2OSwiYm9va05hbWUiOiLYqtmB2LPZitixINmF2KzYp9mH2K8iLCJhdXRob3IiOiLZhdis2KfZh9ivINio2YYg2KzYqNixIiwicGFydCI6IjEiLCJwYWdlIjozMDgsInRleHQiOiLYo9mG2KjYoyDYudmO2KjZktiv2Y8g2KfZhNix2ZHZjtit2ZLZhdmO2YbZkNiMINmC2Y7Yp9mE2Y46INir2YbYpyDYpdmQ2KjZktix2Y7Yp9mH2ZDZitmF2Y/YjCDZgtmO2KfZhNmOOiDZhtinINii2K/ZjtmF2Y/YjCDZgtmO2KfZhNmOOiDYq9mG2Kcg2YjZjtix2ZLZgtmO2KfYodmP2Iwg2LnZjtmG2ZAg2KfYqNmS2YbZkCDYo9mO2KjZkNmKINmG2Y7YrNmQ2YrYrdmN2Iwg2LnZjtmG2ZIg2YXZj9is2Y7Yp9mH2ZDYr9mN2Iwg77S/2YHZjtmF2Y7ZhtmSINiq2Y7Yp9io2Y4g2YXZkNmG2ZIg2KjZjti52ZLYr9mQINi42Y/ZhNmS2YXZkNmH2ZDvtL4gW9in2YTZhdin2KbYr9ipOiDZo9mpXdiMINmK2Y7ZgtmP2YjZhNmPOiDCq9in2YTZktit2Y7Yr9mR2Y8g2YPZjtmB2ZHZjtin2LHZjtip2Ywg2LnZjtmG2ZLZh9mPwrsiLCJ1cmwiOiJodHRwczovL3F1cmFucGVkaWEubmV0L2FwaS92MS9heWFoLzUvMzkvYm9vay8yNjkifV19XSwiZGlmZmVyZW5jZXMiOltdLCJzb3VyY2VWZXJzaW9uIjoiMjAyNi0xMC0wMSJ9"))
        let expected = try JSONDecoder().decode(ReviewResult.self, from: raw)
        XCTAssertEqual(expected.selected?.id, "5:39")
        XCTAssertEqual(expected.candidates.count, 12)
        XCTAssertEqual(expected.candidateCount, 42)
        XCTAssertFalse(expected.candidates.contains { $0.id == expected.selected?.id })
        let result = try await review(raw, quote: expected.quote, selection: expected.selected?.id).get()
        XCTAssertEqual(result, expected)
    }

    func testSelectedOriginalBytesMustMatchTheListedVerse() async throws {
        var changed = try json("01-partial")
        var selected = try XCTUnwrap(changed["selected"] as? [String: Any])
        var verses = try XCTUnwrap(selected["verses"] as? [[String: Any]])
        verses[0]["text"] = try XCTUnwrap(verses[0]["text"] as? String) + "\u{FEFF}"
        selected["verses"] = verses
        changed["selected"] = selected
        try await assertRejected(changed, quote: Self.partialQuote, .conflictingVerseContent, "المعرف نفسه لا يجيز اختلاف بايتات الآية")
    }

    func testContextOriginalBytesMustMatchTheSelectedVerse() async throws {
        var changed = try json("01-partial")
        var context = try XCTUnwrap(changed["context"] as? [[String: Any]])
        let index = try XCTUnwrap(context.firstIndex { ($0["id"] as? String) == "4:43" })
        context[index]["text"] = try XCTUnwrap(context[index]["text"] as? String) + "\u{FEFF}"
        changed["context"] = context
        try await assertRejected(changed, quote: Self.partialQuote, .conflictingVerseContent, "نسخة الآية في السياق لا تتغير")
    }

    func testSelectedKindMustMatchItsListedCandidate() async throws {
        var changed = try json("01-partial")
        var selected = try XCTUnwrap(changed["selected"] as? [String: Any])
        selected["kind"] = "full"
        changed["selected"] = selected
        try await assertRejected(changed, quote: Self.partialQuote, .selectedKindMismatch, "نوع المختار يطابق مرشحه")
    }


}
