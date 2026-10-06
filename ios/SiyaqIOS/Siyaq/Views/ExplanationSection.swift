import SwiftUI

/// ما يلزم لطلب الشرح لنفس الطلب الذي أنتج النتيجة.
struct ExplanationRequestContext: Equatable {
    let outcome: ReviewOutcome
    let quote: String
    let selection: String?

    var key: String {
        [quote, selection ?? "-", outcome.result.selected?.id ?? "-", outcome.result.sourceVersion].joined(separator: "|")
    }
}

/// قسم الشرح المساعد: منفصل بصريًا ونصيًا عن النص القرآني والتفسير المنقول.
/// يدوي فقط، ويعرض إشعار الخصوصية قبل الطلب.
struct ExplanationSection: View {
    let context: ExplanationRequestContext
    /// آيات الموضع وسياقه لعرض موضع كل دليل.
    let verses: [Verse]

    @State private var controller = ExplanationController()

    private var eligible: Bool { ExplanationEligibility.isEligible(context.outcome) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !eligible {
                NoticeCard(.info, message: ineligibleMessage)
            } else {
                switch controller.state {
                case .idle:
                    idleView
                case .loading:
                    loadingView
                case .ready(let explanation):
                    readyView(explanation)
                case .abstained(let explanation):
                    abstainedView(explanation)
                case .failed(let error):
                    failedView(error)
                }
            }
        }
        .siyaqCard()
        .accessibilityElement(children: .contain)
        .onDisappear { controller.cancel() }
        .onChange(of: context.key) { controller.reset() }
    }

    // MARK: أجزاء

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Tone.lavender.foreground)
                .accessibilityHidden(true)
            Text("شرح مساعد مولّد")
                .siyaqFont(.sectionTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Text("اختياري")
                .siyaqFont(.small)
                .foregroundStyle(Palette.navy)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Tone.lavender.background))
        }
    }

    private var ineligibleMessage: String {
        // التشابه المحتمل أولًا: هو المانع العلمي الدائم، أيًّا كان الوضع.
        if context.outcome.result.isSelectedPossible {
            return "لا يُقدَّم شرح مساعد للتشابه المحتمل. قارن الألفاظ بالنص الأصلي والتفسير المنقول."
        }
        if context.outcome.origin == .preview {
            return "الشرح المساعد غير متاح في وضع المعاينة؛ لا توجد أمثلة شرح مسجلة، ولا يولّد التطبيق شرحًا محليًا."
        }
        return "الشرح المساعد غير متاح لهذه النتيجة."
    }

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("شرح مولّد آليًا من الأدلة المعتمدة المعروضة، وليس تفسيرًا مستقلًا ولا فتوى. النص القرآني والتفسير المنقول أعلاه هما الأصل.")
                .siyaqFont(.caption)
                .foregroundStyle(Palette.navy)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("قبل الطلب: الخصوصية")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.navy)
                Text("الطلب يدوي. عند الضغط يُرسل اقتباسك والموضع إلى خدمة سِياق، ثم ترسل الخدمة نص الآية والأدلة المعتمدة فقط إلى مزود الذكاء الاصطناعي. لا يصل نص اقتباسك الحر إلى المزود، ولا يُحفظ الشرح على جهازك.")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.notice))
            .accessibilityElement(children: .combine)

            Button(action: requestExplanation) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                    Text("اطلب الشرح المساعد")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("يرسل طلبًا واحدًا إلى خدمة سِياق")
            .accessibilityIdentifier("explainButton")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Palette.tealDark)
                .accessibilityHidden(true)
            Text("نجهّز الشرح من الأدلة المعتمدة…")
                .siyaqFont(.caption)
                .foregroundStyle(Palette.navy)
            Button("إلغاء") { controller.cancel() }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement("نجهّز الشرح المساعد").post() }
    }

    private func readyView(_ explanation: Explanation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !explanation.notice.isEmpty {
                NoticeCard(.warning, title: "تنبيه", message: explanation.notice)
            }
            ForEach(Array(explanation.claims.enumerated()), id: \.offset) { index, claim in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                ClaimView(claim: claim, verses: verses)
            }
            footer(explanation)
        }
    }

    private func abstainedView(_ explanation: Explanation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NoticeCard(
                .info,
                title: "امتنع الشرح المساعد",
                message: (explanation.reason?.isEmpty == false ? explanation.reason! : "لا تكفي الأدلة المعتمدة لتقديم شرح موثق لهذا الموضع.")
            )
            if !explanation.notice.isEmpty {
                Text(explanation.notice)
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("لا يُعرض شرح بديل. النص والسياق والتفسير المنقول أعلاه متاحة كما هي.")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            footer(explanation)
        }
        .onAppear { AccessibilityNotification.Announcement("امتنع الشرح المساعد").post() }
    }

    private func failedView(_ error: ReviewError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NoticeCard(error == .aiNotConfigured ? .info : .warning, title: error.title, message: error.message)
            if error.canRetry {
                Button(action: requestExplanation) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").accessibilityHidden(true)
                        Text("أعد المحاولة")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityHint("محاولة يدوية واحدة")
            }
        }
        .onAppear { AccessibilityNotification.Announcement(error.message).post() }
    }

    private func footer(_ explanation: Explanation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !explanation.sourceVersion.isEmpty {
                Text("إصدار البيانات: \(explanation.sourceVersion)")
            }
            if let model = explanation.model, !model.isEmpty {
                Text("النموذج: \(model)")
            }
        }
        .siyaqFont(.small)
        .foregroundStyle(Palette.muted)
    }

    // MARK: إجراءات

    private func requestExplanation() {
        do {
            let service = try ServiceConfiguration.current.makeExplanationService()
            controller.request(for: context.outcome, quote: context.quote, selection: context.selection, service: service)
        } catch {
            // خدمة غير مهيأة في هذا البناء، أو أمثلة اختبار مسجلة: لا اتصال.
            controller.showFailure(ReviewError.from(error))
        }
    }
}

/// ادعاء واحد: الشرح المولد، ثم الاقتباس الحرفي، ثم الدليل ومصدره.
struct ClaimView: View {
    let claim: ExplanationClaim
    let verses: [Verse]

    @State private var showEvidence = false

    private var evidenceLocation: String {
        if let verse = verses.first(where: { $0.id == claim.evidence.verseId }) {
            return ArabicFormat.location(of: verse)
        }
        return claim.evidence.verseId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ١) الشرح المولد — بخلفية مميزة وتسمية صريحة.
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("شرح مولّد")
                        .foregroundStyle(Palette.navy)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Tone.lavender.foreground)
                }
                .siyaqFont(.captionBold)
                Text(claim.text)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.navy)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tone.lavender.background))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("شرح مولّد: \(claim.text)")

            // ٢) الاقتباس الحرفي من الدليل كما أعاده الخادم.
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "الاقتباس الحرفي من الدليل")
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(Tone.mint.foreground).frame(width: 3)
                        .accessibilityHidden(true)
                    Text(verbatim: claim.excerpt)
                        .siyaqFont(.body)
                        .foregroundStyle(Palette.navy)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            // ٣) الدليل ومصدره.
            VStack(alignment: .leading, spacing: 3) {
                Text(claim.evidence.bookName.isEmpty ? "كتاب غير مسمى" : claim.evidence.bookName)
                    .siyaqFont(.captionBold)
                    .foregroundStyle(Palette.navy)
                Text(
                    [claim.evidence.author,
                     ArabicFormat.reference(part: claim.evidence.part, page: claim.evidence.page),
                     evidenceLocation]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            SourceLinkRow(title: "فتح الدليل في مصدره", rawURL: claim.evidence.url)

            DisclosureGroup(isExpanded: $showEvidence) {
                Text(verbatim: claim.evidence.text)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.navy)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } label: {
                Text("نص الدليل كاملًا")
                    .siyaqFont(.captionBold)
                    .foregroundStyle(Palette.tealDark)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .tint(Palette.tealDark)
        }
    }
}
