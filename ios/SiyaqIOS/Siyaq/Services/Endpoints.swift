import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// التحقق من الاقتباس قبل الإرسال وفق العقد: كلمتان على الأقل، و١٠٠٠ وحدة UTF-16 كحد أقصى.
/// لا يُعدل نص المستخدم سوى إزالة المسافات في طرفيه.
enum QuoteValidator {
    static let maxUTF16Length = 1000

    static func validated(_ raw: String) throws -> String {
        let quote = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { throw ReviewError.emptyQuote }
        guard quote.utf16.count <= maxUTF16Length else { throw ReviewError.quoteTooLong }
        let words = quote.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count >= 2 else { throw ReviewError.tooFewWords }
        return quote
    }
}

/// بناء عنوان POST <baseURL>/api/review من عنوان الخدمة في إعدادات البناء (ServiceConfiguration).
/// لا بيانات دخول في العنوان ولا في التطبيق.
enum ServiceEndpoint {
    static let reviewPath = "/api/review"

    /// HTTP مسموح فقط لعناوين الجهاز المحلية في بناء Debug (محاكي macOS).
    static var allowsLocalHTTP: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    static let explainPath = "/api/explain"

    static func reviewURL(from base: String, allowLocalHTTP: Bool = allowsLocalHTTP) throws -> URL {
        try url(from: base, path: reviewPath, allowLocalHTTP: allowLocalHTTP)
    }

    /// الشرح المساعد على نفس الخدمة وبنفس قواعد العنوان (https، وlocalhost في Debug فقط).
    static func explainURL(from base: String, allowLocalHTTP: Bool = allowsLocalHTTP) throws -> URL {
        try url(from: base, path: explainPath, allowLocalHTTP: allowLocalHTTP)
    }

    static func url(from base: String, path endpointPath: String, allowLocalHTTP: Bool) throws -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReviewError.notConfigured }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { throw ReviewError.insecureEndpoint }

        switch scheme {
        case "https":
            break
        case "http" where allowLocalHTTP && loopbackHosts.contains(host):
            break
        default:
            throw ReviewError.insecureEndpoint
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.scheme = scheme
        components.path = path + endpointPath
        guard let url = components.url else { throw ReviewError.insecureEndpoint }
        return url
    }
}

/// روابط المصادر قيم غير موثوقة: يُسمح بـ http/https فقط ولها مضيف، بلا بيانات دخول.
enum SafeLink {
    static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url
        else { return nil }
        return url
    }

    /// مصدر النص القرآني كما في التصميم المعتمد.
    static let quranpedia = URL(string: "https://quranpedia.net/")!
}

/// روابط مباشرة إلى موضع النص والتفسير في مصادرهما (طلب كريم ٣ أكتوبر).
/// الأنماط فُحصت فعلًا بعناوين الصفحات (انظر سجل-التحقق-من-الروابط.md في التسليم)، ولا تُخمَّن لكتب أخرى.
enum SourceLinks {
    /// عدد آيات كل سورة في مصحف حفص (٦٢٣٦ آية)؛ يمنع بناء رابط لآية غير موجودة.
    static let ayahCounts: [Int] = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
        112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
        54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
        14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
        29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
        11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
    ]

    /// كتب التفسير التي فُحص لها نمط صفحة الكتاب المطبوعة في الموسوعة القرآنية.
    static let verifiedTafsirBooks: Set<Int> = [269, 27758]

    static func isValid(surah: Int, ayah: Int) -> Bool {
        (1...114).contains(surah) && ayah >= 1 && ayah <= ayahCounts[surah - 1]
    }

    /// صفحة الآية نفسها في مصحف حفص بالموسوعة القرآنية: https://quranpedia.net/surah/1/{سورة}/{آية}.
    /// (‏/surah/{رقم} وحده يفتح مصحفًا آخر بهذا الرقم، لا السورة.)
    static func verse(surah: Int, ayah: Int) -> URL? {
        guard isValid(surah: surah, ayah: ayah) else { return nil }
        return URL(string: "https://quranpedia.net/surah/1/\(surah)/\(ayah)")
    }

    /// المسارات الرسمية للسور، مستخرجة من تحويلات الموسوعة للسور١١٤ بتاريخ٣ أكتوبر٢٠٢٦.
    /// سجل التحقق محفوظ في روابط-الآية/quranpedia-ayah-routes.json؛ لا أسماء مسارات مخمّنة.
    static let tafsirSurahSlugs = [
        "al-fatiha", "al-baqara", "aal-imran", "an-nisa", "al-maida", "al-anam", "al-araf", "al-anfal", "at-tawba", "yunus", "hud", "yusuf",
        "ar-rad", "ibrahim", "al-hijr", "an-nahl", "al-isra", "al-kahf", "maryam", "ta-ha", "al-anbiya", "al-hajj", "al-muminun", "an-nur",
        "al-furqan", "ash-shuara", "an-naml", "al-qasas", "al-ankabut", "ar-rum", "luqman", "as-sajda", "al-ahzab", "saba", "fatir", "ya-sin",
        "as-saffat", "sad", "az-zumar", "ghafir", "fussilat", "ash-shura", "az-zukhruf", "ad-dukhan", "al-jathiya", "al-ahqaf", "muhammad", "al-fath",
        "al-hujurat", "qaf", "adh-dhariyat", "at-tur", "an-najm", "al-qamar", "ar-rahman", "al-waqia", "al-hadid", "al-mujadila", "al-hashr", "al-mumtahina",
        "as-saff", "al-jumua", "al-munafiqun", "at-taghabun", "at-talaq", "at-tahrim", "al-mulk", "al-qalam", "al-haaqqa", "al-maarij", "nuh", "al-jinn",
        "al-muzzammil", "al-muddaththir", "al-qiyama", "al-insan", "al-mursalat", "an-naba", "an-naziat", "abasa", "at-takwir", "al-infitar", "al-mutaffifin", "al-inshiqaq",
        "al-buruj", "at-tariq", "al-ala", "al-ghashiya", "al-fajr", "al-balad", "ash-shams", "al-layl", "ad-duha", "ash-sharh", "at-tin", "al-alaq",
        "al-qadr", "al-bayyina", "az-zalzala", "al-adiyat", "al-qaria", "at-takathur", "al-asr", "al-humaza", "al-fil", "quraysh", "al-maun", "al-kawthar",
        "al-kafirun", "an-nasr", "al-masad", "al-ikhlas", "al-falaq", "an-nas",
    ]

    /// صفحة تفسير الآية والكتاب المحددين؛ رابط الصفحة المطبوعة قد يضم آيات عديدة.
    static func tafsirAyah(bookId: Int, surah: Int, ayah: Int) -> URL? {
        guard verifiedTafsirBooks.contains(bookId), isValid(surah: surah, ayah: ayah),
              tafsirSurahSlugs.count == ayahCounts.count else { return nil }
        return URL(string: "https://quranpedia.net/tafsir/\(tafsirSurahSlugs[surah - 1])/\(ayah)?book=\(bookId)")
    }

    /// صفحة الكتاب المطبوعة التي ورد فيها نص التفسير المعروض: https://quranpedia.net/book/{كتاب}/{جزء}/{صفحة}.
    /// nil إن كان الكتاب غير مفحوص أو الجزء ليس رقمًا أو الصفحة مجهولة؛ عندها لا نعرض رابطًا بديلًا عامًا.
    static func tafsirPage(bookId: Int, part: String, page: Int?) -> URL? {
        guard verifiedTafsirBooks.contains(bookId), let page, page > 0,
              let partNumber = Int(part.trimmingCharacters(in: .whitespaces)), partNumber > 0
        else { return nil }
        return URL(string: "https://quranpedia.net/book/\(bookId)/\(partNumber)/\(page)")
    }

    struct DorarPassage: Equatable {
        let firstAyah: Int
        let lastAyah: Int
        let url: URL
    }

    /// مقاطع إبراهيم كما وردت في صفحات الدرر الرسمية، وليست أرقام آيات في مسار الرابط.
    /// السجل المحلي لا يحتوي نص التفسير ولا يُنشئ مقطعًا لسورة لم تُراجع روابطها.
    static func dorarPassage(surah: Int, ayah: Int) -> DorarPassage? {
        guard isValid(surah: surah, ayah: ayah), surah == 14 else { return nil }
        let ends = [3, 8, 12, 18, 21, 23, 27, 31, 34, 41, 46, 52]
        guard let index = ends.firstIndex(where: { ayah <= $0 }),
              let url = URL(string: "https://dorar.net/tafseer/14/\(index + 1)") else { return nil }
        return DorarPassage(firstAyah: index == 0 ? 1 : ends[index - 1] + 1,
                            lastAyah: ends[index], url: url)
    }
}

/// قائمة «المصادر» في «عن سِياق» (طلب كريم ٣ أكتوبر): ما تستخدمه النتائج فعلًا فقط، بدوره ورابطه العام.
/// كتاب تفسير لا يدخل هنا إلا إذا كانت بياناته محمّلة ونمط رابطه مفحوصًا (SourceLinks.verifiedTafsirBooks)
/// وشرطه في المرجعية مثبتًا (القرون الثلاثة الأولى بحسب source-policy.json). الدرر السنية لا تُدرج مصدرًا للبيانات
/// قبل ربط بياناتها والتحقق منها؛ الإحالة الخارجية إلى مقطع آيات مفحوص فقط.
enum AboutSources {
    struct Entry: Equatable {
        let title: String
        let role: String
        let url: URL
        /// رقم الكتاب في الموسوعة القرآنية لكتب التفسير؛ nil للنص القرآني.
        let tafsirBookId: Int?
    }

    static let entries: [Entry] = [
        Entry(title: "الموسوعة القرآنية",
              role: "النص القرآني (مصحف حفص) والآيات المحيطة به، وتُقرأ منها نصوص كتابي التفسير.",
              url: URL(string: "https://quranpedia.net/")!, tafsirBookId: nil),
        Entry(title: "تفسير مجاهد",
              role: "نص التفسير الأصلي حيث يتوفر · مجاهد بن جبر (ت ١٠٤هـ).",
              url: URL(string: "https://quranpedia.net/book/269")!, tafsirBookId: 269),
        Entry(title: "تفسير سفيان الثوري",
              role: "نص التفسير الأصلي حيث يتوفر · سفيان الثوري (ت ١٦١هـ).",
              url: URL(string: "https://quranpedia.net/book/27758")!, tafsirBookId: 27758),
    ]

    static let note = "كتابا التفسير من مصادر القرون الثلاثة الأولى التي تقبلها المرجعية المعتمدة، ويغطيان بعض الآيات فقط؛ يظهر غياب التفسير صراحة ولا نعرض تفسير آية أخرى. داخل النتيجة يفتح كل رابط الآية نفسها أو صفحة التفسير نفسها."

    static let dorarNote = "الدرر السنية (التفسير) منصة معتمدة في المرجعية، لكن نصوصها لم تُربط بسِياق بعد؛ لذلك لا نعرض نصًا منها. عند غياب تفسير محفوظ نُحيل إلى مقطع الآيات إذا تحققنا من رابطه، ولا نضع رابطًا عامًا بدل الموضع المحدد."
}

/// لا نتبع تحويلات الخدمة، حتى لا يُرسل الاقتباس إلى عنوان آخر.
final class ServiceRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
