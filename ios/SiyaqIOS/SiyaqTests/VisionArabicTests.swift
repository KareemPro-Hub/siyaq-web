#if canImport(Vision) && canImport(UIKit) && DEBUG
import XCTest
import Vision
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Siyaq

/// فحص فعلي لدعم العربية في Apple Vision على الجهاز/المحاكي الذي تُشغَّل عليه الاختبارات (لا افتراض).
/// تُشغَّل على Xcode فقط؛ لم تُشغَّل على Linux. الصورة مولّدة في الذاكرة من اقتباس المستخدم المثال.
final class VisionArabicTests: XCTestCase {

    /// قياس مسار فك الصورة وOCR فقط؛ إنشاء عينة ٤٨ ميجابكسل خارج القياس.
    func test48MegapixelFileMemoryAndRepeatedArabicRecognition() throws {
        guard VisionArabicRecognizer().isArabicSupported else {
            throw XCTSkip("Vision لا يعلن العربية على هذا الجهاز")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let size = CGSize(width: 8064, height: 6048)
            let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.baseWritingDirection = .rightToLeft
                (ScreenshotTestSample.text as NSString).draw(
                    in: CGRect(x: 200, y: 2500, width: 7664, height: 1000),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 480), .foregroundColor: UIColor.black,
                                     .paragraphStyle: paragraph])
            }
            XCTAssertLessThan(data.count, ScreenshotLimits.standard.maxBytes)
            try data.write(to: url)
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric()], options: options) {
            let complete = expectation(description: "48MP Arabic OCR completed and image released")
            Task.detached(priority: .medium) {
                do {
                    let text = try await self.recognize48MPFile(at: url)
                    XCTAssertTrue(text.contains("الصلاة") || text.contains("تقربوا"), "النص: \(text)")
                } catch {
                    XCTFail("تعذر استخراج الصورة الكبيرة: \(error)")
                }
                complete.fulfill()
            }
            wait(for: [complete], timeout: 60)
        }
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func recognize48MPFile(at url: URL) async throws -> String {
        let prepared = try autoreleasepool {
            try ImageIOScreenshotProcessor().prepare(fileAt: url, limits: .standard)
        }
        XCTAssertEqual(prepared.width, 4096)
        XCTAssertEqual(prepared.height, 3072)
        let lines = try await VisionArabicRecognizer().recognizeLines(in: prepared, region: .full)
        return ExtractedTextAssembler.assemble(lines).text
    }

    func testRealHEICFileDownsamplesAndAppliesOrientation() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4032, height: 3024,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
        let url = try writeHEIC(try XCTUnwrap(context.makeImage()), orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        var limits = ScreenshotLimits.standard
        limits.workingMaxSide = 1024
        let checkedLimits = limits
        let prepared = try await Task.detached(priority: .medium) {
            try ImageIOScreenshotProcessor().prepare(fileAt: url, limits: checkedLimits)
        }.value
        XCTAssertEqual(prepared.width, 768)
        XCTAssertEqual(prepared.height, 1024)
    }

    func testActualFileLargerThan25MiBIsRejectedBeforeDecode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ScreenshotLimits.standard.maxBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try ImageIOScreenshotProcessor().prepare(fileAt: url, limits: .standard)) {
            XCTAssertEqual($0 as? ScreenshotTextError, .fileTooLarge)
        }
    }

    func testRealHEICArabicRemainsReadableAfterTemporaryFileRemoval() async throws {
        let recognizer = VisionArabicRecognizer()
        guard recognizer.isArabicSupported else { throw XCTSkip("Vision لا يعلن العربية على هذا الإصدار") }
        let image = try XCTUnwrap(UIImage(data: ScreenshotTestSample.pngData())?.cgImage)
        let url = try writeHEIC(image)
        defer { try? FileManager.default.removeItem(at: url) }
        let fixture = XCTAttachment(contentsOfFile: url)
        fixture.name = "عينة HEIC مولدة لاختبار مكتبة المحاكي"
        fixture.lifetime = .keepAlways
        add(fixture)
        // لا نفك HEIC على خيط الواجهة؛ الاختبار يحاكي استلام الملف في الخلفية.
        let prepared = try await Task.detached(priority: .medium) {
            try ImageIOScreenshotProcessor().prepare(fileAt: url, limits: .standard)
        }.value
        try FileManager.default.removeItem(at: url)
        let lines = try await recognizer.recognizeLines(in: prepared, region: .full)
        let text = ExtractedTextAssembler.assemble(lines).text
        XCTAssertTrue(text.contains("الصلاة") || text.contains("تقربوا"), "النص: \(text)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func writeHEIC(_ image: CGImage, orientation: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: orientation,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            XCTFail("تعذر إنشاء ملف HEIC حقيقي على هذا الجهاز")
            throw ScreenshotTextError.unreadableImage
        }
        return url
    }

    /// يسجل قائمة اللغات كما يعلنها Vision، ويتحقق أن المحرك يعتمد عليها هي لا على افتراض.
    func testArabicSupportIsReadFromTheDevice() {
        let languages = VisionArabicRecognizer.supportedLanguages()
        let attachment = XCTAttachment(string: "iOS \(UIDevice.current.systemVersion): " + languages.joined(separator: ", "))
        attachment.name = "Vision supportedRecognitionLanguages"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(languages.isEmpty, "Vision لم يعلن أي لغة")
        let arabic = languages.filter { $0.lowercased().hasPrefix("ar") }
        XCTAssertEqual(VisionArabicRecognizer().isArabicSupported, !arabic.isEmpty)
        XCTAssertEqual(VisionArabicRecognizer.arabicLanguages(), arabic)
    }

    /// استخراج حقيقي من صورة مولدة. يُتخطى (لا ينجح زورًا) إن لم يعلن الجهاز العربية.
    func testRecognizesRenderedArabicWhenSupported() async throws {
        let recognizer = VisionArabicRecognizer()
        guard recognizer.isArabicSupported else {
            throw XCTSkip("Vision على هذا الإصدار لا يعلن العربية: \(VisionArabicRecognizer.supportedLanguages())")
        }
        let prepared = try ImageIOScreenshotProcessor().prepare(ScreenshotTestSample.pngData(), limits: .standard)
        let lines = try await recognizer.recognizeLines(in: prepared, region: .full)
        let text = ExtractedTextAssembler.assemble(lines).text
        let attachment = XCTAttachment(string: text)
        attachment.name = "النص المستخرج"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(ExtractedTextAssembler.containsArabicLetters(text), "النص: \(text)")
        XCTAssertTrue(text.contains("الصلاة") || text.contains("تقربوا"), "النص: \(text)")
    }

    /// منطقة قص خارج النص: لا نص (الصورة بيضاء فوق وتحت).
    func testCropOutsideTextFindsNothing() async throws {
        let recognizer = VisionArabicRecognizer()
        guard recognizer.isArabicSupported else { throw XCTSkip("لا عربية في Vision على هذا الإصدار") }
        let prepared = try ImageIOScreenshotProcessor().prepare(ScreenshotTestSample.pngData(), limits: .standard)
        let lines = try await recognizer.recognizeLines(in: prepared, region: CropBand(top: 0, bottom: 0.1).visionRegion)
        XCTAssertTrue(ExtractedTextAssembler.assemble(lines).text.isEmpty)
    }

    /// ImageIO الحقيقي: الأبعاد تُقرأ قبل الفك، والصغيرة والتالفة تُرفض، والكبيرة تُصغَّر.
    func testImageIOProcessorLimits() throws {
        XCTAssertThrowsError(try ImageIOScreenshotProcessor().prepare(ScreenshotTestSample.unreadable, limits: .standard)) {
            XCTAssertEqual($0 as? ScreenshotTextError, .unreadableImage)
        }
        let tiny = ScreenshotTestSample.pngData(text: "لا", size: CGSize(width: 40, height: 40), fontSize: 10)
        XCTAssertThrowsError(try ImageIOScreenshotProcessor().prepare(tiny, limits: .standard)) {
            XCTAssertEqual($0 as? ScreenshotTextError, .imageTooSmall)
        }
        var small = ScreenshotLimits.standard
        small.workingMaxSide = 500
        let prepared = try ImageIOScreenshotProcessor().prepare(ScreenshotTestSample.pngData(), limits: small)
        XCTAssertEqual(max(prepared.width, prepared.height), 500, "تصغير قبل الاستخراج")
        var strict = ScreenshotLimits.standard
        strict.maxSide = 1000
        XCTAssertThrowsError(try ImageIOScreenshotProcessor().prepare(ScreenshotTestSample.pngData(), limits: strict)) {
            XCTAssertEqual($0 as? ScreenshotTextError, .dimensionsTooLarge)
        }
    }

    /// المتحكم الحقيقي بالمحرك الحقيقي: لا يبدأ مراجعة ولا يكتب ملفات.
    @MainActor
    func testEndToEndOnDeviceDoesNotStartReview() async throws {
        guard let recognizer = ScreenshotTextEngines.bestAvailable() else { throw XCTSkip("لا قارئ عربي متاح على هذا الإصدار") }
        let controller = ScreenshotTextController(recognizer: recognizer, processor: ImageIOScreenshotProcessor())
        let data = ScreenshotTestSample.pngData()
        controller.load { data }
        let deadline = Date().addingTimeInterval(10)
        while controller.phase != .ready && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        controller.extract()
        while controller.phase == .extracting && Date() < deadline.addingTimeInterval(20) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(controller.phase, .extracted)
        let session = ReviewSession()
        session.useExtractedText(try XCTUnwrap(controller.acceptedText))
        XCTAssertEqual(session.primary, .idle)
        controller.discard()
        XCTAssertFalse(controller.hasImage)
    }
}
#endif
