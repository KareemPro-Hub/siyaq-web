#if DEBUG && canImport(UIKit)
import UIKit

/// صورة اختبار تُولَّد في الذاكرة لاختبارات الواجهة والوحدة على iOS — **Debug فقط**.
/// نصها اقتباس المستخدم المثال نفسه («لا تقربوا الصلاة»)، وليست موردًا علميًا ولا تُحفظ في أي مكان.
enum ScreenshotTestSample {
    static let text = "لا تقربوا الصلاة"

    /// PNG بخلفية بيضاء ونص أسود بخط النظام، باتجاه من اليمين.
    static func pngData(text: String = text, size: CGSize = CGSize(width: 1170, height: 600), fontSize: CGFloat = 72) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.baseWritingDirection = .rightToLeft
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            let height = fontSize * 2
            (text as NSString).draw(in: CGRect(x: 40, y: (size.height - height) / 2, width: size.width - 80, height: height),
                                    withAttributes: attributes)
        }
    }

    /// بيانات ليست صورة.
    static let unreadable = Data("siyaq-uitest-not-an-image".utf8)
}
#endif
