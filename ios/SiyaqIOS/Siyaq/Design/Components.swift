import SwiftUI

// MARK: - الأزرار

/// الزر الرئيسي: تركواز، نص أبيض عريض، زوايا ١٧، ارتفاع لا يقل عن ٥٠.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .siyaqFont(.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Palette.primaryFill(contrast).opacity(isEnabled ? 1 : 0.5))
            )
            .shadow(color: Palette.teal.opacity(0.08), radius: 5, y: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// زر ثانوي هادئ بحدود.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .siyaqFont(.bodyBold)
            .foregroundStyle(Palette.navy)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(configuration.isPressed ? Palette.notice : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Palette.inputBorder, lineWidth: 1)
            )
    }
}

// MARK: - رموز وبطاقات

/// مربع أيقونة باستيل (٣٩ نقطة في النموذج).
struct IconBubble: View {
    let systemName: String
    let tone: Tone
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .regular))
            .foregroundStyle(tone.foreground)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 3, style: .continuous).fill(tone.background))
            .accessibilityHidden(true)
    }
}

/// بطاقة بيضاء بحدود خفيفة.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 17

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.cardBorder, lineWidth: 1))
    }
}

extension View {
    func siyaqCard(padding: CGFloat = 17) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// تنبيه بخلفية نعناعية؛ نسخة تحذير للتشابه المحتمل.
struct NoticeCard: View {
    enum Style { case info, warning, success }

    let style: Style
    let title: String?
    let message: String

    init(_ style: Style = .info, title: String? = nil, message: String) {
        self.style = style
        self.title = title
        self.message = message
    }

    private var icon: String {
        switch style {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .success: return "checkmark.shield"
        }
    }

    private var iconColor: Color {
        switch style {
        case .warning: return Tone.coral.foreground
        default: return Palette.noticeIcon
        }
    }

    private var fill: Color {
        switch style {
        case .warning: return Tone.coral.background
        default: return Palette.notice
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(iconColor)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .siyaqFont(.captionBold)
                        .foregroundStyle(Palette.navy)
                }
                Text(message)
                    .siyaqFont(.caption)
                    .foregroundStyle(Palette.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// شارة وضع المعاينة: واضحة ومنفصلة عن الوضع الحي.
struct PreviewModeBadge: View {
    var message: String = "وضع المعاينة: نتائج مسجلة مسبقًا من أمثلة الخدمة، وليست مراجعة حية."

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye")
                .foregroundStyle(Tone.lavender.foreground)
                .accessibilityHidden(true)
            Text(message)
                .siyaqFont(.caption)
                .foregroundStyle(Palette.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Tone.lavender.background))
        .accessibilityElement(children: .combine)
    }
}

/// عنوان قسم صغير فوق المحتوى.
struct Kicker: View {
    let text: String

    var body: some View {
        Text(text)
            .siyaqFont(.small)
            .foregroundStyle(Palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// رابط مصدر آمن؛ يفتح في متصفح النظام. يرفض غير http/https.
struct SourceLinkRow: View {
    let title: String
    let rawURL: String

    init(title: String, rawURL: String) {
        self.title = title
        self.rawURL = rawURL
    }

    init(title: String, url: URL) {
        self.title = title
        self.rawURL = url.absoluteString
    }

    var body: some View {
        if let url = SafeLink.url(from: rawURL) {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .accessibilityHidden(true)
                    Text(title)
                        .siyaqFont(.caption)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Palette.tealDark)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityHint("يفتح في المتصفح")
        } else {
            Text("رابط المصدر غير متاح للعرض.")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
        }
    }
}

/// شعار التطبيق المعتمد كما هو.
struct BrandLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// شكل أرضية البطل: انحناء سفلي من النموذج (border-radius: 0 0 48% 10% / 0 0 6% 2%).
struct HeroShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let rightX = w * 0.48, rightY = h * 0.06
        let leftX = w * 0.10, leftY = h * 0.02
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rightX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + leftX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - leftY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// مشهد القارئ في البطل: صورة النموذج ومدار متقطع وأربع أيقونات باستيل. زخرفي فقط.
struct ReaderScene: View {
    var body: some View {
        ZStack {
            Ellipse()
                .strokeBorder(Color(hex: 0xA7C6C3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 190, height: 144)
                .position(x: 145, y: 87)
            Image("BookLens")
                .resizable()
                .scaledToFit()
                .frame(width: 222, height: 192)
                .position(x: 145, y: 96)
            bubble("book", color: 0x48A5AD).position(x: 251, y: 49)
            bubble("quote.bubble", color: 0xCE9C83).position(x: 45, y: 29)
            bubble("checkmark.shield", color: 0xB58ACE).position(x: 36, y: 145)
        }
        .frame(width: 290, height: 192)
        // مواضع فيزيائية كما في النموذج، لا تنعكس.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func bubble(_ name: String, color: UInt32) -> some View {
        Image(systemName: name)
            .font(.system(size: 16))
            .foregroundStyle(Color(hex: color))
            .frame(width: 37, height: 37)
            .background(Circle().fill(Palette.ground))
            .overlay(Circle().stroke(Color(hex: 0xD0DFDC), lineWidth: 1))
    }
}

// MARK: - إطار مضيء متحرك حول مربع الإدخال

/// إضاءة تركوازية متصلة: دورة بطيئة وتدرج ناعم، بلا قطع أو رأس حاد.
/// تتوقف عند تقليل الحركة وعندما يغادر التطبيق الحالة النشطة.
struct GlowingInputFrame: ViewModifier {
    var cornerRadius: CGFloat = 20
    var isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.teal.opacity(isFocused ? 0.32 : 0.18),
                                  lineWidth: isFocused ? 1.5 : 1)
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { context in
                        let phase = InputBorderBeam.phase(at: context.date.timeIntervalSinceReferenceDate)
                        let light = AngularGradient(
                            stops: [
                                .init(color: Palette.teal.opacity(0), location: 0),
                                .init(color: Palette.teal.opacity(0), location: 0.48),
                                .init(color: Palette.teal.opacity(0.08), location: 0.60),
                                .init(color: Palette.teal.opacity(0.45), location: 0.73),
                                .init(color: Palette.teal.opacity(0.95), location: 0.85),
                                .init(color: Color(hex: 0x9AE5DE).opacity(0.90), location: 0.91),
                                .init(color: Palette.teal.opacity(0.45), location: 0.96),
                                .init(color: Palette.teal.opacity(0), location: 1)
                            ], center: .center, angle: .degrees(phase * 360)
                        )
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(light, lineWidth: 3)
                                .blur(radius: 4)
                                .opacity(isFocused ? 0.42 : 0.30)
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(light, lineWidth: isFocused ? 2.2 : 2, antialiased: true)
                        }
                        // مزج لوني خطي للإضاءة وحدها؛ النص يظل خارج طبقة الرسم.
                        .drawingGroup(opaque: false, colorMode: .linear)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func glowingInputFrame(cornerRadius: CGFloat = 20, isFocused: Bool) -> some View {
        modifier(GlowingInputFrame(cornerRadius: cornerRadius, isFocused: isFocused))
    }
}

// MARK: - صف يتكيف مع أحجام الخط الكبيرة

/// أفقي في الأحجام العادية، وعمودي في أحجام إمكانية الوصول حتى لا يضيق النص أو يُقطع.
struct AdaptiveRow<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        layout { content() }
    }
}
