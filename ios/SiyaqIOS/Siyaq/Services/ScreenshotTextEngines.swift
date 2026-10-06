import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Vision)
import Vision
#endif

// محركات قراءة النص المحلية. لا اتصال شبكي ولا خدمة مدفوعة.
// - المحرك الأساسي: Apple Vision، **بعد فحص فعلي** لقائمة لغاته على الجهاز (supportedRecognitionLanguages).
// - البديل المفتوح المصدر (Tesseract، Apache-2.0) في TesseractTextRecognizer.swift، ولا يُفعَّل إلا إذا أضاف
//   فريق البناء حزمته وملف ara.traineddata (انظر تسليم-OCR.md).

enum ScreenshotTextEngines {
    /// أفضل محرك متاح فعليًا على هذا الجهاز، أو nil.
    static func bestAvailable() -> (any ArabicTextRecognizing)? {
        #if canImport(Vision)
        let vision = VisionArabicRecognizer()
        if vision.isArabicSupported { return vision }
        #endif
        #if canImport(SwiftyTesseract) && canImport(UIKit)
        let tesseract = TesseractArabicRecognizer()
        if tesseract.isArabicSupported { return tesseract }
        #endif
        return nil
    }

    static func imageProcessor() -> any ScreenshotImageProcessing {
        #if canImport(ImageIO)
        return ImageIOScreenshotProcessor()
        #else
        return UnavailableImageProcessor()
        #endif
    }
}

/// على منصات بلا ImageIO (مثل Linux للاختبارات): كل صورة غير مقروءة.
struct UnavailableImageProcessor: ScreenshotImageProcessing {
    func prepare(_ data: Data, limits: ScreenshotLimits) throws -> PreparedImage {
        throw ScreenshotTextError.unreadableImage
    }

    func decodeFile(at url: URL, limits: ScreenshotLimits) throws -> PreparedImage {
        throw ScreenshotTextError.unreadableImage
    }
}

#if canImport(ImageIO) && canImport(CoreGraphics)
/// يفحص الأبعاد من ترويسة الصورة قبل فكها، ثم يفك نسخة مصغرة باتجاهها الصحيح.
/// لا يكتب أي ملف، ولا يحتفظ بالبيانات الأصلية ولا برابط الملف.
struct ImageIOScreenshotProcessor: ScreenshotImageProcessing {
    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    func prepare(_ data: Data, limits: ScreenshotLimits) throws -> PreparedImage {
        try limits.validate(byteCount: data.count)
        guard let source = CGImageSourceCreateWithData(data as CFData, Self.sourceOptions) else {
            throw ScreenshotTextError.unreadableImage
        }
        return try thumbnail(from: source, limits: limits)
    }

    /// من ملف مباشرة: ImageIO يقرأ الترويسة ثم ما يلزم للنسخة المصغرة فقط، لا الملف كله إلى Data.
    func decodeFile(at url: URL, limits: ScreenshotLimits) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions) else {
            throw ScreenshotTextError.unreadableImage
        }
        return try thumbnail(from: source, limits: limits)
    }

    private func thumbnail(from source: CGImageSource, limits: ScreenshotLimits) throws -> PreparedImage {
        let sourceOptions = Self.sourceOptions
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { throw ScreenshotTextError.unreadableImage }
        try limits.validate(width: width, height: height)

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // يطبق اتجاه EXIF فتصبح الصورة «للأعلى»
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), limits.workingMaxSide),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw ScreenshotTextError.unreadableImage
        }
        return PreparedImage(width: image.width, height: image.height, handle: image)
    }
}
#endif

#if canImport(Vision) && canImport(CoreGraphics)
/// Apple Vision (VNRecognizeTextRequest، المراجعة ٣، الدقة العالية).
/// - اللغات تُقرأ من الجهاز نفسه؛ إن لم تتضمن العربية فالمحرك غير متاح ولا يُستخدم.
/// - تصحيح اللغة مُعطّل: لا نريد أن «يصحح» المحرك رسمًا قرآنيًا إلى إملاء حديث؛ المستخدم يراجع النص.
struct VisionArabicRecognizer: ArabicTextRecognizing {
    let engineName = "Apple Vision"

    /// قائمة اللغات التي يعلنها Vision على هذا الجهاز لهذا الإعداد بالضبط.
    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// رموز العربية التي يعلنها الجهاز (مثل ar-SA وars-SA)، بالترتيب نفسه.
    static func arabicLanguages() -> [String] { cachedArabicLanguages }

    // One real device capability query per process; constructing a SwiftUI view may repeat.
    private static let cachedArabicLanguages: [String] =
        supportedLanguages().filter { $0.lowercased().hasPrefix("ar") }

    var isArabicSupported: Bool { !Self.arabicLanguages().isEmpty }

    func recognizeLines(in image: PreparedImage, region: NormalizedRect) async throws -> [RecognizedLine] {
        guard let handle = image.handle, CFGetTypeID(handle) == CGImage.typeID else {
            throw ScreenshotTextError.unreadableImage
        }
        let cgImage = handle as! CGImage // نوعه مفحوص بالسطر السابق
        let languages = Self.arabicLanguages()
        guard !languages.isEmpty else { throw ScreenshotTextError.arabicUnsupported }

        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                        try handler.perform([request])
                        let observations = request.results ?? []
                        let lines = observations.compactMap { observation -> RecognizedLine? in
                            guard let best = observation.topCandidates(1).first else { return nil }
                            let box = observation.boundingBox
                            return RecognizedLine(
                                text: best.string,
                                confidence: Double(best.confidence),
                                box: NormalizedRect(x: box.minX, y: box.minY, width: box.width, height: box.height)
                            )
                        }
                        continuation.resume(returning: lines)
                    } catch {
                        // بعد الإلغاء تُهمل النتيجة بالرمز في المتحكم؛ لا حاجة لتمييزها هنا.
                        continuation.resume(throwing: ScreenshotTextError.extractionFailed)
                    }
                }
            }
        } onCancel: {
            request.cancel()
        }
    }
}
#endif
