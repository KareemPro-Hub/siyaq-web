import SwiftUI
import UIKit

// MARK: - الألوان المعتمدة (من ابدأ-هنا.md ومدخلات/التطبيق/styles.css)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Color {
    /// لون ثابت افتراضيًا، وأغمق عند تفعيل «زيادة التباين» في النظام. لا وضع داكن (الهوية فاتحة).
    static func adaptive(base: UInt32, highContrast: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.accessibilityContrast == .high ? highContrast : base)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    static let navy = Color(hex: BrandTokens.navy)
    static let teal = Color(hex: BrandTokens.teal)
    /// التركواز الأغمق المستخدم في النموذج للتبويب النشط والروابط.
    static let tealDark = Color(hex: BrandTokens.tealDark)
    static let ground = Color(hex: BrandTokens.ground)
    static let hero = Color(hex: BrandTokens.hero)
    /// #667579 المعتمد؛ أغمق تلقائيًا عند «زيادة التباين» (٤٫٤٨:١ على الأرضية افتراضيًا).
    static let muted = Color.adaptive(base: BrandTokens.muted, highContrast: BrandTokens.mutedHigh)
    static let line = Color(hex: 0xDCE7E4)
    // أغمق قليلًا من 0x527578 و0x586F76 في النموذج ليبلغ تباين ٤٫٥:١ على أرضية النعناع.
    static let eyebrow = Color.adaptive(base: BrandTokens.eyebrow, highContrast: BrandTokens.eyebrowHigh)
    static let heroText = Color(hex: BrandTokens.heroText)
    static let card = Color.white
    static let cardBorder = Color(hex: 0xE2EAE6)
    static let inputBorder = Color(hex: 0xD6E2DD)
    static let placeholder = Color.adaptive(base: BrandTokens.placeholder, highContrast: BrandTokens.placeholderHigh)
    static let notice = Color(hex: 0xE5EFEB)
    static let noticeIcon = Color(hex: 0x46919A)
    static let segmentTrack = Color(hex: 0xE6EDE9)
    static let highlight = Color(hex: 0xEFF5F2)
    static let error = Color(hex: BrandTokens.error)
    static let rowDivider = Color(hex: 0xE1E9E6)
}

/// أيقونات الباستيل من النموذج.
enum Tone: CaseIterable {
    case coral, lavender, mint

    var foreground: Color {
        switch self {
        case .coral: return Color(hex: 0xA16C51)
        case .lavender: return Color(hex: 0x9470AF)
        case .mint: return Color(hex: 0x42959E)
        }
    }

    var background: Color {
        switch self {
        case .coral: return Color(hex: 0xF4E9E0)
        case .lavender: return Color(hex: 0xEEE5F4)
        case .mint: return Color(hex: 0xE3EFEB)
        }
    }
}

// MARK: - الخط: حرير مع بديل النظام

/// أسماء PostScript الداخلية بعد فحص ملفات الخط: Harir-Reg و Harir-Bld (Typotheque).
enum SiyaqTypography {
    static let regularName = "Harir-Reg"
    static let boldName = "Harir-Bld"

    static let isHarirAvailable: Bool =
        UIFont(name: regularName, size: 12) != nil && UIFont(name: boldName, size: 12) != nil
}

enum SiyaqTextStyle {
    case brand
    case heroTitle
    case screenTitle
    case sectionTitle
    case body
    case bodyBold
    case button
    case quran
    case quranContext
    case caption
    case captionBold
    case eyebrow
    case small

    private var spec: (size: CGFloat, bold: Bool, relativeTo: Font.TextStyle) {
        switch self {
        case .brand: return (30, true, .largeTitle)
        case .heroTitle: return (30, true, .title)
        case .screenTitle: return (28, true, .title)
        case .sectionTitle: return (17, true, .headline)
        case .body: return (16, false, .body)
        case .bodyBold: return (16, true, .body)
        case .button: return (17, true, .headline)
        case .quran: return (23, false, .title2)
        case .quranContext: return (20, false, .title3)
        case .caption: return (14, false, .subheadline)
        case .captionBold: return (14, true, .subheadline)
        case .eyebrow: return (13, false, .footnote)
        case .small: return (12, false, .caption)
        }
    }

    func font(useSystem: Bool) -> Font {
        let spec = self.spec
        if useSystem || !SiyaqTypography.isHarirAvailable {
            return Font.system(spec.relativeTo).weight(spec.bold ? .bold : .regular)
        }
        let name = spec.bold ? SiyaqTypography.boldName : SiyaqTypography.regularName
        // relativeTo يجعل الخط يتبع Dynamic Type.
        return Font.custom(name, size: spec.size, relativeTo: spec.relativeTo)
    }
}

private struct SystemFontKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var siyaqUsesSystemFont: Bool {
        get { self[SystemFontKey.self] }
        set { self[SystemFontKey.self] = newValue }
    }
}

private struct SiyaqFontModifier: ViewModifier {
    @Environment(\.siyaqUsesSystemFont) private var useSystem
    let style: SiyaqTextStyle

    func body(content: Content) -> some View {
        content.font(style.font(useSystem: useSystem))
    }
}

extension View {
    func siyaqFont(_ style: SiyaqTextStyle) -> some View {
        modifier(SiyaqFontModifier(style: style))
    }
}

// MARK: - تباين

extension Palette {
    /// كل زر بنص أبيض يستخدم #007F89 (تباين ٤٫٧٨:١ مع الأبيض)، وهو لون من النموذج المعتمد نفسه.
    /// التركواز #00ABB7 يبقى للزخرفة والإطار والتركيز، لا خلفية لنص أبيض.
    static func primaryFill(_ contrast: ColorSchemeContrast = .standard) -> Color {
        tealDark
    }
}
