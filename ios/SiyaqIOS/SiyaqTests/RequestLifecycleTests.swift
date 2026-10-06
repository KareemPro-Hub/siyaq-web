import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Siyaq

/// المرحلة ١١: متانة دورة الطلب بمضاعفات معزولة (لا شبكة ولا مزود ذكاء اصطناعي).
@MainActor
final class ExplanationLifecycleTests: XCTestCase {

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func ready(_ result: ReviewResult, marker: String) throws -> Explanation {
        let evidence = try ExplanationFixtures.evidence(from: result)
        return Explanation(status: .ready,
                           claims: [ExplanationClaim(text: marker, excerpt: String(evidence.text.prefix(40)), evidence: evidence)],
                           sourceVersion: result.sourceVersion, model: nil, notice: "إشعار اختباري", reason: nil)
    }

    /// نقرات متتالية على الزر نفسه أثناء الانتظار = طلب واحد فقط.
    func testRepeatedTapsSendOneRequest() async throws {
        let result = try Samples.result("01-partial")
        let service = ScriptedExplanationService([.init(delay: .milliseconds(200), result: .success(try ready(result, marker: "أ")))])
        let controller = ExplanationController()
        let outcome = ReviewOutcome(result: result, origin: .live)
        for _ in 0..<5 {
            controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        }
        await waitUntil { controller.state != .loading }
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertEqual(controller.requestCount, 1)
        guard case .ready = controller.state else { return XCTFail("\(controller.state)") }
    }

    /// تغيّر الموضع أثناء الطلب: الاستجابة القديمة لا تظهر مع الموضع الجديد.
    func testStaleResponseNeverAppearsWithNewPosition() async throws {
        let partial = try Samples.result("01-partial")
        let full = try Samples.result("05-full-no-tafsir")
        let abstainedForFull = Explanation(status: .abstained, claims: [], sourceVersion: full.sourceVersion,
                                           model: nil, notice: "إشعار اختباري", reason: "لا أدلة")
        let service = ScriptedExplanationService([
            .init(delay: .milliseconds(400), result: .success(try ready(partial, marker: "قديم")), selection: "4:43"),
            .init(delay: .milliseconds(20), result: .success(abstainedForFull), selection: "112:1"),
        ])
        let controller = ExplanationController()
        controller.request(for: ReviewOutcome(result: partial, origin: .live), quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        // الشاشة تعيد الضبط عند تغير مفتاح السياق، ثم يطلب المستخدم للموضع الجديد.
        controller.reset()
        controller.request(for: ReviewOutcome(result: full, origin: .live), quote: "قل هو الله أحد", selection: "112:1", service: service)

        await waitUntil { controller.state != .loading }
        try await Task.sleep(for: .milliseconds(600))
        guard case .abstained(let shown) = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(shown.reason, "لا أدلة")
        // الطلب القديم قد يُلغى قبل وصوله للخدمة أو بعده؛ المهم أن الجديد أُرسل ولم يظهر القديم.
        XCTAssertTrue(Set(service.calls.compactMap(\.selection)).isSubset(of: ["4:43", "112:1"]))
        XCTAssertTrue(service.calls.contains { $0.selection == "112:1" })
    }

    /// حتى لو وصلت استجابة صحيحة الشكل لموضع آخر إلى المتحكم، تُرفض لأنها لا تطابق النتيجة المعروضة.
    func testExplanationForAnotherPositionIsRejected() async throws {
        let partial = try Samples.result("01-partial")
        let full = try Samples.result("05-full-no-tafsir")
        let service = ScriptedExplanationService([.init(delay: .zero, result: .success(try ready(partial, marker: "س")))])
        let controller = ExplanationController()
        controller.request(for: ReviewOutcome(result: full, origin: .live), quote: "قل هو الله أحد", selection: "112:1", service: service)
        await waitUntil { controller.state != .loading }
        XCTAssertEqual(controller.state, .failed(.invalidResponse))
    }

    /// الخروج ثم العودة: الإلغاء لا يترك حالة انتظار، وطلب جديد يكتمل.
    func testLeaveAndReturnThenRequestAgain() async throws {
        let result = try Samples.result("01-partial")
        // خطوة واحدة فقط: الطلب الأول أُلغي قبل وصوله، فلو استهلكها لما ظهر «ثان».
        let service = ScriptedExplanationService([
            .init(delay: .zero, result: .success(try ready(result, marker: "ثان"))),
        ])
        let controller = ExplanationController()
        let outcome = ReviewOutcome(result: result, origin: .live)
        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        controller.cancel() // onDisappear
        XCTAssertEqual(controller.state, .idle)
        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        await waitUntil { controller.state != .loading }
        try await Task.sleep(for: .milliseconds(100))
        guard case .ready(let shown) = controller.state else { return XCTFail("\(controller.state)") }
        XCTAssertEqual(shown.claims.first?.text, "ثان")
        XCTAssertEqual(controller.requestCount, 2)
    }

    /// لا رسالة نجاح كاذبة: الفشل يبقى فشلًا، ولا شيء يتحول إلى ready دون تحقق.
    func testNoFalseSuccess() async throws {
        let result = try Samples.result("01-partial")
        let outcome = ReviewOutcome(result: result, origin: .live)
        var wrongVersion = try ready(result, marker: "س")
        wrongVersion = Explanation(status: .ready, claims: wrongVersion.claims, sourceVersion: "2026-10-09",
                                   model: nil, notice: "إشعار اختباري", reason: nil)
        let cases: [(Result<Explanation, ReviewError>, ExplanationState)] = [
            (.success(wrongVersion), .failed(.explanationVersionMismatch)),
            (.failure(.timedOut), .failed(.timedOut)),
            (.failure(.offline), .failed(.offline)),
            (.failure(.http(status: 500, message: nil)), .failed(.http(status: 500, message: nil))),
        ]
        for (response, expected) in cases {
            let controller = ExplanationController()
            controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43",
                               service: ScriptedExplanationService([.init(delay: .zero, result: response)]))
            await waitUntil { controller.state != .loading }
            XCTAssertEqual(controller.state, expected)
        }
    }

    /// الشرح لا يُحفظ ولا يدخل نص المشاركة.
    func testExplanationIsNeitherSavedNorShared() async throws {
        let result = try Samples.result("01-partial")
        let marker = "علامة-اختبار-الشرح-٧٣٩"
        let service = ScriptedExplanationService([.init(delay: .zero, result: .success(try ready(result, marker: marker)))])
        let controller = ExplanationController()
        let outcome = ReviewOutcome(result: result, origin: .live)
        controller.request(for: outcome, quote: "لا تقربوا الصلاة", selection: "4:43", service: service)
        await waitUntil { controller.state != .loading }
        guard case .ready = controller.state else { return XCTFail("\(controller.state)") }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SiyaqNoSave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedResultsStore(directory: directory)
        store.save(outcome)
        let onDisk = String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self)
        XCTAssertFalse(onDisk.contains(marker))
        XCTAssertFalse(onDisk.contains("\"claims\""))
        XCTAssertFalse(onDisk.contains("إشعار اختباري"))

        let share = ShareText.make(result: result, candidate: try XCTUnwrap(result.selected))
        XCTAssertFalse(share.contains(marker))
        XCTAssertFalse(share.contains("شرح"))
    }
}

/// دورة طلب المراجعة واختيار الموضع.
@MainActor
final class ReviewLifecycleTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// اختيار موضع ثم آخر بسرعة: تظهر نتيجة الأخير فقط، والقديمة المتأخرة لا تستبدلها.
    func testChangingSelectionDuringRequestShowsOnlyLatest() async throws {
        let choices = try Samples.result("02-choices")
        let slowOld = try Samples.result("01-partial")         // يمثّل استجابة متأخرة لموضع سابق
        let fastNew = try Samples.result("05-full-no-tafsir")  // يمثّل استجابة الموضع الأحدث
        let service = ScriptedService([
            .init(delay: .zero, result: .success(choices), selection: .some(nil)),
            .init(delay: .milliseconds(400), result: .success(slowOld), selection: "2:173"),
            .init(delay: .milliseconds(20), result: .success(fastNew), selection: "2:182"),
        ])
        let session = ReviewSession()
        session.start(quote: "غفور رحيم", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }

        session.select(candidateID: "2:173")
        session.cancelSelection()          // الرجوع من الشاشة
        session.select(candidateID: "2:182")

        await waitUntil { session.selection.outcome != nil }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(session.selectedCandidateID, "2:182")
        XCTAssertEqual(session.selection.outcome?.result.selected?.id, "112:1", "الأحدث فقط")
        XCTAssertEqual(service.calls.first?.selection, .some(nil))
        XCTAssertTrue(Set(service.calls.compactMap(\.selection)).isSubset(of: ["2:173", "2:182"]))
        XCTAssertTrue(service.calls.contains { $0.selection == "2:182" })
    }

    /// اختيار موضعين متتاليين دون رجوع (نقر سريع): الأحدث يلغي الأقدم أيضًا.
    func testRapidReselectWithoutBackAlsoKeepsLatest() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("02-choices")), selection: .some(nil)),
            .init(delay: .milliseconds(400), result: .success(try Samples.result("01-partial")), selection: "2:173"),
            .init(delay: .milliseconds(20), result: .success(try Samples.result("05-full-no-tafsir")), selection: "2:182"),
        ])
        let session = ReviewSession()
        session.start(quote: "غفور رحيم", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }
        session.select(candidateID: "2:173")
        session.select(candidateID: "2:182")
        await waitUntil { session.selection.outcome != nil }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(session.selection.outcome?.result.selected?.id, "112:1")
    }

    /// اقتباس جديد أثناء انتظار موضع: يُلغى الموضع ولا تظهر نتيجته لاحقًا.
    func testNewQuoteCancelsPendingSelection() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("02-choices")), quote: "غفور رحيم", selection: .some(nil)),
            .init(delay: .milliseconds(300), result: .success(try Samples.result("01-partial")), selection: "2:173"),
            .init(delay: .zero, result: .success(try Samples.result("05-full-no-tafsir")), quote: "قل هو الله أحد", selection: .some(nil)),
        ])
        let session = ReviewSession()
        let choice = ServiceChoice(service: service, origin: .live)
        session.start(quote: "غفور رحيم", using: choice)
        await waitUntil { session.primary.outcome != nil }
        session.select(candidateID: "2:173")
        session.start(quote: "قل هو الله أحد", using: choice)
        await waitUntil { session.primary.outcome?.result.quote == "قل هو الله أحد" }
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(session.selection, .idle)
        XCTAssertNil(session.selectedCandidateID)
    }
}

/// أخطاء HTTP والشبكة لعميلي المراجعة والشرح.
final class HTTPAndNetworkErrorTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private let reviewURL = URL(string: "https://service.invalid/api/review")!
    private let explainURL = URL(string: "https://service.invalid/api/explain")!

    private func reviewError(_ response: StubURLProtocol.Response) async -> ReviewError? {
        StubURLProtocol.handler = { _ in response }
        do {
            _ = try await LiveReviewService(endpoint: reviewURL, session: StubURLProtocol.session()).review(quote: "أ ب", selection: nil)
            return nil
        } catch { return error as? ReviewError }
    }

    private func explainError(_ response: StubURLProtocol.Response) async -> ReviewError? {
        StubURLProtocol.handler = { _ in response }
        do {
            _ = try await LiveExplanationService(endpoint: explainURL, session: StubURLProtocol.session()).explain(quote: "أ ب", selection: "4:43")
            return nil
        } catch { return error as? ReviewError }
    }

    func testHTTPStatusesMapToHonestErrors() async {
        let body = Data(#"{"error":"رسالة الخادم"}"#.utf8)
        for status in [400, 413, 415, 500, 503] {
            let review = await reviewError(.init(status: status, body: body))
            XCTAssertEqual(review, .http(status: status, message: "رسالة الخادم"), "review \(status)")
            let explain = await explainError(.init(status: status, body: body))
            XCTAssertEqual(explain, .http(status: status, message: "رسالة الخادم"), "explain \(status)")
        }
        // بلا رسالة: نص عربي افتراضي لكل رمز.
        for status in [413, 415] {
            let error = await reviewError(.init(status: status, body: Data()))
            XCTAssertEqual(error, .http(status: status, message: nil))
            XCTAssertFalse(error?.message.isEmpty ?? true)
        }
    }

    func testTimeoutAndConnectionLoss() async {
        let cases: [(URLError.Code, ReviewError)] = [
            (.timedOut, .timedOut),
            (.networkConnectionLost, .offline),
            (.notConnectedToInternet, .offline),
            (.cannotConnectToHost, .unreachable),
            (.secureConnectionFailed, .secureConnectionFailed),
        ]
        for (code, expected) in cases {
            let review = await reviewError(.init(status: 0, body: Data(), error: URLError(code)))
            XCTAssertEqual(review, expected, "review \(code)")
            let explain = await explainError(.init(status: 0, body: Data(), error: URLError(code)))
            XCTAssertEqual(explain, expected, "explain \(code)")
        }
    }

    /// استجابة 2xx غير 200 لا تُفك كنتيجة.
    func testNon200SuccessIsNotTreatedAsResult() async throws {
        let body = try Samples.data("01-partial")
        let error = await reviewError(.init(status: 204, body: body))
        XCTAssertEqual(error, .http(status: 204, message: nil))
    }
}

/// نقرات مكررة وإعلانات النجاح.
@MainActor
final class RepeatedTapTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// «ابدأ المراجعة» مرتين للاقتباس نفسه أثناء الانتظار: طلب واحد يكتمل.
    func testDoubleStartSendsOneReview() async throws {
        let service = ScriptedService([
            .init(delay: .milliseconds(150), result: .success(try Samples.result("05-full-no-tafsir"))),
            .init(delay: .zero, result: .success(try Samples.result("05-full-no-tafsir"))),
        ])
        let session = ReviewSession()
        let choice = ServiceChoice(service: service, origin: .live)
        session.start(quote: "قل هو الله أحد", using: choice)
        session.start(quote: "قل هو الله أحد", using: choice)
        await waitUntil { session.primary.outcome != nil }
        XCTAssertEqual(service.calls.count, 1)
        // بعد اكتمال الطلب، إعادة المراجعة نفسها مسموحة.
        session.start(quote: "قل هو الله أحد", using: choice)
        await waitUntil { service.calls.count == 2 && session.primary.outcome != nil }
        XCTAssertEqual(service.calls.count, 2)
    }

    /// النقر على الموضع نفسه مرتين أثناء الانتظار: طلب واحد.
    func testDoubleSelectSendsOneRequest() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("02-choices"))),
            .init(delay: .milliseconds(150), result: .success(try Samples.result("01-partial"))),
        ])
        let session = ReviewSession()
        session.start(quote: "غفور رحيم", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }
        session.select(candidateID: "2:173")
        session.select(candidateID: "2:173")
        await waitUntil { session.selection.outcome != nil }
        XCTAssertEqual(service.calls.map(\.selection), [nil, "2:173"])
    }

    /// شاشة الموضع تُدفع مرة واحدة فقط مهما تكرر النقر.
    func testSelectionScreenIsPushedOnce() async {
        var path: [ReviewRoute] = [.review]
        path = ReviewRoute.pushingSelection("2:173", onto: path)
        path = ReviewRoute.pushingSelection("2:173", onto: path)
        path = ReviewRoute.pushingSelection("2:182", onto: path)
        XCTAssertEqual(path, [.review, .selection("2:173")])
    }

    /// إزالة من محفوظات للقراءة فقط تعيد false؛ الواجهة لا تعلن «أُزيلت».
    func testRemoveReportsFailureWhenReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SiyaqRO-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try Samples.result("01-partial")
        let entry = String(decoding: try SavedResultsStore.encoder.encode(
            SavedEntry(id: UUID(), savedAt: Date(timeIntervalSince1970: 1_790_000_000), origin: .live, result: result)), as: UTF8.self)
        try Data((#"{"schemaVersion":7,"entries":["# + entry + "]}").utf8)
            .write(to: directory.appendingPathComponent(SavedResultsStore.fileName))

        let store = SavedResultsStore(directory: directory)
        XCTAssertTrue(store.isSaved(ReviewOutcome(result: result, origin: .live)))
        XCTAssertFalse(store.remove(ReviewOutcome(result: result, origin: .live)))
        XCTAssertTrue(store.isSaved(ReviewOutcome(result: result, origin: .live)), "لم تُزل فعلًا")
    }
}
