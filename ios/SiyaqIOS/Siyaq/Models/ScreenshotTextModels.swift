import Foundation

// قراءة اقتباس من صورة (سكرين شوت) — منطق نقي بلا واجهة، قابل للاختبار على أي منصة.
// قواعد ثابتة:
// - الاستخراج محلي على الجهاز فقط؛ الصورة لا تُرفع ولا تُحفظ ولا تُسجَّل.
// - النص المستخرج مسودة يراجعها المستخدم ويعدّلها؛ ليس نصًا قرآنيًا موثقًا، ولا يبدأ البحث تلقائيًا.
// - لا يُضاف إلى النص شيء (لا تشكيل ولا تصحيح)؛ يُزال فقط ما لا يُرى (محارف الاتجاه والعرض الصفري) وتُوحَّد المسافات.

// MARK: - الحدود

/// حدود الصورة قبل الاستخراج: الحجم والأبعاد وعدد البكسلات.
struct ScreenshotLimits: Equatable, Sendable {
    /// أقصى حجم للملف كما ورد من مكتبة الصور.
    var maxBytes: Int = 25 * 1024 * 1024
    /// أقصى طول لأي ضلع بالبكسل.
    var maxSide: Int = 12_000
    /// أقصى عدد بكسلات (العرض × الارتفاع).
    var maxPixels: Int = 50_000_000
    /// أقل طول للضلع الأقصر؛ أصغر من ذلك لا يُقرأ نصه.
    var minSide: Int = 48
    /// الصورة تُصغَّر إلى هذا الضلع الأطول قبل الاستخراج حتى تبقى الذاكرة محدودة.
    var workingMaxSide: Int = 4_096

    static let standard = ScreenshotLimits()

    func validate(byteCount: Int) throws {
        guard byteCount > 0 else { throw ScreenshotTextError.unreadableImage }
        guard byteCount <= maxBytes else { throw ScreenshotTextError.fileTooLarge }
    }

    /// يفحص حجم ملف على القرص **من خصائصه فقط** دون فتحه أو قراءة محتواه.
    /// ملف مفقود أو لا يمكن قراءة خصائصه ← loadFailed؛ ليس ملفًا عاديًا أو فارغ ← unreadableImage؛ أكبر من الحد ← fileTooLarge.
    func validate(fileAt url: URL) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw ScreenshotTextError.loadFailed
        }
        guard values.isRegularFile == true, let size = values.fileSize else { throw ScreenshotTextError.unreadableImage }
        try validate(byteCount: size)
    }

    func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw ScreenshotTextError.unreadableImage }
        guard min(width, height) >= minSide else { throw ScreenshotTextError.imageTooSmall }
        guard max(width, height) <= maxSide,
              width.multipliedReportingOverflow(by: height).partialValue <= maxPixels,
              !width.multipliedReportingOverflow(by: height).overflow
        else { throw ScreenshotTextError.dimensionsTooLarge }
    }
}

// MARK: - الأخطاء

enum ScreenshotTextError: Error, Equatable, Sendable {
    /// تعذر تحميل الصورة من مكتبة الصور.
    case loadFailed
    case fileTooLarge
    case dimensionsTooLarge
    case imageTooSmall
    /// ليست صورة يمكن فكها.
    case unreadableImage
    /// القارئ المحلي للعربية غير متاح على هذا الجهاز أو إصدار iOS.
    case arabicUnsupported
    case extractionFailed
    case noTextFound
    case noArabicText

    var message: String {
        switch self {
        case .loadFailed:
            return "تعذر فتح الصورة من مكتبة الصور. جرّب اختيارها مرة أخرى."
        case .fileTooLarge:
            return "حجم الصورة أكبر من المسموح (٢٥ ميجابايت). اختر لقطة شاشة أصغر أو قُصّها."
        case .dimensionsTooLarge:
            return "أبعاد الصورة كبيرة جدًا. اختر لقطة شاشة عادية أو قُصّها قبل اختيارها."
        case .imageTooSmall:
            return "الصورة صغيرة جدًا فلا يمكن قراءة نصها. اختر صورة أوضح."
        case .unreadableImage:
            return "تعذرت قراءة هذا الملف كصورة. اختر لقطة شاشة بصيغة PNG أو JPEG أو HEIC."
        case .arabicUnsupported:
            return "قراءة النص العربي من الصور غير متاحة على هذا الجهاز أو إصدار iOS. اكتب الاقتباس بنفسك."
        case .extractionFailed:
            return "تعذر استخراج النص من الصورة. حاول مرة أخرى أو اكتب الاقتباس بنفسك."
        case .noTextFound:
            return "لم يُعثر على نص في المنطقة المحددة. وسّع منطقة القص أو اختر صورة أوضح."
        case .noArabicText:
            return "لم يُعثر على نص عربي في المنطقة المحددة. حدّد منطقة الاقتباس أو اختر صورة أخرى."
        }
    }

    /// هل تفيد إعادة المحاولة على الصورة نفسها (بقص مختلف أو مرة أخرى)؟
    var canRetryOnSameImage: Bool {
        switch self {
        case .extractionFailed, .noTextFound, .noArabicText: return true
        default: return false
        }
    }
}

// MARK: - منطقة القص

/// مستطيل بإحداثيات نسبية (٠…١)، أصله أسفل اليسار كما في Apple Vision.
struct NormalizedRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }
}

/// منطقة الاقتباس كشريط أفقي يحدده المستخدم بين حدّ علوي وحدّ سفلي (نسبة من أعلى الصورة).
/// لقطات الشاشة يكون فيها الاقتباس عادة شريطًا أفقيًا، والمنزلقان يعملان مع VoiceOver.
struct CropBand: Equatable, Sendable {
    /// بداية المنطقة من أعلى الصورة (٠ = أعلى).
    private(set) var top: Double
    /// نهاية المنطقة من أعلى الصورة (١ = أسفل).
    private(set) var bottom: Double

    static let minimumHeight = 0.05
    static let full = CropBand(top: 0, bottom: 1)

    init(top: Double, bottom: Double) {
        var t = top.isFinite ? min(max(top, 0), 1) : 0
        var b = bottom.isFinite ? min(max(bottom, 0), 1) : 1
        if t > b { swap(&t, &b) }
        if b - t < Self.minimumHeight {
            b = min(1, t + Self.minimumHeight)
            t = b - Self.minimumHeight
        }
        self.top = t
        self.bottom = b
    }

    var isFull: Bool { top <= 0 && bottom >= 1 }

    /// يحرك الحد العلوي مع الحفاظ على أقل ارتفاع.
    func withTop(_ value: Double) -> CropBand {
        CropBand(top: min(value, bottom - Self.minimumHeight), bottom: bottom)
    }

    /// يحرك الحد السفلي مع الحفاظ على أقل ارتفاع.
    func withBottom(_ value: Double) -> CropBand {
        CropBand(top: top, bottom: max(value, top + Self.minimumHeight))
    }

    /// منطقة الاهتمام بإحداثيات Vision (أصلها أسفل اليسار).
    var visionRegion: NormalizedRect {
        NormalizedRect(x: 0, y: 1 - bottom, width: 1, height: bottom - top)
    }
}

// MARK: - الأسطر المستخرجة

struct RecognizedLine: Equatable, Sendable {
    let text: String
    /// ثقة المحرك (٠…١)، أو nil إن لم يوفرها.
    let confidence: Double?
    /// موضع السطر بإحداثيات Vision النسبية (أصلها أسفل اليسار).
    let box: NormalizedRect
}

/// النص المجمّع مع مؤشرات الجودة.
struct ExtractedText: Equatable, Sendable {
    let text: String
    let lineCount: Int
    /// عدد الأسطر التي ثقتها أقل من الحد؛ تستدعي تنبيه المستخدم.
    let lowConfidenceLines: Int
}

/// يرتب الأسطر من أعلى إلى أسفل، ومن اليمين إلى اليسار داخل الصف الواحد (العربية)، ثم ينظفها.
enum ExtractedTextAssembler {
    static let lowConfidenceThreshold = 0.5

    static func assemble(_ lines: [RecognizedLine]) -> ExtractedText {
        let cleaned = lines.compactMap { line -> RecognizedLine? in
            let text = sanitize(line.text)
            return text.isEmpty ? nil : RecognizedLine(text: text, confidence: line.confidence, box: line.box)
        }

        // صفوف: الأسطر المتداخلة رأسيًا بأكثر من نصف ارتفاع أقصرها تُعد صفًا واحدًا.
        var rows: [[RecognizedLine]] = []
        for line in cleaned.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = rows.indices.last, belongsToRow(line, rows[index]) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        let text = rows
            .map { row in row.sorted(by: { $0.box.maxX > $1.box.maxX }).map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
        let low = cleaned.filter { ($0.confidence ?? 1) < lowConfidenceThreshold }.count
        return ExtractedText(text: text, lineCount: cleaned.count, lowConfidenceLines: low)
    }

    private static func belongsToRow(_ line: RecognizedLine, _ row: [RecognizedLine]) -> Bool {
        guard let reference = row.first else { return false }
        let overlap = min(line.box.maxY, reference.box.maxY) - max(line.box.minY, reference.box.minY)
        let shorter = min(line.box.height, reference.box.height)
        return shorter > 0 && overlap > shorter / 2
    }

    /// محارف لا تُرى (اتجاه وعرض صفري) لا مكان لها في نص مكتوب للبحث.
    static let invisibleScalars: Set<UInt32> = [
        0x200B, 0x200E, 0x200F, 0x061C, 0xFEFF,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    /// يزيل غير المرئي ويوحد المسافات داخل السطر؛ لا يغيّر الحروف ولا التشكيل.
    static func sanitize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !invisibleScalars.contains(scalar.value) {
            scalars.append(scalar)
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// هل في النص حرف عربي واحد على الأقل (لا تُحسب الأرقام وعلامات الترقيم)؟
    static func containsArabicLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            let arabicBlock = (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
                || (0x08A0...0x08FF).contains(v) || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
            return arabicBlock && scalar.properties.isAlphabetic
        }
    }
}

// MARK: - الصورة المجهزة

/// صورة مفكوكة ومصغرة جاهزة للاستخراج والمعاينة. لا تحمل بيانات الملف الأصلي.
/// `handle` هو صورة المنصة (CGImage على iOS)؛ تبقى في الذاكرة فقط ما دامت نافذة القراءة مفتوحة.
struct PreparedImage: @unchecked Sendable {
    let width: Int
    let height: Int
    let handle: AnyObject?
}

/// فك الصورة وفحص أبعادها وتصغيرها.
protocol ScreenshotImageProcessing: Sendable {
    func prepare(_ data: Data, limits: ScreenshotLimits) throws -> PreparedImage
    /// يفك نسخة مصغرة من ملف على القرص مباشرة (دون تحميله كله في الذاكرة).
    /// لا يُستدعى مباشرة؛ `prepare(fileAt:limits:)` يفحص حجم الملف قبله.
    func decodeFile(at url: URL, limits: ScreenshotLimits) throws -> PreparedImage
}

extension ScreenshotImageProcessing {
    /// صورة من ملف: الحجم أولًا من خصائص الملف (دون قراءة محتواه)، ثم فك نسخة مصغرة ضمن الحدود نفسها.
    /// لا يُنسخ الملف ولا يُحتفظ برابطه.
    func prepare(fileAt url: URL, limits: ScreenshotLimits) throws -> PreparedImage {
        try limits.validate(fileAt: url)
        return try decodeFile(at: url, limits: limits)
    }

    /// للمضاعفات والمنصات بلا ImageIO: يقرأ الملف (بعد فحص حجمه) ثم يمر بالمسار نفسه.
    /// ImageIOScreenshotProcessor يستبدله بفك مباشر من الملف.
    func decodeFile(at url: URL, limits: ScreenshotLimits) throws -> PreparedImage {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ScreenshotTextError.loadFailed }
        return try prepare(data, limits: limits)
    }
}

/// قارئ نص عربي محلي.
protocol ArabicTextRecognizing: Sendable {
    /// يُفحص فعليًا على الجهاز (لا يُفترض).
    var isArabicSupported: Bool { get }
    /// اسم المحرك للعرض والتوثيق (مثل «Apple Vision»).
    var engineName: String { get }
    func recognizeLines(in image: PreparedImage, region: NormalizedRect) async throws -> [RecognizedLine]
}
