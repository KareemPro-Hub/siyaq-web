import SwiftUI

/// انتظار مع إمكانية الإلغاء.
struct LoadingStateView: View {
    let quote: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.tealDark)
                .padding(.top, 40)
                .accessibilityHidden(true)
            Text("نراجع الاقتباس…")
                .siyaqFont(.sectionTitle)
                .foregroundStyle(Palette.navy)
            if !quote.isEmpty {
                Text(quote)
                    .siyaqFont(.caption)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            Button("إلغاء", action: cancel)
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 220)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement("نراجع الاقتباس").post()
        }
    }
}

/// خطأ واضح مع خيارات مناسبة.
struct ErrorStateView: View {
    let error: ReviewError
    let retry: (() -> Void)?
    let editQuote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconBubble(systemName: error.systemImage, tone: .coral, size: 48)
                .padding(.top, 20)
            Text(error.title)
                .siyaqFont(.screenTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            Text(error.message)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if let retry {
                    Button(action: retry) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise").accessibilityHidden(true)
                            Text("إعادة المحاولة")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button("تعديل الاقتباس", action: editQuote)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            AccessibilityNotification.Announcement(error.message).post()
        }
    }
}

/// عدم العثور: رسالة صريحة دون ادعاء.
struct NotFoundView: View {
    let outcome: ReviewOutcome
    let editQuote: () -> Void
    var fromImage: Bool = false

    var body: some View {
        let notice = ReviewSearchNotice.notFound(fromImage: fromImage)
        VStack(alignment: .leading, spacing: 14) {
            if outcome.origin == .preview { PreviewModeBadge() }
            IconBubble(systemName: "magnifyingglass", tone: .lavender, size: 48)
                .padding(.top, 8)
            Text(notice.title)
                .siyaqFont(.screenTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            Text(notice.message)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "اقتباسك كما كتبته")
                Text(outcome.result.quote)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.navy)
                    .textSelection(.enabled)
            }
            .siyaqCard()

            if let ignored = ReviewSearchNotice.ignored(outcome.result.search) {
                NoticeCard(.info, message: ignored)
            }

            if !outcome.result.sourceVersion.isEmpty {
                Text("إصدار البيانات: \(outcome.result.sourceVersion)")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
            }

            Button("تعديل الاقتباس", action: editQuote)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
