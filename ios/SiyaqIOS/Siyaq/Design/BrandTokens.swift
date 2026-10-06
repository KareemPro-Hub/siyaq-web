import Foundation

/// قيم ألوان الهوية المعتمدة كأرقام (بلا SwiftUI) حتى تُختبر نسب التباين آليًا.
/// المصدر: ابدأ-هنا.md ومدخلات/التطبيق/styles.css. القيم *High تُستخدم فقط عند «زيادة التباين».
enum BrandTokens {
    static let navy: UInt32 = 0x242C5A
    static let teal: UInt32 = 0x00ABB7
    static let tealDark: UInt32 = 0x007F89
    static let ground: UInt32 = 0xF5F8F7
    static let hero: UInt32 = 0xD3E3DF
    static let white: UInt32 = 0xFFFFFF
    static let muted: UInt32 = 0x667579
    static let mutedHigh: UInt32 = 0x4A585C
    static let eyebrow: UInt32 = 0x46676A
    static let eyebrowHigh: UInt32 = 0x34504F
    static let heroText: UInt32 = 0x4E636A
    static let placeholder: UInt32 = 0x8B999D
    static let placeholderHigh: UInt32 = 0x5E6C70
    static let error: UInt32 = 0x945746
    static let notice: UInt32 = 0xE5EFEB
    static let segmentTrack: UInt32 = 0xE6EDE9
    static let lavenderBackground: UInt32 = 0xEEE5F4
    static let coralBackground: UInt32 = 0xF4E9E0
    static let mintBackground: UInt32 = 0xE3EFEB

    /// نسبة التباين حسب WCAG 2.x.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

/// زمن حركة التدرج المتصل، دون تقطيع الإطار إلى مقاطع.
enum InputBorderBeam {
    /// دورة كاملة هادئة خلال١٨ثانية بدل٣٫٦ثوانٍ.
    static let period: Double = 18

    static func phase(at time: Double, period: Double = period) -> Double {
        guard period > 0, time.isFinite else { return 0 }
        let value = time.truncatingRemainder(dividingBy: period) / period
        return value < 0 ? value + 1 : value
    }
}
