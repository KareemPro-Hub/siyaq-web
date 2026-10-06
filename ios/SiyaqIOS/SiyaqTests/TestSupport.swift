import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import Siyaq

/// يقرأ ملفات أمثلة الخدمة الفعلية المضمنة في حزمة التطبيق.
enum Samples {
    static let files = ["01-partial", "02-choices", "03-possible", "04-not-found", "05-full-no-tafsir", "06-selected-possible"]

    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: SavedResultsStore.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "المثال \(name) غير موجود في الحزمة", file: file, line: line)
        return try Data(contentsOf: url)
    }

    static func result(_ name: String) throws -> ReviewResult {
        try JSONDecoder().decode(ReviewResult.self, from: data(name))
    }
}

/// اعتراض طلبات URLSession دون شبكة.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int
        var body: Data
        var error: URLError? = nil
        var headers: [String: String] = [:]
    }

    static var handler: ((URLRequest) -> Response)?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = handler(request)
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"].merging(response.headers) { $1 })!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        handler = nil
        lastRequest = nil
        lastBody = nil
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// خطوة في سيناريو مضاعف الخدمة. المفتاحان اختياريان: nil = أي طلب؛
/// selection = .some(nil) يطابق الطلب الأول (بلا موضع) فقط.
struct ScriptStep<Value> {
    let delay: Duration
    let result: Result<Value, ReviewError>
    let quote: String?
    let selection: String??

    init(delay: Duration, result: Result<Value, ReviewError>, quote: String? = nil, selection: String?? = nil) {
        self.delay = delay
        self.result = result
        self.quote = quote
        self.selection = selection
    }

    func matches(quote: String, selection: String?) -> Bool {
        if let expected = self.quote, expected != quote { return false }
        if let expected = self.selection, expected != selection { return false }
        return true
    }
}

/// سيناريو مشترك: يسجل كل طلب، ويختار أول خطوة مطابقة للمفتاح بدل ترتيب الوصول؛
/// والطلب الملغى قبل بدئه لا يستهلك خطوة (مثل URLSession الذي يرمي cancelled).
/// هذا يجعل اختبارات السباق حتمية مهما كان ترتيب جدولة المهام.
final class StepScript<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ScriptStep<Value>]
    private var recorded: [(quote: String, selection: String?)] = []

    init(_ steps: [ScriptStep<Value>]) { self.steps = steps }

    var calls: [(quote: String, selection: String?)] { lock.withLock { recorded } }

    func run(quote: String, selection: String?) async throws -> Value {
        let cancelled = Task.isCancelled
        let step: ScriptStep<Value>? = lock.withLock {
            recorded.append((quote, selection))
            if cancelled { return nil }
            guard let index = steps.firstIndex(where: { $0.matches(quote: quote, selection: selection) }) else {
                return ScriptStep(delay: .zero, result: .failure(.invalidResponse))
            }
            return steps.remove(at: index)
        }
        guard let step else { throw CancellationError() }
        try await Task.sleep(for: step.delay)
        return try step.result.get()
    }
}

/// خدمة وهمية قابلة للتحكم بالتوقيت لاختبار الإلغاء وترتيب الاستجابات.
final class ScriptedService: ReviewServicing, @unchecked Sendable {
    typealias Step = ScriptStep<ReviewResult>
    private let script: StepScript<ReviewResult>
    var calls: [(quote: String, selection: String?)] { script.calls }

    init(_ steps: [Step]) { script = StepScript(steps) }

    func review(quote: String, selection: String?) async throws -> ReviewResult {
        try await script.run(quote: quote, selection: selection)
    }
}
