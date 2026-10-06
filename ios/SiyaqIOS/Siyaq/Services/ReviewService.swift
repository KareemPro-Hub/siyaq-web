import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// أي مصدر للنتائج: الخدمة الحية أو أمثلة المعاينة.
protocol ReviewServicing: Sendable {
    func review(quote: String, selection: String?) async throws -> ReviewResult
}

/// جسم الطلب: {"quote": "...", "selection": "4:43"}؛ selection يُحذف إن كان nil.
struct ReviewRequestBody: Encodable, Equatable {
    let quote: String
    let selection: String?
}

/// عميل URLSession لـ POST <baseURL>/api/review.
/// - جلسة ephemeral بلا ذاكرة تخزين على القرص ولا كوكيز.
/// - لا يُسجل نص الاقتباس في أي سجل.
/// - أي استجابة غير 200 لا تُفك كنتيجة.
struct LiveReviewService: ReviewServicing {
    let endpoint: URL
    let session: URLSession

    init(endpoint: URL, session: URLSession = LiveReviewService.makeSession()) {
        self.endpoint = endpoint
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        return URLSession(configuration: configuration, delegate: ServiceRedirectGuard(), delegateQueue: nil)
    }

    func makeRequest(quote: String, selection: String?) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONEncoder().encode(ReviewRequestBody(quote: quote, selection: selection))
        return request
    }

    func review(quote: String, selection: String?) async throws -> ReviewResult {
        let request = try makeRequest(quote: quote, selection: selection)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ReviewError.from(error)
        }
        if Task.isCancelled { throw ReviewError.cancelled }

        guard let http = response as? HTTPURLResponse else { throw ReviewError.invalidResponse }
        guard http.statusCode == 200 else {
            throw ReviewError.http(status: http.statusCode, message: ServiceErrorBody.message(from: data))
        }
        let result: ReviewResult
        do {
            result = try JSONDecoder().decode(ReviewResult.self, from: data)
        } catch {
            throw ReviewError.invalidResponse
        }
        // نتيجة متناقضة لا تُعرض ولا تُحفظ كمطابقة (المرحلة ١٣).
        do {
            return try result.verified(forQuote: quote, selection: selection)
        } catch {
            throw ReviewError.invalidResponse
        }
    }
}
