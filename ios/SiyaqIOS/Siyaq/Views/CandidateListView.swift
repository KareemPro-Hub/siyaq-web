import SwiftUI

/// اختيار الموضع عند choices أو possible. لا اختيار تلقائي، ولا يتحول التشابه إلى إثبات.
struct CandidateListView: View {
    let outcome: ReviewOutcome
    let onSelect: (Candidate) -> Void
    var fromImage: Bool = false

    private var result: ReviewResult { outcome.result }
    private var isPossible: Bool { result.status == .possible }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if outcome.origin == .preview { PreviewModeBadge() }

            VStack(alignment: .leading, spacing: 6) {
                Text("تحديد الموضع")
                    .siyaqFont(.eyebrow)
                    .foregroundStyle(Palette.eyebrow)
                Text(isPossible ? "مواضع محتملة." : "أي موضع تقصد؟")
                    .siyaqFont(.screenTitle)
                    .foregroundStyle(Palette.navy)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "اقتباسك كما كتبته")
                Text(result.quote)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.navy)
                    .textSelection(.enabled)
            }
            .siyaqCard(padding: 14)

            if isPossible {
                let notice = ReviewSearchNotice.possible(search: result.search, fromImage: fromImage)
                NoticeCard(.warning, title: notice.title, message: notice.message)
            } else {
                NoticeCard(
                    .info,
                    message: "ورد هذا الاقتباس في أكثر من موضع. اختر الموضع المقصود لعرض النص كاملًا وسياقه وتفسيره."
                )
            }

            if let ignored = ReviewSearchNotice.ignored(result.search) {
                NoticeCard(.info, message: ignored)
            }

            if result.hiddenCandidateCount > 0 {
                NoticeCard(
                    .info,
                    title: "القائمة محدودة",
                    message: "تعرض القائمة \(ArabicFormat.number(result.candidates.count)) من \(ArabicFormat.number(result.candidateCount)) موضعًا. اكتب اقتباسًا أطول لتضييق النتائج."
                )
            }

            if result.candidates.isEmpty {
                Text("لم تصل مواضع لعرضها.")
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.muted)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(result.candidates.enumerated()), id: \.offset) { _, candidate in
                        CandidateRow(candidate: candidate) { onSelect(candidate) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CandidateRow: View {
    let candidate: Candidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ArabicFormat.location(of: candidate.verses))
                            .siyaqFont(.bodyBold)
                            .foregroundStyle(Palette.navy)
                        KindBadge(kind: candidate.kind)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6B878A))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }

                ForEach(candidate.verses) { verse in
                    // النص الأصلي كاملًا كما ورد.
                    Text(verse.text)
                        .siyaqFont(.quranContext)
                        .foregroundStyle(Palette.navy)
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !candidate.note.isEmpty {
                    Text(candidate.note)
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .siyaqCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("اختر هذا الموضع لعرض النص والسياق والتفسير")
    }
}

/// نوع المطابقة بلغة بسيطة.
struct KindBadge: View {
    let kind: MatchKind

    var body: some View {
        // النص بالكحلي للتباين على الخلفية الباستيل؛ اللون في الأيقونة فقط.
        Label {
            Text(kind.title)
                .foregroundStyle(Palette.navy)
        } icon: {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind == .possible ? Tone.coral.foreground : Palette.tealDark)
        }
        .siyaqFont(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(kind == .possible ? Tone.coral.background : Tone.mint.background))
    }
}

extension MatchKind {
    var title: String {
        switch self {
        case .full: return "مطابق لنص الآية"
        case .partial: return "جزء من آية"
        case .spanning: return "يمتد عبر آيات متجاورة"
        case .possible: return "تشابه محتمل، ليس إثباتًا"
        case .unknown: return "نوع غير معروف"
        }
    }

    var symbol: String {
        switch self {
        case .full: return "checkmark.shield"
        case .partial: return "text.quote"
        case .spanning: return "text.append"
        case .possible: return "exclamationmark.triangle"
        case .unknown: return "questionmark.circle"
        }
    }
}
