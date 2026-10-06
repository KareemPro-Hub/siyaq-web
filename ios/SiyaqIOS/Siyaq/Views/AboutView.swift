import SwiftUI

/// عن سِياق والمصادر والخصوصية والإصدار. لا إعدادات اتصال في الواجهة.
struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrandLogo(size: 66)
                        .accessibilityLabel("شعار سِياق")
                        .padding(.bottom, 20)

                    Text("تطبيق سِياق")
                        .siyaqFont(.screenTitle)
                        .foregroundStyle(Palette.navy)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)

                    Text("يساعدك سِياق على العثور على موضع الاقتباس القرآني، وقراءة الآية في سياقها، والرجوع إلى مصادرها.")
                        .siyaqFont(.body)
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)

                    AboutNote(
                        title: "ما يعرضه التطبيق",
                        text: "النص القرآني والآيات المحيطة به من المصدر المعتمد، والتفسير الأصلي عند توفره، مع مرجعه ورابط موضعه."
                    )
                    AboutNote(
                        title: "حدود المراجعة",
                        text: "لا يقدم سِياق فتاوى أو تفسيرًا مولّدًا. نتائج التشابه اقتراحات تحتاج إلى تحقق، ولا تثبت صحة الاقتباس. والنص المستخرج من الصورة مسودة يجب مراجعتها قبل البحث."
                    )

                    sources
                        .padding(.top, 14)

                    AboutNote(
                        title: "الخصوصية",
                        text: "تُقرأ الصورة على جهازك عند دعم العربية، ولا تُرفع إلى خادم ولا تُحفظ. النص المستخرج مسودة تراجعها وتعدّلها؛ لا يُرسل للمراجعة إلا بعد ضغطك. يُرسل الاقتباس إلى خدمة مراجعة سِياق، وتبقى النتائج التي تحفظها على جهازك فقط، دون حساب أو مزامنة."
                    )
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 12) {
                        Link("سياسة الخصوصية", destination: URL(string: "https://www.mysiyaq.com/privacy")!)
                            .accessibilityIdentifier("privacyPolicyLink")
                        Link("الدعم والمساعدة", destination: URL(string: "https://www.mysiyaq.com/support")!)
                            .accessibilityIdentifier("supportPageLink")
                        Link("موقع سِياق", destination: URL(string: "https://www.mysiyaq.com/")!)
                            .accessibilityIdentifier("siyaqWebsiteLink")
                        Link("contact@mysiyaq.com", destination: URL(string: "mailto:contact@mysiyaq.com")!)
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityLabel("بريد دعم سِياق: contact@mysiyaq.com")
                            .accessibilityIdentifier("supportEmailLink")
                    }
                    .siyaqFont(.caption)
                    .foregroundStyle(Palette.tealDark)
                    .padding(.top, 16)

                    Text(versionText)
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 23)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Palette.ground.ignoresSafeArea())
            .navigationTitle("عن سِياق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.ground, for: .navigationBar)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("المعرفة تبدأ من أصلها")
                .siyaqFont(.eyebrow)
                .foregroundStyle(Palette.eyebrow)
                .padding(.bottom, 6)
            Text("مصادر يمكنك الرجوع إليها.")
                .siyaqFont(.screenTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)

            ForEach(Array(AboutSources.entries.enumerated()), id: \.element.url) { index, entry in
                SourceCard(
                    title: entry.title,
                    subtitle: entry.role,
                    systemImage: entry.tafsirBookId == nil ? "book" : "text.book.closed",
                    tone: [Tone.mint, .coral, .lavender][index % 3],
                    url: entry.url
                )
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: 0x5B7F80))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("كل نص بجوار مرجعه.")
                        .siyaqFont(.caption)
                        .foregroundStyle(Palette.navy)
                    Text(AboutSources.note)
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AboutSources.dorarNote)
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
        }
    }

    /// يُقرأ من الحزمة عند كل تشغيل: يتغير تلقائيًا مع MARKETING_VERSION و CURRENT_PROJECT_VERSION في Xcode.
    private var versionText: String { AppVersionText.make(info: Bundle.main.infoDictionary) }
}

struct AboutNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .siyaqFont(.sectionTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .siyaqFont(.caption)
                .foregroundStyle(Palette.muted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct SourceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: Tone
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                IconBubble(systemName: systemImage, tone: tone, size: 45)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .siyaqFont(.bodyBold)
                        .foregroundStyle(Palette.navy)
                    Text(subtitle)
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0x6B878A))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 16)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("يفتح في المتصفح")
    }
}
