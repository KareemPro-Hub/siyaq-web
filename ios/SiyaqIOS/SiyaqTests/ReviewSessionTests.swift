import XCTest
@testable import Siyaq

/// الإلغاء وترتيب الاستجابات: لا تستبدل استجابة قديمة نتيجة أحدث.
@MainActor
final class ReviewSessionTests: XCTestCase {

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testNewerRequestWinsOverSlowOlderResponse() async throws {
        let older = try Samples.result("02-choices")
        let newer = try Samples.result("05-full-no-tafsir")
        let service = ScriptedService([
            .init(delay: .milliseconds(600), result: .success(older), quote: "غفور رحيم"),
            .init(delay: .milliseconds(50), result: .success(newer), quote: "قل هو الله أحد"),
        ])
        let session = ReviewSession()
        let choice = ServiceChoice(service: service, origin: .live)

        session.start(quote: "غفور رحيم", using: choice)
        session.start(quote: "قل هو الله أحد", using: choice)

        await waitUntil { session.primary.outcome != nil }
        XCTAssertEqual(session.primary.outcome?.result.quote, "قل هو الله أحد")

        // انتظر حتى ينتهي وقت الطلب القديم وتأكد أنه لم يستبدل النتيجة.
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.primary.outcome?.result.quote, "قل هو الله أحد")
        XCTAssertEqual(session.submittedQuote, "قل هو الله أحد")
    }

    func testCancelPrimaryShowsCancelledAndIgnoresLateResponse() async throws {
        let service = ScriptedService([
            .init(delay: .milliseconds(300), result: .success(try Samples.result("01-partial"))),
        ])
        let session = ReviewSession()
        session.start(quote: "لا تقربوا الصلاة", using: ServiceChoice(service: service, origin: .live))
        XCTAssertEqual(session.primary, .loading)

        session.cancelPrimary()
        XCTAssertEqual(session.primary, .failed(.cancelled))

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.primary, .failed(.cancelled))
    }

    func testSelectionSendsSameQuoteAndCandidateID() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .success(try Samples.result("03-possible"))),
            .init(delay: .zero, result: .success(try Samples.result("06-selected-possible"))),
        ])
        let session = ReviewSession()
        session.start(quote: "لا تقربوا الصلاه وانتم سكارى", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary.outcome != nil }
        XCTAssertEqual(session.primary.outcome?.result.status, .possible)

        let candidate = try XCTUnwrap(session.primary.outcome?.result.candidates.first)
        session.select(candidateID: candidate.id)
        await waitUntil { session.selection.outcome != nil }

        XCTAssertEqual(service.calls.count, 2)
        XCTAssertEqual(service.calls[1].quote, "لا تقربوا الصلاه وانتم سكارى")
        XCTAssertEqual(service.calls[1].selection, "4:43")
        XCTAssertEqual(session.selection.outcome?.result.selected?.kind, .possible)
        // نتيجة الاختيار لا تغير نتيجة الاقتباس الأصلية.
        XCTAssertEqual(session.primary.outcome?.result.status, .possible)
    }

    func testFailureIsShownNotReplacedByPreview() async throws {
        let service = ScriptedService([
            .init(delay: .zero, result: .failure(.offline)),
        ])
        let session = ReviewSession()
        session.start(quote: "أ ب", using: ServiceChoice(service: service, origin: .live))
        await waitUntil { session.primary != .loading }
        XCTAssertEqual(session.primary, .failed(.offline))
    }

    func testInvalidInputDoesNotStartRequest() async {
        let session = ReviewSession()
        session.input = "كلمة"
        XCTAssertFalse(session.start(configuration: ServiceConfiguration(source: .recordedSamples)))
        XCTAssertEqual(session.inputError, .tooFewWords)
        XCTAssertEqual(session.primary, .idle)
    }

    /// بناء بلا عنوان خدمة: لا رسالة إعدادات تحت المربع ولا أمثلة بديلة؛ شاشة خطأ واضحة قابلة لإعادة المحاولة.
    func testMissingBuildServiceShowsRetryableFailureNotSamples() async {
        let session = ReviewSession()
        session.input = "لا تقربوا الصلاة"
        XCTAssertTrue(session.start(configuration: ServiceConfiguration(source: .live(baseURL: ""))))
        XCTAssertNil(session.inputError)
        XCTAssertEqual(session.primary, .failed(.notConfigured))
        XCTAssertTrue(ReviewError.notConfigured.canRetry)
        XCTAssertNil(session.primary.outcome, "لا نتيجة تجريبية بدل النتيجة الحقيقية")
        session.retryPrimary()
        XCTAssertEqual(session.primary, .failed(.notConfigured), "إعادة المحاولة تعيد التهيئة ولا تتحول لأمثلة")
    }

    /// تعذر الوصول إلى الخدمة الحية لا يُستبدل أبدًا بنتيجة من الأمثلة المسجلة.
    func testUnreachableLiveServiceNeverFallsBackToSamples() async {
        let session = ReviewSession()
        session.input = "قل هو الله أحد"
        XCTAssertTrue(session.start(configuration: ServiceConfiguration(source: .live(baseURL: "http://127.0.0.1:9"))))
        await waitUntil({ session.primary != .loading }, timeout: 20)
        XCTAssertNil(session.primary.outcome)
        if case .failed(let error) = session.primary {
            XCTAssertTrue(error.canRetry, "\(error)")
        } else {
            XCTFail("\(session.primary)")
        }
    }

    func testPreviewModeLoadsRecordedSample() async {
        let session = ReviewSession()
        session.input = "قل هو الله أحد"
        XCTAssertTrue(session.start(configuration: ServiceConfiguration(source: .recordedSamples)))
        await waitUntil { session.primary.outcome != nil }
        XCTAssertEqual(session.primary.outcome?.origin, .preview)
        XCTAssertEqual(session.primary.outcome?.result.selected?.id, "112:1")
    }
}
