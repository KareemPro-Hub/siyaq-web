import Foundation
import Observation

/// حالة الشرح المساعد لنتيجة واحدة.
enum ExplanationState: Equatable {
    /// لم يُطلب بعد؛ يعرض إشعار الخصوصية وزر الطلب اليدوي.
    case idle
    case loading
    /// ready بعد الفحص الدفاعي.
    case ready(Explanation)
    /// امتناع صريح من الخادم؛ لا شرح بديل.
    case abstained(Explanation)
    case failed(ReviewError)
}

/// يدير طلب شرح واحد لكل شاشة نتيجة.
/// - الطلب يدوي فقط (زر)، ولا إعادة محاولة تلقائية.
/// - إلغاء عند مغادرة الشاشة أو تغير الموضع.
/// - رمز لكل طلب يمنع استبدال الحالة باستجابة قديمة.
@MainActor
@Observable
final class ExplanationController {
    private(set) var state: ExplanationState = .idle
    /// عدد الطلبات المرسلة فعلًا (للاختبار والتحقق من عدم وجود طلبات تلقائية).
    private(set) var requestCount = 0

    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private var token = UUID()

    init() {}

    /// مفتاح الطلب الجاري (لمنع تكرار الطلب نفسه بنقرات متتالية).
    @ObservationIgnored private var inFlightKey: String? = nil

    static func requestKey(for outcome: ReviewOutcome, quote: String, selection: String?) -> String {
        [quote, selection ?? "-", outcome.result.selected?.id ?? "-", outcome.result.sourceVersion]
            .joined(separator: "\u{1F}")
    }

    /// يطلب الشرح. يرفض محليًا النتائج غير المؤهلة دون أي طلب شبكي.
    /// نقرة مكررة على الطلب نفسه أثناء الانتظار تُتجاهل؛ طلب لموضع آخر يلغي القديم.
    func request(for outcome: ReviewOutcome, quote: String, selection: String?, service: any ExplanationServicing) {
        guard ExplanationEligibility.isEligible(outcome) else {
            cancel()
            state = .failed(.explanationNotEligible)
            return
        }
        let key = Self.requestKey(for: outcome, quote: quote, selection: selection)
        if state == .loading, inFlightKey == key { return }

        task?.cancel()
        let current = UUID()
        token = current
        inFlightKey = key
        state = .loading
        requestCount += 1
        let result = outcome.result
        task = Task { [weak self] in
            let next: ExplanationState
            do {
                let explanation = try await service.explain(quote: quote, selection: selection)
                next = Self.state(for: explanation, displayed: result)
            } catch {
                next = .failed(ReviewError.from(error))
            }
            guard let self, self.token == current, !Task.isCancelled else { return }
            self.inFlightKey = nil
            self.state = next
        }
    }

    /// يحول استجابة الخادم إلى حالة عرض بعد التحقق مقابل النتيجة المعروضة.
    static func state(for explanation: Explanation, displayed result: ReviewResult) -> ExplanationState {
        do {
            let checked = try explanation.verified(for: result)
            return checked.status == .abstained ? .abstained(checked) : .ready(checked)
        } catch ExplanationRejection.versionMismatch {
            return .failed(.explanationVersionMismatch)
        } catch ExplanationRejection.notEligible {
            return .failed(.explanationNotEligible)
        } catch {
            return .failed(.invalidResponse)
        }
    }

    /// يلغي أي طلب جارٍ ويعيد الحالة إلى البداية (لا يحذف شيئًا محفوظًا).
    func cancel() {
        task?.cancel()
        task = nil
        token = UUID()
        inFlightKey = nil
        if state == .loading { state = .idle }
    }

    /// خطأ إعداد محلي (عنوان غير مضبوط مثلًا) دون أي اتصال.
    func showFailure(_ error: ReviewError) {
        cancel()
        state = .failed(error)
    }

    /// يُستدعى عند تغير النتيجة أو الموضع المعروض.
    func reset() {
        cancel()
        state = .idle
    }
}

// تهيئة خدمة الشرح: ServiceConfiguration.makeExplanationService() (من إعدادات البناء فقط).
