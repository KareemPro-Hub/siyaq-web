import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Siyaq

/// عميل URLSession: شكل الطلب، فك 200، رفض فك أي HTTP فاشل، وتحويل أخطاء الشبكة.
final class ReviewServiceTests: XCTestCase {
    private let endpoint = URL(string: "https://service.invalid/api/review")!

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func service() -> LiveReviewService {
        LiveReviewService(endpoint: endpoint, session: StubURLProtocol.session())
    }

    func testRequestShapeWithoutSelection() async throws {
        let body = try Samples.data("01-partial")
        StubURLProtocol.handler = { _ in .init(status: 200, body: body) }

        let result = try await service().review(quote: "لا تقربوا الصلاة", selection: nil)
        XCTAssertEqual(result.selected?.id, "4:43")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(json["quote"] as? String, "لا تقربوا الصلاة")
        XCTAssertNil(json["selection"], "selection يجب أن يُحذف حين لا يوجد اختيار")
    }

    func testRequestCarriesSelectionFromService() async throws {
        let body = try Samples.data("06-selected-possible")
        StubURLProtocol.handler = { _ in .init(status: 200, body: body) }

        let result = try await service().review(quote: "لا تقربوا الصلاه وانتم سكارى", selection: "4:43")
        XCTAssertEqual(result.selected?.kind, .possible)

        let sent = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(json["selection"] as? String, "4:43")
        XCTAssertEqual(json["quote"] as? String, "لا تقربوا الصلاه وانتم سكارى")
    }

    func testHTTP400ShowsServerMessageAndIsNotDecodedAsResult() async throws {
        let message = "اكتب كلمتين على الأقل."
        StubURLProtocol.handler = { _ in
            .init(status: 400, body: try! JSONSerialization.data(withJSONObject: ["error": message]))
        }
        do {
            _ = try await service().review(quote: "كلمة", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .http(status: 400, message: message))
            XCTAssertEqual(error.message, message)
            XCTAssertFalse(error.canRetry)
        }
    }

    func testHTTP503IsRetryable() async throws {
        StubURLProtocol.handler = { _ in .init(status: 503, body: Data("{}".utf8)) }
        do {
            _ = try await service().review(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .http(status: 503, message: nil))
            XCTAssertTrue(error.canRetry)
        }
    }

    func testFailedStatusWithResultLikeBodyIsStillAnError() async throws {
        let body = try Samples.data("01-partial")
        StubURLProtocol.handler = { _ in .init(status: 500, body: body) }
        do {
            _ = try await service().review(quote: "أ ب", selection: nil)
            XCTFail("يجب ألا تُفك استجابة فاشلة كنتيجة")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .http(status: 500, message: nil))
        }
    }

    func testMalformedBodyIsInvalidResponse() async throws {
        StubURLProtocol.handler = { _ in .init(status: 200, body: Data("{\"status\":1}".utf8)) }
        do {
            _ = try await service().review(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testOfflineMapsToOffline() async throws {
        StubURLProtocol.handler = { _ in .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)) }
        do {
            _ = try await service().review(quote: "أ ب", selection: nil)
            XCTFail("يجب أن يفشل")
        } catch let error as ReviewError {
            XCTAssertEqual(error, .offline)
        }
    }
}

/// التحقق من الإدخال وعنوان الخدمة والروابط ووضع المعاينة.
final class ValidationTests: XCTestCase {

    func testQuoteValidation() throws {
        XCTAssertThrowsError(try QuoteValidator.validated("   ")) { XCTAssertEqual($0 as? ReviewError, .emptyQuote) }
        XCTAssertThrowsError(try QuoteValidator.validated("الصلاة")) { XCTAssertEqual($0 as? ReviewError, .tooFewWords) }
        let long = String(repeating: "كلمة ", count: 300)
        XCTAssertThrowsError(try QuoteValidator.validated(long)) { XCTAssertEqual($0 as? ReviewError, .quoteTooLong) }
        XCTAssertEqual(try QuoteValidator.validated("  لا تقربوا الصلاة \n"), "لا تقربوا الصلاة")
    }

    func testEndpointBuilding() throws {
        XCTAssertThrowsError(try ServiceEndpoint.reviewURL(from: "", allowLocalHTTP: false)) {
            XCTAssertEqual($0 as? ReviewError, .notConfigured)
        }
        XCTAssertEqual(
            try ServiceEndpoint.reviewURL(from: "https://service.invalid/", allowLocalHTTP: false).absoluteString,
            "https://service.invalid/api/review"
        )
        XCTAssertEqual(
            try ServiceEndpoint.reviewURL(from: "https://service.invalid/siyaq", allowLocalHTTP: false).absoluteString,
            "https://service.invalid/siyaq/api/review"
        )
        XCTAssertEqual(
            try ServiceEndpoint.reviewURL(from: "http://127.0.0.1:3000", allowLocalHTTP: true).absoluteString,
            "http://127.0.0.1:3000/api/review"
        )
        // HTTP لغير الجهاز المحلي مرفوض دائمًا، وHTTP المحلي مرفوض في الإصدار.
        XCTAssertThrowsError(try ServiceEndpoint.reviewURL(from: "http://service.invalid", allowLocalHTTP: true))
        XCTAssertThrowsError(try ServiceEndpoint.reviewURL(from: "http://127.0.0.1:3000", allowLocalHTTP: false))
        XCTAssertThrowsError(try ServiceEndpoint.reviewURL(from: "ftp://service.invalid", allowLocalHTTP: true))
        XCTAssertThrowsError(try ServiceEndpoint.reviewURL(from: "https://user:pass@service.invalid", allowLocalHTTP: false))
    }

    func testSafeLinkAllowsOnlyHTTPAndHTTPS() {
        XCTAssertNotNil(SafeLink.url(from: "https://quranpedia.net/api/v1/ayah/4/43/book/269"))
        XCTAssertNotNil(SafeLink.url(from: "http://dorar.net/tafseer"))
        XCTAssertNil(SafeLink.url(from: "javascript:alert(1)"))
        XCTAssertNil(SafeLink.url(from: "file:///etc/passwd"))
        XCTAssertNil(SafeLink.url(from: "tel:123"))
        XCTAssertNil(SafeLink.url(from: "https://"))
        XCTAssertNil(SafeLink.url(from: ""))
        XCTAssertNil(SafeLink.url(from: "https://user:pw@quranpedia.net/"))
    }

    func testAllTafsirURLsInSamplesAreSafe() throws {
        for name in Samples.files {
            let result = try Samples.result(name)
            for entry in result.tafsir.flatMap(\.entries) {
                XCTAssertNotNil(SafeLink.url(from: entry.url), "\(name): \(entry.url)")
            }
        }
    }

    func testPreviewLibraryMapsQuotesAndSelections() throws {
        let library = try XCTUnwrap(PreviewLibrary.bundled)
        XCTAssertEqual(library.samples.count, 6)
        XCTAssertEqual(try library.result(for: "لا تقربوا الصلاة", selection: nil).status, .matched)
        XCTAssertEqual(try library.result(for: "غفور  رحيم", selection: nil).status, .choices)
        XCTAssertEqual(try library.result(for: "لا تقربوا الصلاه وانتم سكارى", selection: nil).status, .possible)
        XCTAssertEqual(try library.result(for: "لا تقربوا الصلاه وانتم سكارى", selection: "4:43").selected?.kind, .possible)
        XCTAssertEqual(try library.result(for: "قُلْ هُوَ اللَّهُ أَحَدٌ", selection: nil).selected?.id, "112:1")
        XCTAssertThrowsError(try library.result(for: "غفور رحيم", selection: "2:173")) {
            XCTAssertEqual($0 as? ReviewError, .previewSelectionNotInSamples)
        }
        XCTAssertThrowsError(try library.result(for: "إن مع العسر يسرا", selection: nil)) {
            XCTAssertEqual($0 as? ReviewError, .previewQuoteNotInSamples)
        }
    }
}

/// العميل لا يتبع التحويلات ولا يحفظ cookies؛ لا بيانات دخول في التطبيق.
final class ServiceTransportTests: XCTestCase {
    func testRedirectsNeverForwardPrivateRequests() throws {
        let delegate = ServiceRedirectGuard()
        let session = LiveReviewService.makeSession()
        defer { session.invalidateAndCancel() }
        let initial = URL(string: "https://preview.invalid/api/review")!
        let task = session.dataTask(with: initial)
        for target in ["https://attacker.invalid/api/review", "http://preview.invalid/api/review", "https://preview.invalid/other"] {
            let response = HTTPURLResponse(url: initial, statusCode: 307, httpVersion: nil, headerFields: ["Location": target])!
            var invoked = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: URLRequest(url: URL(string: target)!)) { forwarded in
                invoked = true
                XCTAssertNil(forwarded)
            }
            XCTAssertTrue(invoked)
        }
    }

    func testBothLiveClientsUseRedirectProtectionAndNoCookies() {
        for session in [LiveReviewService.makeSession(), LiveExplanationService.makeSession()] {
            XCTAssertTrue(session.delegate is ServiceRedirectGuard)
            XCTAssertNil(session.configuration.httpCookieStorage)
            XCTAssertFalse(session.configuration.httpShouldSetCookies)
            session.invalidateAndCancel()
        }
        XCTAssertTrue(ReviewError.http(status: 401, message: nil).canRetry)
    }
}
