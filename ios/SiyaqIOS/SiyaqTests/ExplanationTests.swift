import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Siyaq

/// /api/explain: فك العقد، شكل الطلب، الحالات الموثقة، الإلغاء، والاستجابات القديمة.
/// الخدمة الحية لم تُفعّل بمفتاح مزود؛ هذه الاختبارات بمضاعفات فقط ولا تدّعي فحص شرح حي.
enum ExplanationFixtures {
    /// نص اختباري للشرح المولد — ليس مادة علمية.
    static let generatedText = "نص شرح تجريبي لأغراض الاختبار فقط."

    /// دليل مبني من تفسير مجاهد في المثال الفعلي 01-partial دون تعديل نصه.
    static func evidence(from result: ReviewResult, entryIndex: Int = 0) throws -> Evidence {
        let group = try XCTUnwrap(result.tafsir.first)
        let entry = group.entries[entryIndex]
        return Evidence(
            id: "\(group.verseId):\(entry.bookId):\(entryIndex)",
            verseId: group.verseId,
            bookId: entry.bookId,
            bookName: entry.bookName,
            author: entry.author,
            part: entry.part,
            page: entry.page,
            text: entry.text,
            url: entry.url
        )
    }

    static func readyJSON(evidence: Evidence, excerpt: String, extra: String = "") throws -> Data {
        let evidenceData = try JSONEncoder().encode(evidence)
        let evidenceJSON = String(decoding: evidenceData, as: UTF8.self)
        let excerptJSON = String(decoding: try JSONEncoder().encode(excerpt), as: UTF8.self)
        let text = String(decoding: try JSONEncoder().encode(generatedText), as: UTF8.self)
        let body = """
        {"status":"ready","claims":[{"text":\(text),"excerpt":\(excerptJSON),"evidence":\(evidenceJSON)}],
         "sourceVersion":"2026-10-01","model":"test-model","notice":"إشعار اختباري"\(extra)}
        """
        return Data(body.utf8)
    }

    static let abstainedJSON = Data("""
    {"status":"abstained","claims":[],"sourceVersion":"2026-10-01","notice":"إشعار اختباري","reason":"الأدلة غير كافية"}
    """.utf8)

    static let abstainedMinimalJSON = Data("""
    {"status":"abstained","claims":[],"sourceVersion":"2026-10-01","notice":"إشعار اختباري"}
    """.utf8)
}

final class ExplanationModelTests: XCTestCase {

    func testReadyDecodesWithVerbatimEvidence() throws {
        let result = try Samples.result("01-partial")
        let evidence = try ExplanationFixtures.evidence(from: result)
        let excerpt = String(evidence.text.prefix(40))
        let data = try ExplanationFixtures.readyJSON(evidence: evidence, excerpt: excerpt, extra: #","futureField":1"#)

        let explanation = try JSONDecoder().decode(Explanation.self, from: data)
        XCTAssertEqual(explanation.status, .ready)
        XCTAssertEqual(explanation.model, "test-model")
        XCTAssertNil(explanation.reason)
        let claim = try XCTUnwrap(explanation.claims.first)
        XCTAssertEqual(claim.excerpt, excerpt)
        XCTAssertEqual(claim.evidence.bookId, 269)
        XCTAssertEqual(claim.evidence.bookName, "تفسير مجاهد")
        XCTAssertEqual(claim.evidence.page, 276)
        XCTAssertEqual(Array(claim.evidence.text.unicodeScalars), Array(result.tafsir[0].entries[0].text.unicodeScalars))
        XCTAssertNoThrow(try explanation.verified(for: try Samples.result("01-partial")))
    }

    func testAbstainedWithAndWithoutReason() throws {
        let a = try JSONDecoder().decode(Explanation.self, from: ExplanationFixtures.abstainedJSON)
        XCTAssertEqual(a.status, .abstained)
        XCTAssertTrue(a.claims.isEmpty)
        XCTAssertEqual(a.reason, "الأدلة غير كافية")
        XCTAssertNil(a.model)

        let b = try JSONDecoder().decode(Explanation.self, from: ExplanationFixtures.abstainedMinimalJSON)
        XCTAssertNil(b.reason)
        XCTAssertEqual(try b.verified(for: try Samples.result("01-partial")).status, .abstained)
    }

    func testEvidenceAcceptsBookAliasAndNullPage() throws {
        let json = """
        {"id":"4:43:269:0","verseId":"4:43","bookId":269,"book":"كتاب","author":"م","part":"1","page":null,"text":"نص","url":"https://quranpedia.net/"}
        """
        let evidence = try JSONDecoder().decode(Evidence.self, from: Data(json.utf8))
        XCTAssertEqual(evidence.bookName, "كتاب")
        XCTAssertNil(evidence.page)
    }

    func testClientDropsUnverifiableClaims() throws {
        let result = try Samples.result("01-partial")
        let evidence = try ExplanationFixtures.evidence(from: result)

        // اقتباس غير موجود حرفيًا في نص الدليل.
        let fake = try JSONDecoder().decode(
            Explanation.self,
            from: ExplanationFixtures.readyJSON(evidence: evidence, excerpt: "عبارة غير موجودة في الدليل إطلاقًا")
        )
        XCTAssertThrowsError(try fake.verified(for: result)) {
            XCTAssertEqual($0 as? ExplanationRejection, .excerptNotVerbatim)
        }

        // دليل لآية خارج الموضع المختار.
        let real = try JSONDecoder().decode(
            Explanation.self,
            from: ExplanationFixtures.readyJSON(evidence: evidence, excerpt: String(evidence.text.prefix(40)))
        )
        XCTAssertThrowsError(try real.verified(for: try Samples.result("05-full-no-tafsir"))) {
            XCTAssertEqual($0 as? ExplanationRejection, .evidenceOutsideSelection)
        }
    }

    func testReadyWithoutClaimsAndUnknownStatusAreRejected() throws {
        let emptyReady = Data(#"{"status":"ready","claims":[],"sourceVersion":"v","notice":"n"}"#.utf8)
        let result = try Samples.result("01-partial")
        XCTAssertThrowsError(try JSONDecoder().decode(Explanation.self, from: emptyReady).verified(for: result)) {
            XCTAssertEqual($0 as? ExplanationRejection, .contradictory)
        }
        let unknown = Data(#"{"status":"partial","claims":[],"sourceVersion":"v","notice":"n"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Explanation.self, from: unknown).verified(for: result)) {
            XCTAssertEqual($0 as? ExplanationRejection, .unknownStatus)
        }
    }

    func testEligibility() throws {
        let partial = try Samples.result("01-partial")
        XCTAssertTrue(ExplanationEligibility.isEligible(ReviewOutcome(result: partial, origin: .live)))
        XCTAssertFalse(ExplanationEligibility.isEligible(ReviewOutcome(result: partial, origin: .preview)))
        XCTAssertTrue(ExplanationEligibility.isEligible(ReviewOutcome(result: try Samples.result("05-full-no-tafsir"), origin: .live)))
        for name in ["02-choices", "03-possible", "04-not-found", "06-selected-possible"] {
            XCTAssertFalse(ExplanationEligibility.isEligible(ReviewOutcome(result: try Samples.result(name), origin: .live)), name)
        }
    }

    func testExplainEndpointFollowsServiceRules() throws {
        XCTAssertEqual(
            try ServiceEndpoint.explainURL(from: "https://service.invalid/base/", allowLocalHTTP: false).absoluteString,
            "https://service.invalid/base/api/explain"
        )
        XCTAssertEqual(
            try ServiceEndpoint.explainURL(from: "http://localhost:3000", allowLocalHTTP: true).absoluteString,
            "http://localhost:3000/api/explain"
        )
        XCTAssertThrowsError(try ServiceEndpoint.explainURL(from: "http://localhost:3000", allowLocalHTTP: false))
        XCTAssertThrowsError(try ServiceEndpoint.explainURL(from: "", allowLocalHTTP: true)) {
            XCTAssertEqual($0 as? ReviewError, .notConfigured)
        }
    }

    func testRecordedSamplesNeverGetAnExplanation() throws {
        XCTAssertThrowsError(try ServiceConfiguration(source: .recordedSamples).makeExplanationService()) {
            XCTAssertEqual($0 as? ReviewError, .explanationNotEligible)
        }
        XCTAssertTrue(try ServiceConfiguration(source: .live(baseURL: "https://service.invalid")).makeExplanationService()
                      is LiveExplanationService)
        XCTAssertThrowsError(try ServiceConfiguration(source: .live(baseURL: "")).makeExplanationService()) {
            XCTAssertEqual($0 as? ReviewError, .notConfigured)
        }
    }
}

/// عميل URLSession لـ /api/explain.
final class ExplanationServiceTests: XCTestCase {
    private let endpoint = URL(string: "https://service.invalid/api/explain")!

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func service() -> LiveExplanationService {
        LiveExplanationService(endpoint: endpoint, session: StubURLProtocol.session())
    }

    func testRequestShapeIsSameAsReviewAndCarriesNoTafsir() async throws {
        let result = try Samples.result("01-partial")
        let evidence = try ExplanationFixtures.evidence(from: result)
        let body = try ExplanationFixtures.readyJSON(evidence: evidence, excerpt: String(evidence.text.prefix(40)))
        StubURLProtocol.handler = { _ in .init(status: 200, body: body) }

        let explanation = try await service().explain(quote: "لا تقربوا الصلاة", selection: "4:43")
        XCTAssertEqual(explanation.status, .ready)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["quote", "selection"], "لا يرسل العميل تفسيرًا أو مراجع")
        XCTAssertEqual(json["quote"] as? String, "لا تقربوا الصلاة")
        XCTAssertEqual(json["selection"] as? String, "4:43")
    }

    func testAbstained() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: ExplanationFixtures.abstainedJSON) }
        let explanation = try await service().explain(quote: "لا تقربوا الصلاة", selection: nil)
        XCTAssertEqual(explanation.status, .abstained)
        XCTAssertTrue(explanation.claims.isEmpty)
    }

    func testAINotConfigured() async throws {
        StubURLProtocol.handler = { _ in
            .init(status: 503, body: Data(#"{"error":"الشرح غير مفعّل","code":"AI_NOT_CONFIGURED"}"#.utf8))
        }
        do {
            _ = try await service().explain(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .aiNotConfigured)
            XCTAssertFalse(error.canRetry)
        }
    }

    func testOther503IsGenericServiceError() async throws {
        StubURLProtocol.handler = { _ in .init(status: 503, body: Data(#"{"error":"تعذر"}"#.utf8)) }
        do {
            _ = try await service().explain(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .http(status: 503, message: "تعذر"))
        }
    }

    func testRateLimitedWithRetryAfter() async throws {
        StubURLProtocol.handler = { _ in
            .init(status: 429, body: Data(#"{"error":"حد"}"#.utf8), headers: ["Retry-After": "30"])
        }
        do {
            _ = try await service().explain(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 30))
            XCTAssertTrue(error.canRetry, "إعادة يدوية مسموحة")
            XCTAssertTrue(error.message.contains("٣٠"))
        }
    }

    func testRateLimitedWithoutRetryAfter() async throws {
        StubURLProtocol.handler = { _ in .init(status: 429, body: Data()) }
        do {
            _ = try await service().explain(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: nil))
        }
    }

    func testMalformedBody() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data(#"{"claims":"x"}"#.utf8)) }
        do {
            _ = try await service().explain(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testTimeoutIsFiftySeconds() throws {
        let request = try service().makeRequest(quote: "أ ب", selection: nil)
        XCTAssertEqual(request.timeoutInterval, 50)
    }
}

/// مضاعف قابل للتحكم بالتوقيت لخدمة الشرح.
final class ScriptedExplanationService: ExplanationServicing, @unchecked Sendable {
    typealias Step = ScriptStep<Explanation>
    private let script: StepScript<Explanation>
    var calls: [(quote: String, selection: String?)] { script.calls }

    init(_ steps: [Step]) { script = StepScript(steps) }

    func explain(quote: String, selection: String?) async throws -> Explanation {
        try await script.run(quote: quote, selection: selection)
    }
}

/// المتحكم: الطلب اليدوي، الرفض المحلي، الإلغاء، الاستجابات القديمة، وعدم إعادة المحاولة تلقائيًا.
@MainActor
final class ExplanationControllerTests: XCTestCase {

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func readyExplanation(_ result: ReviewResult, marker: String) throws -> Explanation {
        let evidence = try ExplanationFixtures.evidence(from: result)
        let excerpt = String(evidence.text.prefix(40))
        return Explanation(
            status: .ready,
            claims: [ExplanationClaim(text: marker, excerpt: excerpt, evidence: evidence)],
            sourceVersion: "2026-10-01",
            model: nil,
            notice: "إشعار اختباري",
            reason: nil
        )
    }

    func testStartsIdleAndNeverRequestsAutomatically() async throws {
        let controller = ExplanationController()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.requestCount, 0)
    }

    func testIneligibleOutcomesNeverHitTheService() async throws {
        let service = ScriptedExplanationService([])
        let controller = ExplanationController()
        for (name, origin) in [("03-possible", ResultOrigin.live), ("02-choices", .live), ("06-selected-possible", .live), ("01-partial", .preview)] {
            controller.request(for: ReviewOutcome(result: try Samples.result(name), origin: origin), quote: "أ ب", selection: nil, service: service)
            XCTAssertEqual(controller.state, .failed(.explanationNotEligible), name)
        }
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertEqual(controller.requestCount, 0)
    }

    func testReadyAndAbstainedStates() async throws {
        let result = try Samples.result("01-partial")
        let outcome = ReviewOutcome(result: result, origin: .live)
        let abstained = try JSONDecoder().decode(Explanation.self, from: ExplanationFixtures.abstainedJSON)
        let service = ScriptedExplanationService([
            .init(delay: .zero, result: .success(try readyExplanation(result, marker: "أ"))),
            .init(delay: .zero, result: .success(abstained)),
        ])
        let controller = ExplanationController()

        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        XCTAssertEqual(controller.state, .loading)
        await waitUntil { controller.state != .loading }
        guard case .ready(let explanation) = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(explanation.claims.first?.text, "أ")

        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        await waitUntil { controller.state != .loading }
        guard case .abstained = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(service.calls.map(\.selection), ["4:43", "4:43"])
    }

    func testNewerRequestWinsOverSlowOlderResponse() async throws {
        let result = try Samples.result("01-partial")
        let outcome = ReviewOutcome(result: result, origin: .live)
        let service = ScriptedExplanationService([
            .init(delay: .milliseconds(500), result: .success(try readyExplanation(result, marker: "قديم")), selection: .some(nil)),
            .init(delay: .milliseconds(30), result: .success(try readyExplanation(result, marker: "جديد")), selection: "4:43"),
        ])
        let controller = ExplanationController()
        // طلبان لمفتاحين مختلفين (selection مختلف): الأحدث يلغي الأقدم.
        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: nil, service: service)
        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)

        await waitUntil { controller.state != .loading }
        try await Task.sleep(for: .milliseconds(700))
        guard case .ready(let explanation) = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(explanation.claims.first?.text, "جديد")
    }

    func testCancelIgnoresLateResponse() async throws {
        let result = try Samples.result("01-partial")
        let service = ScriptedExplanationService([
            .init(delay: .milliseconds(300), result: .success(try readyExplanation(result, marker: "متأخر"))),
        ])
        let controller = ExplanationController()
        controller.request(for: ReviewOutcome(result: result, origin: .live), quote: "لا تقربوا الصلاة", selection: nil, service: service)
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.state, .idle)
    }

    func testErrorsAreShownAndNotRetriedAutomatically() async throws {
        let result = try Samples.result("01-partial")
        let outcome = ReviewOutcome(result: result, origin: .live)
        for error in [ReviewError.aiNotConfigured, .rateLimited(retryAfterSeconds: 20), .offline, .timedOut] {
            let service = ScriptedExplanationService([.init(delay: .zero, result: .failure(error))])
            let controller = ExplanationController()
            controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: nil, service: service)
            await waitUntil { controller.state != .loading }
            XCTAssertEqual(controller.state, .failed(error))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(service.calls.count, 1, "لا إعادة محاولة تلقائية")
            XCTAssertEqual(controller.requestCount, 1)
        }
    }

    func testUnverifiableReadyBecomesInvalidResponse() async throws {
        let result = try Samples.result("01-partial")
        let evidence = try ExplanationFixtures.evidence(from: result)
        let bad = Explanation(
            status: .ready,
            claims: [ExplanationClaim(text: "س", excerpt: "اقتباس لا يوجد في الدليل", evidence: evidence)],
            sourceVersion: "2026-10-01", model: nil, notice: "إشعار اختباري", reason: nil
        )
        let service = ScriptedExplanationService([.init(delay: .zero, result: .success(bad))])
        let controller = ExplanationController()
        controller.request(for: ReviewOutcome(result: result, origin: .live), quote: "لا تقربوا الصلاة", selection: nil, service: service)
        await waitUntil { controller.state != .loading }
        XCTAssertEqual(controller.state, .failed(.invalidResponse))
    }

    func testResetClearsState() async throws {
        let controller = ExplanationController()
        controller.showFailure(.aiNotConfigured)
        XCTAssertEqual(controller.state, .failed(.aiNotConfigured))
        controller.reset()
        XCTAssertEqual(controller.state, .idle)
    }
}
