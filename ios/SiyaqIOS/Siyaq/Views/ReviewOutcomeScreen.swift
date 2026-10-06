import SwiftUI

/// شاشة نتيجة طلب (الاقتباس أو الموضع المختار): انتظار، خطأ، اختيار، عدم عثور، أو نتيجة كاملة.
struct ReviewOutcomeScreen: View {
    let route: ReviewRoute
    @Bindable var session: ReviewSession
    let onSelect: (Candidate) -> Void

    @Environment(\.dismiss) private var dismiss

    private var state: LoadState {
        switch route {
        case .review: return session.primary
        case .selection: return session.selection
        }
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 23)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.ground, for: .navigationBar)
        .toolbar {
            if let outcome = state.outcome, let candidate = outcome.result.selected, outcome.result.status == .matched {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ResultActions(outcome: outcome, candidate: candidate)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch route {
        case .review: return "المراجعة"
        case .selection: return "الموضع المختار"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView(quote: session.submittedQuote) {
                switch route {
                case .review: session.cancelPrimary()
                case .selection: session.cancelSelection(); dismiss()
                }
            }
        case .failed(let error):
            ErrorStateView(
                error: error,
                retry: error.canRetry ? retry : nil,
                editQuote: { dismiss() }
            )
        case .loaded(let outcome):
            OutcomeContent(
                outcome: outcome,
                onSelect: onSelect,
                editQuote: { dismiss() },
                fromImage: session.submittedFromImage,
                explanationContext: ExplanationRequestContext(
                    outcome: outcome,
                    quote: session.submittedQuote,
                    // نثبت الموضع المعروض نفسه: معرف المرشح المختار من النتيجة (مسموح في العقد)،
                    // حتى لا يشرح الخادم موضعًا غير الذي يراه المستخدم.
                    selection: selectionID ?? outcome.result.selected?.id
                )
            )
        }
    }

    /// selection الذي أنتج هذه النتيجة: معرف المرشح في شاشة الاختيار، ولا شيء للطلب الأول.
    private var selectionID: String? {
        if case .selection(let id) = route { return id }
        return nil
    }

    private func retry() {
        switch route {
        case .review: session.retryPrimary()
        case .selection: session.retrySelection()
        }
    }
}

/// يختار العرض حسب status.
struct OutcomeContent: View {
    let outcome: ReviewOutcome
    let onSelect: (Candidate) -> Void
    let editQuote: () -> Void
    /// الاقتباس جاء من قراءة صورة: يغيّر نص «لم نجد» والمواضع المحتملة فقط.
    var fromImage: Bool = false
    var explanationContext: ExplanationRequestContext? = nil

    var body: some View {
        let result = outcome.result
        switch result.status {
        case .matched:
            if let candidate = result.selected {
                ResultDetailView(
                    result: result,
                    candidate: candidate,
                    origin: outcome.origin,
                    savedAt: nil,
                    explanationContext: explanationContext
                )
            } else {
                ErrorStateView(error: .invalidResponse, retry: nil, editQuote: editQuote)
            }
        case .choices, .possible:
            CandidateListView(outcome: outcome, onSelect: onSelect,
                              fromImage: fromImage || ReviewSearchNotice.looksLikeImageText(result.search))
        case .notFound:
            NotFoundView(outcome: outcome, editQuote: editQuote,
                         fromImage: fromImage || ReviewSearchNotice.looksLikeImageText(result.search))
        case .unknown:
            NoticeCard(.info, title: "نتيجة غير مدعومة", message: "وصلت نتيجة من نوع لا يعرضه هذا الإصدار من التطبيق. حدّث التطبيق ثم أعد المحاولة.")
        }
    }
}

/// حفظ ومشاركة نتيجة كاملة.
struct ResultActions: View {
    let outcome: ReviewOutcome
    let candidate: Candidate

    @Environment(SavedResultsStore.self) private var store

    var body: some View {
        let saved = store.isSaved(outcome)
        ShareLink(
            item: ShareText.make(result: outcome.result, candidate: candidate),
            subject: Text("سِياق"),
            preview: SharePreview(ArabicFormat.location(of: candidate.verses))
        ) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("مشاركة النص والموضع والمصدر")
        .accessibilityIdentifier("shareResult")

        Button {
            if saved {
                // لا إعلان نجاح كاذب: يُعلن فقط إن تمت الإزالة فعلًا (قد تكون المحفوظات للقراءة فقط).
                if store.remove(outcome) {
                    AccessibilityNotification.Announcement("أُزيلت من المحفوظات").post()
                }
            } else if store.save(outcome) != nil {
                AccessibilityNotification.Announcement("حُفظت النتيجة").post()
            }
        } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
        }
        .accessibilityLabel(saved ? "إزالة من المحفوظات" : "حفظ النتيجة")
        .accessibilityIdentifier("saveResult")
    }
}
