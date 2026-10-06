import SwiftUI

enum ResultTab: String, CaseIterable, Identifiable {
    case text, context, tafsir, source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "النص"
        case .context: return "السياق"
        case .tafsir: return "التفسير"
        case .source: return "المصدر"
        }
    }
}

/// نتيجة كاملة: الموضع، التنبيه، مقارنة الألفاظ، ثم أقسام النص والسياق والتفسير والمصدر.
/// تُستخدم للنتيجة الحية وللمحفوظات (savedAt) بلا اتصال.
struct ResultDetailView: View {
    let result: ReviewResult
    let candidate: Candidate
    let origin: ResultOrigin
    let savedAt: Date?
    /// سياق طلب الشرح المساعد؛ nil للمحفوظات (الشرح لا يُحفظ ويحتاج اتصالًا).
    var explanationContext: ExplanationRequestContext? = nil

    @State private var tab: ResultTab = .text

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("العودة إلى الأصل")
                    .siyaqFont(.eyebrow)
                    .foregroundStyle(Palette.eyebrow)
                Text("اقتباسك في سياقه.")
                    .siyaqFont(.screenTitle)
                    .foregroundStyle(Palette.navy)
                    .accessibilityAddTraits(.isHeader)
                Text(ArabicFormat.location(of: candidate.verses))
                    .siyaqFont(.caption)
                    .foregroundStyle(Palette.muted)
            }

            if origin == .preview {
                PreviewModeBadge(message: "نتيجة من أمثلة المعاينة المسجلة، وليست مراجعة حية.")
            }

            if let savedAt {
                Label {
                    Text("محفوظة في \(ArabicFormat.date(savedAt))")
                } icon: {
                    Image(systemName: "bookmark.fill")
                }
                .siyaqFont(.small)
                .foregroundStyle(Palette.tealDark)
            }

            kindNotice

            if !result.differences.isEmpty {
                DifferencesView(differences: result.differences)
            }

            ResultTabPicker(selection: $tab)

            Group {
                switch tab {
                case .text: TextPanel(result: result, candidate: candidate)
                case .context: ContextPanel(result: result, candidate: candidate)
                case .tafsir: TafsirPanel(result: result, candidate: candidate)
                case .source: SourcePanel(result: result, candidate: candidate, origin: origin, savedAt: savedAt)
                }
            }
            .siyaqCard()

            // Original approved tafsir is shown in TafsirPanel. Generated explanations are disabled.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var kindNotice: some View {
        switch candidate.kind {
        case .possible:
            // matched مع kind=possible يبقى تشابهًا اختاره المستخدم.
            NoticeCard(
                .warning,
                title: "موضع محتمل اخترته، وليس مطابقة مؤكدة",
                message: candidate.note.isEmpty
                    ? "اخترت هذا الموضع بسبب تشابه الألفاظ. قارن الكلمات بالنص الأصلي."
                    : candidate.note
            )
        case .full:
            NoticeCard(.success, title: candidate.kind.title, message: candidate.note.isEmpty ? "اقرأ ما حول الآية لفهم السياق." : candidate.note)
        default:
            NoticeCard(.info, title: candidate.kind.title, message: candidate.note.isEmpty ? "اقرأ النص كاملًا قبل فهم المعنى." : candidate.note)
        }
    }
}

/// شريط أقسام النتيجة بنمط النموذج؛ يتحول لعمود عند أحجام الخط الكبيرة.
struct ResultTabPicker: View {
    @Binding var selection: ResultTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3))
            : AnyLayout(HStackLayout(spacing: 3))
        layout {
            ForEach(ResultTab.allCases) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(item.title)
                        .siyaqFont(isSelected ? .captionBold : .caption)
                        .foregroundStyle(isSelected ? Palette.navy : Palette.eyebrow)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.white : Color.clear)
                                .shadow(color: isSelected ? Color(hex: 0x254144, opacity: 0.06) : .clear, radius: 3, y: 2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityHint("قسم من أقسام النتيجة")
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.segmentTrack))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("أقسام النتيجة")
    }
}

// MARK: - مقارنة الألفاظ

/// فروق الألفاظ بين الاقتباس والنص (تظهر في التشابه المحتمل المختار).
struct DifferencesView: View {
    let differences: [Difference]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("مقارنة الألفاظ")
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.navy)
            combined
                .siyaqFont(.body)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveRow(spacing: 14) {
                legend(color: Palette.error, text: "في اقتباسك")
                legend(color: Palette.tealDark, text: "في النص الأصلي")
            }
        }
        .siyaqCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
    }

    private var combined: Text {
        var output = Text("")
        for (index, item) in differences.enumerated() {
            if index > 0 { output = output + Text(" ") }
            output = output + token(item)
        }
        return output
    }

    private func token(_ item: Difference) -> Text {
        switch item.type {
        case .input:
            return Text(item.text).foregroundColor(Palette.error).strikethrough(true, color: Palette.error)
        case .source:
            return Text(item.text).foregroundColor(Palette.tealDark).underline(true, color: Palette.tealDark)
        case .same, .unknown:
            return Text(item.text).foregroundColor(Palette.navy)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).siyaqFont(.small).foregroundStyle(Palette.muted)
        }
    }

    private var accessibleDescription: String {
        let parts = differences.map { item -> String in
            switch item.type {
            case .input: return "في اقتباسك: \(item.text)"
            case .source: return "في النص الأصلي: \(item.text)"
            case .same, .unknown: return item.text
            }
        }
        return "مقارنة الألفاظ. " + parts.joined(separator: "، ")
    }
}
