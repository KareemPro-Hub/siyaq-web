import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// كل أخطاء المراجعة برسائل عربية بسيطة.
enum ReviewError: Error, Equatable, Sendable {
    // تحقق محلي من الاقتباس
    case emptyQuote
    case tooFewWords
    case quoteTooLong

    // إعداد الخدمة (من إعدادات البناء؛ لا يضبطه المستخدم)
    case notConfigured
    case insecureEndpoint

    // الشبكة
    case offline
    case timedOut
    case unreachable
    case secureConnectionFailed

    // استجابة الخدمة
    case http(status: Int, message: String?)
    case invalidResponse

    // المستخدم ألغى
    case cancelled

    // الأمثلة المسجلة — أداة اختبارات الواجهة فقط، لا تظهر للمستخدم
    case previewUnavailable
    case previewQuoteNotInSamples
    case previewSelectionNotInSamples

    // الشرح المساعد (/api/explain)
    /// 503 مع code=AI_NOT_CONFIGURED: الشرح غير مفعّل في الخدمة.
    case aiNotConfigured
    /// 429: حد مؤقت؛ إعادة المحاولة يدوية فقط.
    case rateLimited(retryAfterSeconds: Int?)
    /// لا يُطلب شرح لنتيجة غير مؤكدة أو لنتيجة معاينة.
    case explanationNotEligible
    /// إصدار بيانات الشرح يختلف عن إصدار النتيجة المعروضة.
    case explanationVersionMismatch

    var title: String {
        switch self {
        case .emptyQuote, .tooFewWords, .quoteTooLong: return "راجع الاقتباس"
        case .notConfigured, .insecureEndpoint: return "خدمة المراجعة غير متاحة"
        case .offline: return "لا يوجد اتصال"
        case .cancelled: return "أُلغيت المراجعة"
        case .previewUnavailable, .previewQuoteNotInSamples, .previewSelectionNotInSamples: return "خارج أمثلة المعاينة"
        case .aiNotConfigured: return "الشرح المساعد غير مفعّل"
        case .rateLimited: return "تجاوزت الحد المؤقت"
        case .explanationNotEligible: return "الشرح المساعد غير متاح هنا"
        case .explanationVersionMismatch: return "تغيّرت بيانات المصدر"
        default: return "تعذرت المراجعة"
        }
    }

    var message: String {
        switch self {
        case .emptyQuote:
            return "اكتب اقتباسًا أو اختر أحد الأمثلة أولًا."
        case .tooFewWords:
            return "اكتب كلمتين على الأقل من الاقتباس."
        case .quoteTooLong:
            return "الاقتباس أطول من المسموح (١٠٠٠ حرف). اختصره ثم أعد المحاولة."
        case .notConfigured:
            return "تعذر الاتصال بخدمة سِياق من هذه النسخة من التطبيق. أعد المحاولة، أو حدّث التطبيق إن استمرت المشكلة. لم نعرض نتيجة بديلة."
        case .insecureEndpoint:
            return "تعذر إنشاء اتصال آمن بخدمة سِياق من هذه النسخة من التطبيق. أعد المحاولة، أو حدّث التطبيق إن استمرت المشكلة."
        case .offline:
            return "لا يوجد اتصال بالإنترنت. المحفوظات متاحة دون اتصال، لكن المراجعة الجديدة تحتاج اتصالًا بالخدمة."
        case .timedOut:
            return "انتهت مهلة الاتصال بالخدمة. حاول مرة أخرى."
        case .unreachable:
            return "تعذر الوصول إلى خدمة المراجعة. تحقق من اتصالك ثم أعد المحاولة، أو حاول بعد قليل."
        case .secureConnectionFailed:
            return "تعذر إنشاء اتصال آمن بخدمة المراجعة."
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            switch status {
            case 401, 403: return "رفضت خدمة المراجعة الطلب الآن. أعد المحاولة بعد قليل."
            case 400: return "تعذر قبول الاقتباس. تأكد أنه كلمتان على الأقل وبطول مناسب."
            case 413: return "الاقتباس أطول من المسموح."
            case 415: return "صيغة الطلب غير مدعومة في الخدمة."
            case 503: return "خدمة المراجعة غير متاحة الآن. حاول بعد قليل."
            default: return "حدث خطأ في خدمة المراجعة (رمز \(ArabicFormat.number(status)))."
            }
        case .invalidResponse:
            return "وصلت استجابة غير مفهومة من خدمة المراجعة."
        case .cancelled:
            return "أوقفت هذه المراجعة. يمكنك إعادة المحاولة."
        case .previewUnavailable:
            return "تعذر تحميل الأمثلة المسجلة للاختبار."
        case .previewQuoteNotInSamples:
            return "هذا الاقتباس ليس من الأمثلة المسجلة للاختبار."
        case .previewSelectionNotInSamples:
            return "نتيجة هذا الموضع غير مسجلة في أمثلة المعاينة للاختبار."
        case .aiNotConfigured:
            return "الشرح المساعد غير مفعّل في الخدمة حاليًا. النص والسياق والتفسير المنقول معروضة كما هي."
        case .rateLimited(let seconds):
            if let seconds, seconds > 0 {
                return "وصلت الطلبات إلى الحد المؤقت. انتظر نحو \(ArabicFormat.number(seconds)) ثانية ثم أعد المحاولة بنفسك."
            }
            return "وصلت الطلبات إلى الحد المؤقت. انتظر قليلًا ثم أعد المحاولة بنفسك."
        case .explanationNotEligible:
            return "يُطلب الشرح المساعد لموضع مؤكد من الخدمة فقط، ولا يُقدَّم للتشابه المحتمل."
        case .explanationVersionMismatch:
            return "تغيّر إصدار بيانات المصدر منذ عرض هذه النتيجة، فلم يُعرض الشرح. أعد المراجعة ثم اطلب الشرح."
        }
    }

    /// كل تعذر في الاتصال بالخدمة أو تهيئتها يُعرض مع «إعادة المحاولة»؛ لا إعدادات يفتحها المستخدم.
    var canRetry: Bool {
        switch self {
        case .notConfigured, .insecureEndpoint, .offline, .timedOut, .unreachable, .secureConnectionFailed,
             .invalidResponse, .cancelled, .rateLimited:
            return true
        case .http(let status, _):
            // رفض مؤقت أو تعذر في الخدمة؛ أما 400/413/415 فمشكلة في الاقتباس نفسه.
            return status >= 500 || [401, 403, 408, 429].contains(status)
        default:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .offline: return "wifi.slash"
        case .rateLimited: return "hourglass"
        case .aiNotConfigured: return "sparkles"
        case .cancelled: return "stop.circle"
        case .notConfigured, .insecureEndpoint: return "exclamationmark.icloud"
        default: return "exclamationmark.triangle"
        }
    }

    /// يحول أي خطأ إلى ReviewError دون كشف تفاصيل تقنية للمستخدم.
    static func from(_ error: Error) -> ReviewError {
        if let error = error as? ReviewError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .timedOut:
                return .timedOut
            case .appTransportSecurityRequiresSecureConnection:
                return .insecureEndpoint
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
                 .clientCertificateRequired:
                return .secureConnectionFailed
            default:
                return .unreachable
            }
        }
        return .unreachable
    }
}

/// جسم الخطأ من الخدمة: {"error":"رسالة عربية","code":"..."}؛ كلاهما اختياري عند الفك.
struct ServiceErrorBody: Decodable {
    let error: String?
    let code: String?

    static func code(from data: Data) -> String? {
        (try? JSONDecoder().decode(ServiceErrorBody.self, from: data))?.code
    }

    /// رسالة الخادم بعد التنظيف، أو nil. تُعرض نصًا فقط.
    static func message(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ServiceErrorBody.self, from: data),
              let raw = body.error else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }
}
