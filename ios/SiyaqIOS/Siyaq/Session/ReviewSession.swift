import Foundation
import Observation

/// حالة طلب واحد.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded(ReviewOutcome)
    case failed(ReviewError)

    var outcome: ReviewOutcome? {
        if case .loaded(let outcome) = self { return outcome }
        return nil
    }

    var isLoading: Bool { self == .loading }
}

/// يدير طلب الاقتباس وطلب اختيار الموضع.
/// - بدء طلب جديد يلغي القديم.
/// - كل طلب يحمل رمزًا؛ استجابة طلب قديم لا تستبدل نتيجة أحدث.
/// - لا يُسجل نص الاقتباس في أي سجل.
@MainActor
@Observable
final class ReviewSession {
    /// نص المستخدم في مربع الاقتباس.
    var input: String = ""
    /// خطأ يظهر تحت مربع الاقتباس (تحقق أو إعداد).
    var inputError: ReviewError? = nil

    private(set) var submittedQuote: String = ""
    private(set) var primary: LoadState = .idle
    private(set) var selection: LoadState = .idle
    private(set) var selectedCandidateID: String? = nil
    /// النص الحالي في المربع جاء من قراءة صورة (حتى لو راجعه المستخدم وعدّله).
    private(set) var inputFromImage = false
    /// الطلب الحالي أُرسل بنص جاء من صورة؛ يغيّر رسالة «لم نجد» فقط، لا يغيّر البحث.
    private(set) var submittedFromImage = false

    @ObservationIgnored private var choice: ServiceChoice? = nil
    /// إعداد الخدمة الذي بدأ به الطلب الحالي؛ تعيد «إعادة المحاولة» تهيئتها إن تعذّرت أول مرة.
    @ObservationIgnored private var configuration: ServiceConfiguration? = nil
    @ObservationIgnored private var primaryTask: Task<Void, Never>? = nil
    @ObservationIgnored private var selectionTask: Task<Void, Never>? = nil
    @ObservationIgnored private var primaryToken = UUID()
    @ObservationIgnored private var selectionToken = UUID()

    init() {}

    /// يبدأ مراجعة جديدة بخدمة سِياق المضبوطة في إعدادات البناء. يعيد false إن رُفض الاقتباس (والخطأ في inputError).
    /// تعذّر تهيئة الخدمة لا يُعرض تحت المربع ولا يُستبدل بأمثلة: تُفتح شاشة المراجعة برسالة واضحة وزر «إعادة المحاولة».
    @discardableResult
    func start(configuration: ServiceConfiguration = .current) -> Bool {
        let quote: String
        do {
            quote = try QuoteValidator.validated(input)
        } catch {
            inputError = ReviewError.from(error)
            return false
        }
        self.configuration = configuration
        do {
            start(quote: quote, using: try configuration.makeReviewService())
        } catch {
            inputError = nil
            cancelAll()
            choice = nil
            submittedQuote = quote
            submittedFromImage = inputFromImage
            primary = .failed(ReviewError.from(error))
        }
        return true
    }

    /// نقطة دخول قابلة للاختبار بخدمة محددة.
    func start(quote: String, using made: ServiceChoice) {
        inputError = nil
        // نقرة مكررة على «ابدأ المراجعة» للاقتباس نفسه أثناء الانتظار: لا طلب ثانٍ.
        if primary.isLoading, quote == submittedQuote, choice?.origin == made.origin { return }
        cancelAll()
        choice = made
        submittedQuote = quote
        submittedFromImage = inputFromImage
        runPrimary()
    }

    func retryPrimary() {
        guard !submittedQuote.isEmpty else { return }
        if choice == nil, let configuration {
            do {
                choice = try configuration.makeReviewService()
            } catch {
                primary = .failed(ReviewError.from(error))
                return
            }
        }
        guard choice != nil else { return }
        cancelSelection()
        runPrimary()
    }

    /// يطلب نتيجة موضع مختار. يُرسل quote نفسه وselection = معرف المرشح كما ورد من الخدمة.
    func select(candidateID: String) {
        guard choice != nil, !submittedQuote.isEmpty else { return }
        // نقرة مكررة على الموضع نفسه أثناء الانتظار: لا طلب ثانٍ.
        if selection.isLoading, selectedCandidateID == candidateID { return }
        selectedCandidateID = candidateID
        runSelection()
    }

    func retrySelection() {
        guard selectedCandidateID != nil else { return }
        runSelection()
    }

    func cancelPrimary() {
        primaryTask?.cancel()
        primaryTask = nil
        primaryToken = UUID()
        if primary.isLoading { primary = .failed(.cancelled) }
    }

    func cancelSelection() {
        selectionTask?.cancel()
        selectionTask = nil
        selectionToken = UUID()
        selection = .idle
        selectedCandidateID = nil
    }

    func cancelAll() {
        cancelSelection()
        primaryTask?.cancel()
        primaryTask = nil
        primaryToken = UUID()
        primary = .idle
    }

    // MARK: داخلي

    private func runPrimary() {
        guard let made = choice else { return }
        primaryTask?.cancel()
        let token = UUID()
        primaryToken = token
        primary = .loading
        let quote = submittedQuote
        primaryTask = Task { [weak self] in
            let state = await Self.perform(made, quote: quote, selection: nil)
            guard let self, self.primaryToken == token, !Task.isCancelled else { return }
            self.primary = state
        }
    }

    private func runSelection() {
        guard let made = choice, let candidateID = selectedCandidateID else { return }
        selectionTask?.cancel()
        let token = UUID()
        selectionToken = token
        selection = .loading
        let quote = submittedQuote
        selectionTask = Task { [weak self] in
            let state = await Self.perform(made, quote: quote, selection: candidateID)
            guard let self, self.selectionToken == token, !Task.isCancelled else { return }
            self.selection = state
        }
    }

    private static func perform(_ made: ServiceChoice, quote: String, selection: String?) async -> LoadState {
        do {
            let result = try await made.service.review(quote: quote, selection: selection)
            return .loaded(ReviewOutcome(result: result, origin: made.origin))
        } catch {
            return .failed(ReviewError.from(error))
        }
    }
}

// نُقل من ScreenshotTextController.swift ليضبط أصل النص (صورة/كتابة) داخل الملف نفسه.
extension ReviewSession {
    /// يضع النص المراجَع في مربع الاقتباس فقط؛ لا يبدأ المراجعة ولا يلغي نتيجة معروضة.
    func useExtractedText(_ text: String) {
        inputError = nil
        input = text
        inputFromImage = !text.isEmpty
    }

    /// تحرير يدوي للمربع: يبقى أصل الصورة ما دام في المربع نص، ويزول عند مسحه كله.
    func editInput(_ text: String) {
        inputError = nil
        input = text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { inputFromImage = false }
    }

    /// مثال مكتوب: ليس من صورة.
    func useSample(_ quote: String) {
        inputError = nil
        input = quote
        inputFromImage = false
    }
}
