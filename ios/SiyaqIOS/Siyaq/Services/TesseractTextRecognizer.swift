// البديل المحلي المفتوح المصدر للعربية — **غير مفعّل افتراضيًا**.
// يُترجم فقط إذا أضاف فريق البناء الحزمة SwiftyTesseract (MIT، تضم Tesseract بترخيص Apache-2.0 وLeptonica BSD-2
// وlibpng/libjpeg/libtiff بتراخيصها) ومجلد `tessdata` فيه `ara.traineddata` من tessdata_fast (Apache-2.0).
// الحزمة مؤرشفة منذ ٢٠٢٢؛ لذلك لا تُضاف إلا بقرار موثق (انظر تسليم-OCR.md). لم يُبنَ هذا الملف ولم يُختبر.
#if canImport(SwiftyTesseract) && canImport(UIKit) && canImport(CoreGraphics)
import Foundation
import UIKit
import CoreGraphics
import SwiftyTesseract

struct TesseractArabicRecognizer: ArabicTextRecognizing {
    let engineName = "Tesseract (محلي)"

    /// متاح فقط إن وُجد ملف العربية داخل الحزمة فعلًا.
    var isArabicSupported: Bool {
        Bundle.main.url(forResource: "ara", withExtension: "traineddata", subdirectory: "tessdata") != nil
    }

    func recognizeLines(in image: PreparedImage, region: NormalizedRect) async throws -> [RecognizedLine] {
        guard let handle = image.handle, CFGetTypeID(handle) == CGImage.typeID else {
            throw ScreenshotTextError.unreadableImage
        }
        let cgImage = handle as! CGImage
        // منطقة Vision (أصلها أسفل اليسار) ← مستطيل بكسلات (أصله أعلى اليسار).
        let rect = CGRect(
            x: region.x * Double(cgImage.width),
            y: (1 - region.maxY) * Double(cgImage.height),
            width: region.width * Double(cgImage.width),
            height: region.height * Double(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: rect) else { throw ScreenshotTextError.extractionFailed }

        return try await Task.detached(priority: .userInitiated) {
            let tesseract = Tesseract(language: .arabic, dataSource: Bundle.main, engineMode: .lstmOnly)
            switch tesseract.performOCR(on: UIImage(cgImage: cropped)) {
            case .success(let text):
                // Tesseract يعيد النص بترتيب القراءة؛ نعطي كل سطر موضعًا تنازليًا حتى يحافظ المجمّع على الترتيب.
                let rows = text.split(whereSeparator: \.isNewline).map(String.init)
                return rows.enumerated().map { index, row in
                    let height = 1.0 / Double(max(rows.count, 1))
                    return RecognizedLine(text: row, confidence: nil,
                                          box: NormalizedRect(x: 0, y: 1 - Double(index + 1) * height, width: 1, height: height))
                }
            case .failure:
                throw ScreenshotTextError.extractionFailed
            }
        }.value
    }
}
#endif
