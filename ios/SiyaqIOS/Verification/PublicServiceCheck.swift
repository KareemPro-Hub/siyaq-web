import Foundation

/// فحص يدوي لعميل التطبيق مع خدمة سِياق المنشورة، بالعنوان نفسه في إعدادات البناء ودون أي بيانات دخول.
/// يشغّله المراجع عند الحاجة (ليس جزءًا من هدف التطبيق ولا اختبارات CI).
@main
struct PublicServiceCheck {
    static func main() async throws {
        let base = ProcessInfo.processInfo.environment["SIYAQ_SERVICE_BASE_URL"] ?? "https://www.mysiyaq.com"
        let service = LiveReviewService(endpoint: try ServiceEndpoint.reviewURL(from: base))
        defer { service.session.invalidateAndCancel() }
        let result = try await service.review(quote: "لا تقربوا الصلاة", selection: nil)
            .verified(forQuote: "لا تقربوا الصلاة", selection: nil)
        guard result.selected?.id == "4:43" else { throw ReviewError.invalidResponse }
        print("Public review passed without credentials; selected 4:43; source " + result.sourceVersion)
    }
}
