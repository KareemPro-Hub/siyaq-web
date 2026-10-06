import SwiftUI

/// الشاشة الرئيسية لتبويب «مراجعة»: الشعار، التقديم، مربع الاقتباس، زر المراجعة.
struct HomeView: View {
    @Bindable var session: ReviewSession
    @Binding var selectedTab: AppTab

    @State private var path: [ReviewRoute] = []
    @State private var showingScreenshotReader = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let usesRecordedSamples = ServiceConfiguration.current.source == .recordedSamples

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 0) {
                        inputSection
                            .padding(.top, 22)
                        examplesSection
                            .padding(.top, 30)
                    }
                    .padding(.horizontal, 23)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    Palette.hero.frame(height: 280)
                    Palette.ground
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if inputFocused {
                    HStack {
                        Spacer()
                        Button("تم") { inputFocused = false }
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 23)
                    .background(Palette.ground)
                }
            }
            .navigationDestination(for: ReviewRoute.self) { route in
                ReviewOutcomeScreen(
                    route: route,
                    session: session,
                    onSelect: { candidate in
                        guard !path.contains(where: { $0.isSelection }) else { return }
                        session.select(candidateID: candidate.id)
                        path = ReviewRoute.pushingSelection(candidate.id, onto: path)
                    }
                )
            }
        }
        .sheet(isPresented: $showingScreenshotReader) {
            ScreenshotTextSheet(replacesExistingInput: !session.input.isEmpty) { text in
                session.useExtractedText(text)
                AccessibilityNotification.Announcement("وُضع النص في مربع الاقتباس. راجعه ثم اضغط «ابدأ المراجعة».").post()
            }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty {
                session.cancelAll()
            } else if !newPath.contains(where: { $0.isSelection }) {
                session.cancelSelection()
            }
        }
    }

    // MARK: البطل

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    BrandLogo(size: 56)
                    Text("سِياق")
                        .siyaqFont(.brand)
                        .foregroundStyle(Palette.navy)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("سِياق")
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button {
                    selectedTab = .about
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0x5B7580))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.4)))
                }
                .accessibilityLabel("عن سِياق والمصادر")
            }
            .padding(.top, 6)

            Text("اقرأ بفهم")
                .siyaqFont(.heroTitle)
                .foregroundStyle(Palette.navy)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)

            Text("النص وسياقه وتفسيره، مع مرجعه.")
                .siyaqFont(.caption)
                .foregroundStyle(Palette.heroText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            // زخرفي فقط؛ يُخفى في أحجام الخط الكبيرة ليقترب مربع الاقتباس.
            if !dynamicTypeSize.isAccessibilitySize {
                ReaderScene()
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 23)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(HeroShape().fill(Palette.hero))
    }

    // MARK: مربع الاقتباس

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // أمثلة مسجلة: في اختبارات الواجهة وحدها (Debug)، ولا تظهر للمستخدم.
            if usesRecordedSamples {
                PreviewModeBadge()
            }

            Text("الاقتباس القرآني")
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.navy)
                .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { session.input },
                    set: { newInput in
                        // تحرير المستخدم يمسح الخطأ السابق قبل التحقق التالي، لا بعد ظهور خطأ جديد للمثال.
                        session.editInput(newInput)
                    }
                ))
                    .focused($inputFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .siyaqFont(.body)
                    .foregroundStyle(Palette.navy)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 240)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityLabel("الاقتباس القرآني")
                    .accessibilityHint("اكتب الآية أو جزءًا منها، كلمتين على الأقل")
                    .accessibilityIdentifier("quoteInput")

                if session.input.isEmpty {
                    Text("اكتب الاقتباس هنا…")
                        .siyaqFont(.body)
                        .foregroundStyle(Palette.placeholder)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
            .glowingInputFrame(cornerRadius: 20, isFocused: inputFocused)

            let length = session.input.utf16.count
            if length > 900 {
                Text("\(ArabicFormat.number(length)) من \(ArabicFormat.number(QuoteValidator.maxUTF16Length)) حرف")
                    .siyaqFont(.small)
                    .foregroundStyle(length > QuoteValidator.maxUTF16Length ? Palette.error : Palette.muted)
            }

            if let error = session.inputError {
                inputErrorView(error)
            }

            Button(action: submit) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                    Text("ابدأ المراجعة")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.forward")
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("startReview")
            .padding(.top, 4)

            // قراءة اقتباس من لقطة شاشة على الجهاز؛ يضع النص في المربع للمراجعة ولا يبدأ البحث.
            Button {
                inputFocused = false
                showingScreenshotReader = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "text.viewfinder")
                        .accessibilityHidden(true)
                    Text("اقرأ الاقتباس من صورة")
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("تختار لقطة شاشة، ويُقرأ نصها على جهازك لتراجعه قبل البحث")
            .accessibilityIdentifier("ocrOpen")

            if !usesRecordedSamples {
                Text("البحث عبر الإنترنت. المحفوظات متاحة دون اتصال.")
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    private func inputErrorView(_ error: ReviewError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .accessibilityHidden(true)
                Text(error.message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .siyaqFont(.caption)
            .foregroundStyle(Palette.error)
        }
    }

    // MARK: الأمثلة

    @ViewBuilder
    private var examplesSection: some View {
        if let library = PreviewLibrary.bundled {
            let samples = library.startingSamples
            VStack(alignment: .leading, spacing: 0) {
                AdaptiveRow {
                    Text("جرّب باقتباس")
                        .siyaqFont(.sectionTitle)
                        .foregroundStyle(Palette.navy)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Text("أمثلة للتجربة")
                        .siyaqFont(.small)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.bottom, 6)

                ForEach(Array(samples.enumerated()), id: \.element.file) { index, sample in
                    Button {
                        session.useSample(sample.result.quote)
                        submit()
                    } label: {
                        HStack(spacing: 11) {
                            IconBubble(systemName: "quote.bubble", tone: Tone.allCases[index % Tone.allCases.count])
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.result.quote)
                                    .siyaqFont(.body)
                                    .foregroundStyle(Palette.navy)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: 0x6B878A))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("يضع هذا الاقتباس في المربع ويبدأ المراجعة")

                    if index < samples.count - 1 {
                        Rectangle().fill(Palette.rowDivider).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: إجراءات

    private func submit() {
        inputFocused = false
        if session.start() {
            path = [.review]
        } else if let error = session.inputError {
            AccessibilityNotification.Announcement(error.message).post()
        }
    }
}
