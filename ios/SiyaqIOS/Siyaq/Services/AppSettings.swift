import Foundation
#if canImport(Security)
import Security
#endif

/// الاتصال بخدمة سِياق (طلب كريم ٣ أكتوبر): يُضبط تلقائيًا من إعدادات البناء فقط، دون أي خيار للمستخدم
/// ودون أسرار داخل التطبيق.
///
/// - العنوان من Info.plist ← `SiyaqServiceBaseURL` = `$(SIYAQ_SERVICE_BASE_URL)` في إعدادات بناء هدف التطبيق.
/// - لا وضع معاينة ولا عنوان قابل للتعديل ولا كلمة وصول في الواجهة.
/// - الأمثلة المسجلة أداة لاختبارات الواجهة وحدها: تُفعَّل عبر `UITestSandbox` (Debug وبمتغير بيئة) ولا تصل للمستخدم،
///   ولا تحل أبدًا محل نتيجة حقيقية عند فشل الاتصال.
struct ServiceConfiguration: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case live(baseURL: String)
        /// أمثلة مسجلة — لاختبارات الواجهة فقط.
        case recordedSamples
    }

    static let infoPlistKey = "SiyaqServiceBaseURL"

    let source: Source

    /// إعداد البناء كما في الحزمة. قيمة فارغة أو متغير غير موسَّع تعني: غير مضبوط.
    static func bundled(_ bundle: Bundle = .main) -> ServiceConfiguration {
        ServiceConfiguration(source: .live(baseURL: cleaned(bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)))
    }

    /// التهيئة الفعلية: إعداد البناء، أو بديل اختبار الواجهة (Debug فقط؛ دائمًا nil في Release).
    static var current: ServiceConfiguration {
        UITestSandbox.current?.service ?? bundled()
    }

    static func cleaned(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$(") ? "" : trimmed
    }

    func makeReviewService() throws -> ServiceChoice {
        switch source {
        case .recordedSamples:
            guard let library = PreviewLibrary.bundled else { throw ReviewError.previewUnavailable }
            return ServiceChoice(service: PreviewReviewService(library: library), origin: .preview)
        case .live(let baseURL):
            return ServiceChoice(service: LiveReviewService(endpoint: try ServiceEndpoint.reviewURL(from: baseURL)), origin: .live)
        }
    }

    /// الشرح المساعد على الخدمة الحية نفسها فقط؛ لا شرح للأمثلة المسجلة.
    func makeExplanationService() throws -> any ExplanationServicing {
        switch source {
        case .recordedSamples:
            throw ReviewError.explanationNotEligible
        case .live(let baseURL):
            return LiveExplanationService(endpoint: try ServiceEndpoint.explainURL(from: baseURL))
        }
    }
}

/// الخدمة المختارة لطلب واحد مع مصدر نتيجتها.
struct ServiceChoice {
    let service: any ReviewServicing
    let origin: ResultOrigin
}

/// تنظيف لمرة واحدة لما كانت تحفظه إعدادات الاتصال المحذوفة: الوضع والعنوان ومفتاح الخط في UserDefaults،
/// وكلمة وصول المعاينة في Keychain. لا يمس المحفوظات.
enum LegacyConnectionSettings {
    static let defaultsKeys = ["siyaq.reviewMode", "siyaq.serviceBaseURL", "siyaq.useSystemFont"]
    static let keychainService = "Siyaq.PrivateServiceAccess"

    static func removeStoredValues(defaults: UserDefaults, includeKeychain: Bool) {
        for key in defaultsKeys { defaults.removeObject(forKey: key) }
        #if canImport(Security)
        if includeKeychain {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                        kSecAttrService as String: keychainService]
            _ = SecItemDelete(query as CFDictionary)
        }
        #endif
    }
}
