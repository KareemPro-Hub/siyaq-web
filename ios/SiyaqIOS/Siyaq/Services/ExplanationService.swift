import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// الشرح المساعد الاختياري: POST <baseURL>/api/explain بنفس quote وselection.
/// العميل لا يرسل أي تفسير أو مرجع؛ الخادم يستخرج الأدلة بنفسه.
protocol ExplanationServicing: Sendable {
    func explain(quote: String, selection: String?) async throws -> Explanation
}

struct LiveExplanationService: ExplanationServicing {
    /// مهلة العميل حسب العقد: ٥٠ ثانية. لا إعادة محاولة تلقائية.
    static let timeout: TimeInterval = 50
    static let notConfiguredCode = "AI_NOT_CONFIGURED"

    let endpoint: URL
    let session: URLSession

    init(endpoint: URL, session: URLSession = LiveExplanationService.makeSession()) {
        self.endpoint = endpoint
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration, delegate: ServiceRedirectGuard(), delegateQueue: nil)
    }

    func makeRequest(quote: String, selection: String?) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // نفس جسم /api/review تمامًا؛ لا نصوص تفسير ولا مراجع من العميل.
        request.httpBody = try JSONEncoder().encode(ReviewRequestBody(quote: quote, selection: selection))
        return request
    }

    func explain(quote: String, selection: String?) async throws -> Explanation {
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
        switch http.statusCode {
        case 200:
            break
        case 429:
            throw ReviewError.rateLimited(retryAfterSeconds: Self.retryAfter(http))
        case 503 where ServiceErrorBody.code(from: data) == Self.notConfiguredCode:
            throw ReviewError.aiNotConfigured
        default:
            throw ReviewError.http(status: http.statusCode, message: ServiceErrorBody.message(from: data))
        }
        do {
            return try JSONDecoder().decode(Explanation.self, from: data)
        } catch {
            throw ReviewError.invalidResponse
        }
    }

    /// Retry-After بالثواني فقط؛ يُعرض للمستخدم ولا يُستخدم لإعادة محاولة تلقائية.
    static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(raw.trimmingCharacters(in: .whitespaces)),
              seconds > 0, seconds < 3600
        else { return nil }
        return seconds
    }
}

/// هل يجوز طلب شرح لهذه النتيجة؟ موضع مؤكد مختار من الوضع الحي فقط.
enum ExplanationEligibility {
    static func isEligible(_ outcome: ReviewOutcome) -> Bool {
        guard outcome.origin == .live,
              outcome.result.status == .matched,
              let selected = outcome.result.selected
        else { return false }
        switch selected.kind {
        case .full, .partial, .spanning:
            return !selected.verses.isEmpty
        case .possible, .unknown:
            return false
        }
    }
}
