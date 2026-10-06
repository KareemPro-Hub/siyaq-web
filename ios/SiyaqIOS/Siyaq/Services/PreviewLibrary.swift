import Foundation

/// وضع المعاينة: نتائج فعلية مسجلة من محرك سِياق المحلي (مدخلات/أمثلة-الخدمة)، تُقرأ من حزمة التطبيق.
/// ليست خدمة حية، ولا يتحول التطبيق إليها تلقائيًا عند فشل الشبكة.
struct PreviewLibrary: Sendable {
    struct Sample: Sendable {
        let file: String
        /// selection المرسل الذي أنتج هذا المثال، أو nil.
        let selection: String?
        let result: ReviewResult
        /// وصف قصير لما يوضحه المثال.
        let caption: String
    }

    /// ملفات الأمثلة كما وردت؛ لا تُعدل محتوياتها.
    static let manifest: [(file: String, selection: String?, caption: String)] = [
        ("01-partial", nil, "جزء من آية، مع التفسير المتاح"),
        ("02-choices", nil, "ورد في أكثر من موضع"),
        ("03-possible", nil, "تشابه محتمل، ليس إثباتًا"),
        ("04-not-found", nil, "عبارة غير موجودة في النص"),
        ("05-full-no-tafsir", nil, "آية كاملة، دون تفسير متاح"),
        ("06-selected-possible", "4:43", "موضع محتمل اختاره المستخدم"),
    ]

    let samples: [Sample]

    init(bundle: Bundle) throws {
        let decoder = JSONDecoder()
        samples = try Self.manifest.map { item in
            guard let url = bundle.url(forResource: item.file, withExtension: "json") else {
                throw ReviewError.previewUnavailable
            }
            let data = try Data(contentsOf: url)
            let result = try decoder.decode(ReviewResult.self, from: data)
            return Sample(file: item.file, selection: item.selection, result: result, caption: item.caption)
        }
    }

    /// المكتبة المضمنة في التطبيق (nil إن تعذر تحميلها).
    static let bundled: PreviewLibrary? = try? PreviewLibrary(bundle: Bundle(for: BundleToken.self))

    /// الأمثلة التي تبدأ بها المراجعة (دون selection)، بترتيبها.
    var startingSamples: [Sample] { samples.filter { $0.selection == nil } }

    func result(for quote: String, selection: String?) throws -> ReviewResult {
        let key = Self.lookupKey(quote)
        if let match = samples.first(where: { Self.lookupKey($0.result.quote) == key && $0.selection == selection }) {
            return match.result
        }
        if selection != nil, samples.contains(where: { Self.lookupKey($0.result.quote) == key }) {
            throw ReviewError.previewSelectionNotInSamples
        }
        throw ReviewError.previewQuoteNotInSamples
    }

    /// مفتاح بحث داخلي فقط لمطابقة نص المستخدم بأسماء الأمثلة؛ لا يُعرض أبدًا.
    /// يزيل التشكيل وعلامات المصحف والتطويل ويوحد صور الألف والمسافات.
    static func lookupKey(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            switch scalar.value {
            case 0xFEFF, 0x0640, 0x200C, 0x200D, 0x200E, 0x200F:
                continue
            case 0x0623, 0x0625, 0x0622, 0x0671:
                scalars.append(Unicode.Scalar(0x0627)!)
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }
}

/// يحدد حزمة التطبيق حتى عند تشغيل الاختبارات.
private final class BundleToken {}

/// نتائج المعاينة بتأخير قصير لإظهار حالة الانتظار وإتاحة الإلغاء.
struct PreviewReviewService: ReviewServicing {
    let library: PreviewLibrary
    var delay: Duration = .milliseconds(450)

    func review(quote: String, selection: String?) async throws -> ReviewResult {
        do {
            try await Task.sleep(for: delay)
        } catch {
            throw ReviewError.cancelled
        }
        return try library.result(for: quote, selection: selection)
    }
}
