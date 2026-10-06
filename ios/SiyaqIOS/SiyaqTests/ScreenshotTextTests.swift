import XCTest
import Foundation
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif
@testable import Siyaq

/// قراءة اقتباس من صورة: الحدود، القص، ترتيب الأسطر من اليمين، التنظيف، والحالات والأخطاء والإلغاء.
/// مضاعفات معزولة: لا صور حقيقية ولا Vision هنا (تلك في VisionArabicTests على Xcode).
/// نصوص الاختبار تقنية: كلمات من اقتباس المستخدم المثال «لا تقربوا الصلاة» فقط، لا موارد علمية.
final class ScreenshotTextModelTests: XCTestCase {

    // MARK: الحدود

    func testByteLimits() {
        let limits = ScreenshotLimits.standard
        XCTAssertNoThrow(try limits.validate(byteCount: 1))
        XCTAssertNoThrow(try limits.validate(byteCount: limits.maxBytes))
        XCTAssertThrowsError(try limits.validate(byteCount: limits.maxBytes + 1)) { XCTAssertEqual($0 as? ScreenshotTextError, .fileTooLarge) }
        XCTAssertThrowsError(try limits.validate(byteCount: 0)) { XCTAssertEqual($0 as? ScreenshotTextError, .unreadableImage) }
    }

    func testDimensionLimits() {
        let limits = ScreenshotLimits.standard
        XCTAssertNoThrow(try limits.validate(width: 1290, height: 2796), "لقطة شاشة آيفون")
        XCTAssertNoThrow(try limits.validate(width: 48, height: 48))
        XCTAssertThrowsError(try limits.validate(width: 47, height: 2000)) { XCTAssertEqual($0 as? ScreenshotTextError, .imageTooSmall) }
        XCTAssertThrowsError(try limits.validate(width: 12_001, height: 100)) { XCTAssertEqual($0 as? ScreenshotTextError, .dimensionsTooLarge) }
        XCTAssertThrowsError(try limits.validate(width: 8_000, height: 8_000)) { XCTAssertEqual($0 as? ScreenshotTextError, .dimensionsTooLarge) }
        XCTAssertThrowsError(try limits.validate(width: Int.max, height: Int.max)) { XCTAssertEqual($0 as? ScreenshotTextError, .dimensionsTooLarge) }
        XCTAssertThrowsError(try limits.validate(width: 0, height: 10)) { XCTAssertEqual($0 as? ScreenshotTextError, .unreadableImage) }
    }

    // MARK: القص

    func testCropBandClampsAndKeepsMinimumHeight() {
        XCTAssertEqual(CropBand(top: -1, bottom: 2), .full)
        XCTAssertEqual(CropBand(top: 0.8, bottom: 0.2), CropBand(top: 0.2, bottom: 0.8), "يُبدَّل الحدان")
        let thin = CropBand(top: 0.5, bottom: 0.51)
        XCTAssertEqual(thin.bottom - thin.top, CropBand.minimumHeight, accuracy: 1e-9)
        let atEnd = CropBand(top: 1, bottom: 1)
        XCTAssertEqual(atEnd.bottom, 1)
        XCTAssertEqual(atEnd.top, 1 - CropBand.minimumHeight, accuracy: 1e-9)
        XCTAssertEqual(CropBand(top: .nan, bottom: .infinity), .full)

        let band = CropBand(top: 0.3, bottom: 0.6)
        XCTAssertEqual(band.withTop(0.9).top, 0.6 - CropBand.minimumHeight, accuracy: 1e-9, "الحد العلوي لا يتجاوز السفلي")
        XCTAssertEqual(band.withBottom(0.1).bottom, 0.3 + CropBand.minimumHeight, accuracy: 1e-9)
    }

    /// Vision أصله أسفل اليسار: شريط من ٢٠٪ إلى ٤٠٪ من الأعلى = y من ٠٫٦ بارتفاع ٠٫٢.
    func testCropBandMapsToVisionRegion() {
        let region = CropBand(top: 0.2, bottom: 0.4).visionRegion
        XCTAssertEqual(region.x, 0)
        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.y, 0.6, accuracy: 1e-9)
        XCTAssertEqual(region.height, 0.2, accuracy: 1e-9)
        XCTAssertEqual(CropBand.full.visionRegion, .full)
    }

    // MARK: الترتيب من اليمين والتنظيف

    private func line(_ text: String, x: Double, y: Double, w: Double = 0.3, h: Double = 0.05, c: Double? = 0.9) -> RecognizedLine {
        RecognizedLine(text: text, confidence: c, box: NormalizedRect(x: x, y: y, width: w, height: h))
    }

    /// صف واحد من جزأين: الأيمن أولًا. ثم الصف التالي تحته.
    func testRightToLeftWithinRowAndTopToBottomAcrossRows() {
        let lines = [
            line("الصلاة", x: 0.1, y: 0.80),   // يسار الصف الأول
            line("ثالث", x: 0.5, y: 0.50),
            line("لا تقربوا", x: 0.6, y: 0.81), // يمين الصف الأول (متداخل رأسيًا)
        ]
        let extracted = ExtractedTextAssembler.assemble(lines)
        XCTAssertEqual(extracted.text, "لا تقربوا الصلاة\nثالث")
        XCTAssertEqual(extracted.lineCount, 3)
    }

    func testSanitizeRemovesInvisibleAndKeepsLettersAndDiacritics() {
        let withMarks = "\u{200F}لَا\u{200B}  تَقْرَبُوا\u{202B}\u{FEFF}\tالصَّلَاةَ\u{2069}"
        let clean = ExtractedTextAssembler.sanitize(withMarks)
        XCTAssertEqual(clean, "لَا تَقْرَبُوا الصَّلَاةَ")
        // التشكيل باقٍ بايتًا بايتًا: لا تطبيع ولا حذف.
        XCTAssertTrue(Data(clean.utf8).range(of: Data("الصَّلَاةَ".utf8)) != nil)
        XCTAssertEqual(ExtractedTextAssembler.sanitize(" \u{200E} "), "")
    }

    func testEmptyLinesAreDroppedAndLowConfidenceIsCounted() {
        let extracted = ExtractedTextAssembler.assemble([
            line(" \u{200F} ", x: 0.1, y: 0.9),
            line("لا تقربوا", x: 0.5, y: 0.7, c: 0.3),
            line("الصلاة", x: 0.5, y: 0.5, c: nil),
        ])
        XCTAssertEqual(extracted.text, "لا تقربوا\nالصلاة")
        XCTAssertEqual(extracted.lowConfidenceLines, 1)
    }

    func testArabicDetection() {
        XCTAssertTrue(ExtractedTextAssembler.containsArabicLetters("لا"))
        XCTAssertTrue(ExtractedTextAssembler.containsArabicLetters("Surah ٤٣ لا"))
        XCTAssertFalse(ExtractedTextAssembler.containsArabicLetters("Quran 4:43"))
        XCTAssertFalse(ExtractedTextAssembler.containsArabicLetters("٤٣ ، ؟ \u{FEFF}"), "أرقام وعلامات فقط")
    }

    // MARK: الرسائل

    func testEveryErrorHasAnArabicMessage() {
        let all: [ScreenshotTextError] = [.loadFailed, .fileTooLarge, .dimensionsTooLarge, .imageTooSmall, .unreadableImage,
                                          .arabicUnsupported, .extractionFailed, .noTextFound, .noArabicText]
        for error in all {
            XCTAssertTrue(ExtractedTextAssembler.containsArabicLetters(error.message), "\(error)")
            XCTAssertFalse(error.message.contains("OCR"), "لا مصطلحات إنجليزية للمستخدم")
        }
        XCTAssertTrue(ScreenshotTextError.noTextFound.canRetryOnSameImage)
        XCTAssertFalse(ScreenshotTextError.fileTooLarge.canRetryOnSameImage)
    }
}

// MARK: - المتحكم

/// معالج صور مزيف: يقرأ الأبعاد من نص «WxH» ويرفض غيره.
private struct FakeProcessor: ScreenshotImageProcessing {
    final class Counter: @unchecked Sendable { var calls = 0; let lock = NSLock() }
    let counter = Counter()
    func prepare(_ data: Data, limits: ScreenshotLimits) throws -> PreparedImage {
        counter.lock.withLock { counter.calls += 1 }
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { throw ScreenshotTextError.unreadableImage }
        try limits.validate(width: parts[0], height: parts[1])
        return PreparedImage(width: parts[0], height: parts[1], handle: nil)
    }
}

/// قارئ مزيف بخطوات مؤقتة؛ يسجل المناطق المطلوبة.
private final class FakeRecognizer: ArabicTextRecognizing, @unchecked Sendable {
    struct Step { let delay: Duration; let result: Result<[RecognizedLine], Error> }
    let isArabicSupported: Bool
    let engineName = "مضاعف اختبار"
    private let lock = NSLock()
    private var steps: [Step]
    private(set) var regions: [NormalizedRect] = []

    init(supported: Bool = true, _ steps: [Step] = []) {
        isArabicSupported = supported
        self.steps = steps
    }

    func recognizeLines(in image: PreparedImage, region: NormalizedRect) async throws -> [RecognizedLine] {
        let step: Step = lock.withLock {
            regions.append(region)
            return steps.isEmpty ? Step(delay: .zero, result: .success([])) : steps.removeFirst()
        }
        try await Task.sleep(for: step.delay)
        return try step.result.get()
    }
}

private func lines(_ texts: String...) -> [RecognizedLine] {
    texts.enumerated().map { index, text in
        RecognizedLine(text: text, confidence: 0.9, box: NormalizedRect(x: 0.1, y: 0.9 - Double(index) * 0.1, width: 0.8, height: 0.05))
    }
}

private let screenshot = Data("1290x2796".utf8)

@MainActor
final class ScreenshotTextControllerTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func ready(_ recognizer: FakeRecognizer, processor: FakeProcessor = FakeProcessor()) async -> ScreenshotTextController {
        let controller = ScreenshotTextController(recognizer: recognizer, processor: processor)
        controller.load { screenshot }
        await waitUntil { controller.phase != .loadingImage }
        return controller
    }

    /// المسار الكامل: صورة ← قص ← استخراج ← مسودة قابلة للتعديل؛ ولا بحث تلقائي.
    func testHappyPathProducesEditableDraftWithoutStartingReview() async {
        let recognizer = FakeRecognizer([.init(delay: .zero, result: .success(lines("لا تقربوا", "الصلاة")))])
        let controller = await ready(recognizer)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertTrue(controller.hasImage)

        controller.crop = CropBand(top: 0.2, bottom: 0.5)
        controller.extract()
        XCTAssertEqual(controller.phase, .extracting)
        await waitUntil { controller.phase != .extracting }
        XCTAssertEqual(controller.phase, .extracted)
        XCTAssertEqual(controller.draft, "لا تقربوا\nالصلاة")
        XCTAssertEqual(recognizer.regions, [CropBand(top: 0.2, bottom: 0.5).visionRegion], "الاستخراج من منطقة القص فقط")

        controller.draft = "لا تقربوا الصلاة  "
        XCTAssertEqual(controller.acceptedText, "لا تقربوا الصلاة")

        let session = ReviewSession()
        session.inputError = .emptyQuote
        session.useExtractedText(controller.acceptedText!)
        XCTAssertEqual(session.input, "لا تقربوا الصلاة")
        XCTAssertNil(session.inputError)
        XCTAssertEqual(session.primary, .idle, "لا يبدأ البحث تلقائيًا")
        XCTAssertEqual(session.submittedQuote, "")

        controller.discard()
        XCTAssertFalse(controller.hasImage, "الصورة تُترك عند الإغلاق")
        XCTAssertEqual(controller.draft, "")
        XCTAssertEqual(controller.phase, .idle)
    }

    /// المتحكم لا يملك أي خاصية تحمل بيانات الملف الأصلي.
    func testControllerNeverStoresOriginalImageData() async {
        let controller = await ready(FakeRecognizer())
        let stored = Mirror(reflecting: controller).children.filter {
            let type = Swift.type(of: $0.value)
            return type == Data.self || type == Optional<Data>.self || type == [Data].self
        }
        XCTAssertFalse(Mirror(reflecting: controller).children.isEmpty, "الانعكاس يرى الخصائص")
        XCTAssertTrue(stored.isEmpty, "بيانات الصورة الأصلية لا تُخزَّن")
    }

    func testUnsupportedArabicNeverLoadsAnImage() async {
        let processor = FakeProcessor()
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(supported: false), processor: processor)
        XCTAssertEqual(controller.phase, .unavailable)
        controller.load { screenshot }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.phase, .unavailable)
        XCTAssertEqual(processor.counter.calls, 0)
        XCTAssertEqual(ScreenshotTextController(recognizer: nil, processor: processor).phase, .unavailable, "لا قارئ إطلاقًا")
    }

    func testPickerCancelReturnsToIdle() async {
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: FakeProcessor())
        controller.load { nil }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(controller.hasImage)
    }

    func testOversizedFileIsRejectedBeforeDecoding() async {
        let processor = FakeProcessor()
        let limits = ScreenshotLimits(maxBytes: 4)
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: processor, limits: limits)
        controller.load { screenshot }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .failed(.fileTooLarge))
        XCTAssertEqual(processor.counter.calls, 0, "لا فك لملف أكبر من الحد")
    }

    func testUnreadableAndOversizedDimensionsAndLoadFailure() async {
        for (data, expected) in [(Data("garbage".utf8), ScreenshotTextError.unreadableImage),
                                 (Data("20000x100".utf8), .dimensionsTooLarge),
                                 (Data("10x10".utf8), .imageTooSmall)] {
            let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: FakeProcessor())
            controller.load { data }
            await waitUntil { controller.phase != .loadingImage }
            XCTAssertEqual(controller.phase, .failed(expected))
            XCTAssertFalse(controller.hasImage)
        }
        struct Boom: Error {}
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: FakeProcessor())
        controller.load { throw Boom() }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .failed(.loadFailed))
    }

    func testExtractionFailuresAreHonestAndRetryable() async {
        struct Boom: Error {}
        let cases: [(Result<[RecognizedLine], Error>, ScreenshotTextError)] = [
            (.failure(Boom()), .extractionFailed),
            (.success([]), .noTextFound),
            (.success(lines(" \u{200F} ")), .noTextFound),
            (.success(lines("Quran 4:43")), .noArabicText),
        ]
        for (result, expected) in cases {
            let recognizer = FakeRecognizer([.init(delay: .zero, result: result),
                                             .init(delay: .zero, result: .success(lines("الصلاة")))])
            let controller = await ready(recognizer)
            controller.extract()
            await waitUntil { controller.phase != .extracting }
            XCTAssertEqual(controller.phase, .failed(expected))
            XCTAssertEqual(controller.draft, "", "لا مسودة عند الفشل")
            XCTAssertNil(controller.acceptedText)

            // إعادة المحاولة على الصورة نفسها (بعد توسيع القص مثلًا).
            controller.extract()
            await waitUntil { controller.phase != .extracting }
            XCTAssertEqual(controller.phase, .extracted)
            XCTAssertEqual(controller.draft, "الصلاة")
        }
    }

    /// إيقاف أثناء الاستخراج: يعود للقص، والنتيجة المتأخرة لا تظهر.
    func testCancelDuringExtractionIgnoresLateResult() async throws {
        let recognizer = FakeRecognizer([.init(delay: .milliseconds(200), result: .success(lines("متأخر")))])
        let controller = await ready(recognizer)
        controller.extract()
        controller.cancel()
        XCTAssertEqual(controller.phase, .ready)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.draft, "")
    }

    /// صورة جديدة أثناء استخراج الأقدم: النتيجة القديمة لا تستبدل الأحدث.
    func testNewImageDuringExtractionWinsOverStaleResult() async throws {
        let recognizer = FakeRecognizer([
            .init(delay: .milliseconds(250), result: .success(lines("قديم"))),
            .init(delay: .milliseconds(10), result: .success(lines("جديد"))),
        ])
        let controller = await ready(recognizer)
        controller.extract()
        controller.load { Data("1170x2532".utf8) }
        await waitUntil { controller.phase == .ready }
        XCTAssertEqual(controller.image?.width, 1170)
        controller.extract()
        await waitUntil { controller.phase == .extracted }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(controller.draft, "جديد")
        XCTAssertEqual(controller.phase, .extracted)
    }

    /// صورة أحدث تُختار أثناء تحميل أبطأ: الأبطأ لا يستبدلها.
    func testSlowOlderLoadDoesNotReplaceNewerImage() async throws {
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: FakeProcessor())
        controller.load {
            try await Task.sleep(for: .milliseconds(200))
            return Data("1290x2796".utf8)
        }
        controller.load { Data("1170x2532".utf8) }
        await waitUntil { controller.phase == .ready }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.image?.width, 1170)
    }

    func testRepeatedExtractTapsStartOneExtraction() async {
        let recognizer = FakeRecognizer([.init(delay: .milliseconds(100), result: .success(lines("الصلاة")))])
        let controller = await ready(recognizer)
        for _ in 0..<5 { controller.extract() }
        await waitUntil { controller.phase != .extracting }
        XCTAssertEqual(recognizer.regions.count, 1)
        XCTAssertEqual(controller.phase, .extracted)
    }

    /// المسودة التي عدّلها المستخدم لا يستبدلها شيء دون طلبه؛ الرجوع للقص يمسحها صراحة.
    func testUserEditsAreKeptUntilExplicitReextract() async {
        let recognizer = FakeRecognizer([.init(delay: .zero, result: .success(lines("لا تقربوا")))])
        let controller = await ready(recognizer)
        controller.extract()
        await waitUntil { controller.phase == .extracted }
        controller.draft = "لا تقربوا الصلاة"
        controller.extract() // ليس في حالة ready: لا استخراج جديد يكتب فوق التعديل
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.draft, "لا تقربوا الصلاة")
        XCTAssertEqual(recognizer.regions.count, 1)

        controller.backToCrop()
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.draft, "")
    }

    func testEmptyDraftIsNotAccepted() async {
        let recognizer = FakeRecognizer([.init(delay: .zero, result: .success(lines("الصلاة")))])
        let controller = await ready(recognizer)
        controller.extract()
        await waitUntil { controller.phase == .extracted }
        controller.draft = " \n "
        XCTAssertNil(controller.acceptedText)
    }

    /// قراءة الصورة لا تكتب شيئًا في المحفوظات.
    func testExtractionWritesNothingToSavedResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SiyaqOCR-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedResultsStore(directory: directory)
        let recognizer = FakeRecognizer([.init(delay: .zero, result: .success(lines("الصلاة")))])
        let controller = await ready(recognizer)
        controller.extract()
        await waitUntil { controller.phase == .extracted }
        controller.discard()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "لا ملفات")
    }
}

// MARK: - صورة من ملف (منتقي الصور): الحجم قبل أي قراءة، ثم فك مصغر

/// معالج يعدّ مرات فك الملف؛ يقرأ الأبعاد من نص «WxH» داخل الملف (عبر FakeProcessor).
private final class FileSpyProcessor: ScreenshotImageProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var decodeCount = 0
    var decodes: Int { lock.withLock { decodeCount } }

    func prepare(_ data: Data, limits: ScreenshotLimits) throws -> PreparedImage {
        try FakeProcessor().prepare(data, limits: limits)
    }

    func decodeFile(at url: URL, limits: ScreenshotLimits) throws -> PreparedImage {
        lock.withLock { decodeCount += 1 }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ScreenshotTextError.loadFailed }
        return try prepare(data, limits: limits)
    }
}

/// مجلد مؤقت لكل اختبار يُحذف بعده.
private final class TempFiles {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SiyaqOCRFile-\(UUID().uuidString)", isDirectory: true)

    init() { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }

    func file(_ name: String, _ contents: Data) -> URL {
        let url = root.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: contents)
        return url
    }

    /// ملف متفرق بالحجم المطلوب: لا يُكتب محتواه ولا يُحمّل في الذاكرة.
    func sparse(_ name: String, size: Int) throws -> URL {
        let url = file(name, Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return url
    }

    func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func expectError(_ expected: ScreenshotTextError, file: StaticString = #filePath, line: UInt = #line,
                         _ body: () throws -> PreparedImage) {
    XCTAssertThrowsError(try body(), file: file, line: line) {
        XCTAssertEqual($0 as? ScreenshotTextError, expected, file: file, line: line)
    }
}

final class ScreenshotFileLimitTests: XCTestCase {
    private var files: TempFiles!
    override func setUp() { files = TempFiles() }
    override func tearDown() { files.remove() }

    /// ملف أكبر من الحد يُرفض من خصائصه: لا فك ولا قراءة، حتى لو كان محتواه غير قابل للقراءة أصلًا.
    func testOversizedFileIsRejectedBeforeAnyRead() throws {
        let spy = FileSpyProcessor()
        let limits = ScreenshotLimits.standard
        let big = try files.sparse("big.heic", size: limits.maxBytes + 1)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: big.path) // المحتوى مقفل
        expectError(.fileTooLarge) { try spy.prepare(fileAt: big, limits: limits) }
        XCTAssertEqual(spy.decodes, 0, "لم يُفك الملف ولم يُقرأ")
    }

    /// الحد بالبايت: عند الحد يُفك، وبعده بايت واحد يُرفض قبل الفك.
    func testFileSizeBoundaryIsExact() throws {
        let spy = FileSpyProcessor()
        let shot = files.file("shot.png", Data("1290x2796".utf8)) // ٩ بايتات
        var limits = ScreenshotLimits.standard
        limits.maxBytes = 9
        XCTAssertEqual(try spy.prepare(fileAt: shot, limits: limits).width, 1290)
        limits.maxBytes = 8
        expectError(.fileTooLarge) { try spy.prepare(fileAt: shot, limits: limits) }
        XCTAssertEqual(spy.decodes, 1)
    }

    func testEmptyMissingAndDirectoryAreRejectedWithoutDecoding() throws {
        let spy = FileSpyProcessor()
        expectError(.unreadableImage) { try spy.prepare(fileAt: self.files.file("empty.png", Data()), limits: .standard) }
        expectError(.loadFailed) { try spy.prepare(fileAt: self.files.root.appendingPathComponent("missing.png"), limits: .standard) }
        let folder = files.root.appendingPathComponent("folder.png", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        expectError(.unreadableImage) { try spy.prepare(fileAt: folder, limits: .standard) }
        XCTAssertEqual(spy.decodes, 0)
    }

    /// ملف تالف أو بأبعاد خارج الحدود: يُفك ويُرفض برسالة صادقة.
    func testCorruptAndOversizedDimensionFiles() {
        let spy = FileSpyProcessor()
        expectError(.unreadableImage) { try spy.prepare(fileAt: self.files.file("corrupt.png", Data("siyaq-not-an-image".utf8)), limits: .standard) }
        expectError(.dimensionsTooLarge) { try spy.prepare(fileAt: self.files.file("wide.png", Data("20000x100".utf8)), limits: .standard) }
        expectError(.imageTooSmall) { try spy.prepare(fileAt: self.files.file("tiny.png", Data("20x20".utf8)), limits: .standard) }
    }

    /// فك صورة من ملف لا ينسخه ولا يعدّله ولا يكتب شيئًا بجواره.
    func testPreparingAFileNeitherCopiesNorChangesIt() throws {
        let contents = Data("1290x2796".utf8)
        let shot = files.file("shot.png", contents)
        let before = files.listing()
        _ = try FileSpyProcessor().prepare(fileAt: shot, limits: .standard)
        XCTAssertEqual(files.listing(), before)
        XCTAssertEqual(try Data(contentsOf: shot), contents)
    }

    /// على منصة بلا ImageIO: الحجم يُفحص أولًا، ثم «غير مقروءة» بصدق.
    func testPlatformWithoutImageIOStillChecksSizeFirst() throws {
        #if !canImport(ImageIO)
        let processor = ScreenshotTextEngines.imageProcessor()
        let big = try files.sparse("big.png", size: ScreenshotLimits.standard.maxBytes + 1)
        expectError(.fileTooLarge) { try processor.prepare(fileAt: big, limits: .standard) }
        expectError(.unreadableImage) { try processor.prepare(fileAt: self.files.file("shot.png", Data("1290x2796".utf8)), limits: .standard) }
        #endif
    }
}

/// المتحكم مع صورة يجهزها المحمِّل من ملف (مسار منتقي الصور): الحالات والإلغاء والإغلاق وتبديل الصور.
@MainActor
final class ScreenshotPickedFileControllerTests: XCTestCase {
    private var files: TempFiles!
    override func setUp() async throws { files = TempFiles() }
    override func tearDown() async throws { files.remove() }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// محمِّل لا يحترم الإلغاء (مثل استلام النظام للملف): ينتظر في مهمة منفصلة ثم يفك الملف.
    private func slowPick(_ url: URL, _ spy: FileSpyProcessor, delay: Duration = .milliseconds(200)) -> @Sendable () async throws -> PreparedImage? {
        {
            await Task.detached { try? await Task.sleep(for: delay) }.value
            return try spy.prepare(fileAt: url, limits: .standard)
        }
    }

    func testPickedFileReachesReadyThenExtractsWithoutStartingReview() async {
        let spy = FileSpyProcessor()
        let shot = files.file("shot.png", Data("1290x2796".utf8))
        let controller = ScreenshotTextController(
            recognizer: FakeRecognizer([.init(delay: .zero, result: .success(lines("لا تقربوا الصلاة")))]), processor: spy)
        controller.loadPrepared { try spy.prepare(fileAt: shot, limits: .standard) }
        XCTAssertEqual(controller.phase, .loadingImage)
        await waitUntil { controller.phase == .ready }
        XCTAssertEqual(controller.image?.width, 1290)
        controller.extract()
        await waitUntil { controller.phase == .extracted }
        XCTAssertEqual(controller.acceptedText, "لا تقربوا الصلاة")
    }

    func testOversizedPickedFileFailsWithoutDecoding() async throws {
        let spy = FileSpyProcessor()
        let big = try files.sparse("big.heic", size: ScreenshotLimits.standard.maxBytes + 1)
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: spy)
        controller.loadPrepared { try spy.prepare(fileAt: big, limits: .standard) }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .failed(.fileTooLarge))
        XCTAssertNil(controller.image)
        XCTAssertEqual(spy.decodes, 0)
    }

    /// ملف تالف: خطأ صادق، ثم اختيار صورة سليمة يعمل.
    func testCorruptPickedFileFailsHonestlyAndAnotherPickRecovers() async {
        let spy = FileSpyProcessor()
        let corrupt = files.file("corrupt.png", Data("siyaq-not-an-image".utf8))
        let good = files.file("good.png", Data("1170x2532".utf8))
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: spy)
        controller.loadPrepared { try spy.prepare(fileAt: corrupt, limits: .standard) }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .failed(.unreadableImage))
        XCTAssertFalse(controller.hasImage)
        controller.loadPrepared { try spy.prepare(fileAt: good, limits: .standard) }
        await waitUntil { controller.phase == .ready }
        XCTAssertEqual(controller.image?.width, 1170)
    }

    /// «إيقاف» أثناء التحميل: يعود فورًا، والنتيجة المتأخرة تُهمل.
    func testCancelDuringPickedLoadIgnoresLateResult() async throws {
        let spy = FileSpyProcessor()
        let shot = files.file("shot.png", Data("1290x2796".utf8))
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: spy)
        controller.loadPrepared(slowPick(shot, spy))
        try await Task.sleep(for: .milliseconds(30))
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(spy.decodes, 1, "المحمِّل أكمل فعلًا (لا يحترم الإلغاء)")
        XCTAssertEqual(controller.phase, .idle, "النتيجة المتأخرة لم تُعرض")
        XCTAssertNil(controller.image)
    }

    /// إغلاق النافذة أثناء التحميل: لا صورة تبقى ولا تعود بعده.
    func testCloseDuringPickedLoadIgnoresLateResult() async throws {
        let spy = FileSpyProcessor()
        let shot = files.file("shot.png", Data("1290x2796".utf8))
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: spy)
        controller.loadPrepared(slowPick(shot, spy))
        try await Task.sleep(for: .milliseconds(30))
        controller.discard()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.image)
    }

    /// صورة أحدث تُختار أثناء تحميل أبطأ: الأبطأ (نجح أو فشل) لا يستبدلها.
    func testNewerPickWinsOverSlowerOlderResultOrError() async throws {
        let spy = FileSpyProcessor()
        let older = files.file("older.png", Data("1290x2796".utf8))
        let olderBig = try files.sparse("older-big.heic", size: ScreenshotLimits.standard.maxBytes + 1)
        let newer = files.file("newer.png", Data("1170x2532".utf8))
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: spy)

        controller.loadPrepared(slowPick(older, spy))
        controller.loadPrepared { try spy.prepare(fileAt: newer, limits: .standard) }
        await waitUntil { controller.phase == .ready }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(controller.image?.width, 1170, "نجاح الأقدم لم يستبدل الأحدث")

        controller.loadPrepared(slowPick(olderBig, spy))
        controller.loadPrepared { try spy.prepare(fileAt: newer, limits: .standard) }
        await waitUntil { controller.phase == .ready }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(controller.phase, .ready, "خطأ الأقدم لم يستبدل الأحدث")
        XCTAssertEqual(controller.image?.width, 1170)
    }

    /// صورة جديدة أثناء الاستخراج: الاستخراج القديم يُهمل ولا يكتب مسودة على الصورة الجديدة.
    func testNewPickDuringExtractionDropsStaleDraft() async throws {
        let spy = FileSpyProcessor()
        let first = files.file("first.png", Data("1290x2796".utf8))
        let second = files.file("second.png", Data("1170x2532".utf8))
        let recognizer = FakeRecognizer([.init(delay: .milliseconds(200), result: .success(lines("لا تقربوا")))])
        let controller = ScreenshotTextController(recognizer: recognizer, processor: spy)
        controller.loadPrepared { try spy.prepare(fileAt: first, limits: .standard) }
        await waitUntil { controller.phase == .ready }
        controller.extract()
        XCTAssertEqual(controller.phase, .extracting)
        controller.loadPrepared { try spy.prepare(fileAt: second, limits: .standard) }
        await waitUntil { controller.phase == .ready }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.image?.width, 1170)
        XCTAssertEqual(controller.draft, "")
    }

    /// المحمِّل يعيد nil (ألغى المستخدم): عودة إلى البداية بلا خطأ.
    func testNilPickReturnsToIdle() async {
        let controller = ScreenshotTextController(recognizer: FakeRecognizer(), processor: FileSpyProcessor())
        controller.loadPrepared { nil }
        await waitUntil { controller.phase != .loadingImage }
        XCTAssertEqual(controller.phase, .idle)
    }
}

#if canImport(ImageIO) && canImport(CoreGraphics)
/// المعالج الحقيقي (ImageIO) على ملفات حقيقية — يعمل على Xcode/macOS فقط، لم يُشغَّل على Linux.
final class ImageIOFileProcessorTests: XCTestCase {
    private var files: TempFiles!
    override func setUp() { files = TempFiles() }
    override func tearDown() { files.remove() }

    /// يرسم صورة بيضاء بخط أسود عرضي ويكتبها PNG إلى ملف.
    private func png(_ name: String, width: Int, height: Int) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: max(1, height / 10)))
        let image = try XCTUnwrap(context.makeImage())
        let url = files.root.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// صورة أعرض من حد العمل: تُفك من الملف نسخةً مصغرة ضلعها الأطول ٤٠٩٦، بالنسبة نفسها.
    func testFileDecodesToBoundedThumbnail() throws {
        let url = try png("wide.png", width: 6000, height: 400)
        let prepared = try ImageIOScreenshotProcessor().prepare(fileAt: url, limits: .standard)
        XCTAssertEqual(prepared.width, ScreenshotLimits.standard.workingMaxSide)
        XCTAssertEqual(Double(prepared.height), Double(400 * 4096) / 6000, accuracy: 2)
        XCTAssertNotNil(prepared.handle)
        let fromData = try ImageIOScreenshotProcessor().prepare(Data(contentsOf: url), limits: .standard)
        XCTAssertEqual(fromData.width, prepared.width, "المساران يعطيان النتيجة نفسها")
        XCTAssertEqual(fromData.height, prepared.height)
    }

    func testCorruptAndTruncatedFilesAreUnreadable() throws {
        expectError(.unreadableImage) {
            try ImageIOScreenshotProcessor().prepare(fileAt: self.files.file("corrupt.png", Data("siyaq-not-an-image".utf8)), limits: .standard)
        }
        let valid = try Data(contentsOf: png("valid.png", width: 600, height: 300))
        let header = files.file("header-only.png", valid.prefix(20)) // التوقيع وبداية ترويسة ناقصة
        expectError(.unreadableImage) { try ImageIOScreenshotProcessor().prepare(fileAt: header, limits: .standard) }
    }

    func testOversizedDimensionsAndBytesAreRejected() throws {
        let tooWide = try png("too-wide.png", width: 13_000, height: 60) // أطول من ١٢٠٠٠
        expectError(.dimensionsTooLarge) { try ImageIOScreenshotProcessor().prepare(fileAt: tooWide, limits: .standard) }
        let big = try files.sparse("big.heic", size: ScreenshotLimits.standard.maxBytes + 1)
        expectError(.fileTooLarge) { try ImageIOScreenshotProcessor().prepare(fileAt: big, limits: .standard) }
    }
}
#endif

#if DEBUG
/// تهيئة اختبارات الواجهة لقراءة الصور: Debug فقط، وقيمة مجهولة تُتجاهل.
final class ScreenshotFixtureSandboxTests: XCTestCase {
    func testOCRFixtureIsParsedOnlyInsideTheSandbox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SiyaqOCRSandbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "ocr-\(UUID().uuidString.prefix(8))"
        for (raw, expected) in [("sample", UITestSandbox.OCRFixture.sample), ("unreadable", .unreadable), ("unsupported", .unsupported)] {
            let config = try XCTUnwrap(UITestSandbox.configuration(
                environment: ["SIYAQ_UITEST_SANDBOX": name, "SIYAQ_UITEST_OCR": raw], applicationSupport: root))
            XCTAssertEqual(config.ocrFixture, expected)
            config.defaults.removePersistentDomain(forName: config.suiteName)
        }
        let unknown = try XCTUnwrap(UITestSandbox.configuration(
            environment: ["SIYAQ_UITEST_SANDBOX": name, "SIYAQ_UITEST_OCR": "camera"], applicationSupport: root))
        XCTAssertNil(unknown.ocrFixture)
        XCTAssertNil(UITestSandbox.configuration(environment: ["SIYAQ_UITEST_OCR": "sample"], applicationSupport: root),
                     "بلا مساحة اختبار لا تهيئة")
        unknown.defaults.removePersistentDomain(forName: unknown.suiteName)
    }

    /// على منصة بلا Vision/ImageIO (Linux): لا محرك، والمتحكم يعلن عدم التوفر بصدق.
    @MainActor
    func testNoEngineMeansHonestUnavailability() async {
        #if !canImport(Vision)
        XCTAssertNil(ScreenshotTextEngines.bestAvailable())
        XCTAssertThrowsError(try ScreenshotTextEngines.imageProcessor().prepare(Data([1, 2, 3]), limits: .standard))
        let controller = ScreenshotTextController(recognizer: ScreenshotTextEngines.bestAvailable(),
                                                  processor: ScreenshotTextEngines.imageProcessor())
        XCTAssertEqual(controller.phase, .unavailable)
        #endif
    }
}
#endif
