import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

/// صورة من منتقي الصور تُستلم **ملفًا** مؤقتًا يديره النظام، لا `Data` في الذاكرة.
/// داخل الاستلام فقط (والملف ما زال موجودًا): فحص حجمه من خصائصه، ثم فك نسخة مصغرة منه مباشرة.
/// لا يُنسخ الملف إلى أي مكان، ولا يُحفظ رابطه، ولا يُقرأ محتواه قبل فحص الحجم.
/// أخطاء الفحص تُحمل في النتيجة (لا تُرمى) حتى تصل رسالتها كما هي، أيًّا كان تغليف النظام للأخطاء.
struct PickedScreenshotFile: Transferable {
    let outcome: Result<PreparedImage, ScreenshotTextError>

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            do {
                let image = try ScreenshotTextEngines.imageProcessor().prepare(fileAt: received.file, limits: .standard)
                return PickedScreenshotFile(outcome: .success(image))
            } catch let error as ScreenshotTextError {
                return PickedScreenshotFile(outcome: .failure(error))
            } catch {
                return PickedScreenshotFile(outcome: .failure(.loadFailed))
            }
        }
    }
}

extension ScreenshotTextController {
    /// المحرك المتاح فعليًا على الجهاز. في اختبارات الواجهة (Debug) قد يُعطَّل عمدًا.
    static func forCurrentDevice() -> ScreenshotTextController {
        #if DEBUG
        if UITestSandbox.current?.ocrFixture == .unsupported {
            return ScreenshotTextController(recognizer: nil, processor: ScreenshotTextEngines.imageProcessor())
        }
        #endif
        return ScreenshotTextController(recognizer: ScreenshotTextEngines.bestAvailable(),
                                        processor: ScreenshotTextEngines.imageProcessor())
    }
}

/// نافذة «اقرأ الاقتباس من صورة»: اختيار ← قص ← استخراج محلي ← مراجعة وتعديل ← وضع النص في مربع الاقتباس.
/// لا تبدأ المراجعة، ولا تحفظ الصورة، ولا ترسلها إلى أي خادم.
struct ScreenshotTextSheet: View {
    /// هل في مربع الاقتباس نص سيُستبدل؟
    let replacesExistingInput: Bool
    let onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = ScreenshotTextController.forCurrentDevice()
    @State private var pickerItem: PhotosPickerItem? = nil
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    NoticeCard(.info, message: "تُقرأ الصورة على جهازك فقط، ولا تُرفع إلى أي خادم ولا تُحفظ. النص المستخرج مسودة تراجعها قبل البحث.")
                    content
                }
                .padding(.horizontal, 23)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.ground.ignoresSafeArea())
            .navigationTitle("قراءة من صورة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.ground, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if draftFocused {
                    HStack {
                        Spacer()
                        Button("تم") { draftFocused = false }
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 23)
                    .background(Palette.ground)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق", action: close)
                        .accessibilityIdentifier("ocrClose")
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil // يسمح باختيار الصورة نفسها مرة أخرى
            controller.loadPrepared {
                // لا تمثيل صورة ملفيًّا لهذا العنصر ← ليست صورة مقروءة.
                guard let picked = try await item.loadTransferable(type: PickedScreenshotFile.self) else {
                    throw ScreenshotTextError.unreadableImage
                }
                return try picked.outcome.get()
            }
        }
        .onChange(of: controller.phase) { _, phase in announce(phase) }
        .onDisappear { controller.discard() }
    }

    // MARK: الأقسام

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("من لقطة شاشة")
                .siyaqFont(.eyebrow)
                .foregroundStyle(Palette.eyebrow)
            Text("اقرأ الاقتباس من صورة.")
                .siyaqFont(.screenTitle)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .unavailable:
            NoticeCard(.warning, title: "غير متاحة على هذا الجهاز", message: ScreenshotTextError.arabicUnsupported.message)
                .accessibilityIdentifier("ocrUnavailable")
        case .idle:
            pickButton(title: "اختر صورة من مكتبة الصور", primary: true)
            Text("اختر لقطة شاشة فيها الاقتباس. يمكنك بعدها تحديد منطقته قبل القراءة.")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .loadingImage:
            progress("نجهّز الصورة…")
        case .ready:
            preview
            cropControls
            Button(action: controller.extract) {
                Label("استخرج النص", systemImage: "text.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("ocrExtract")
            pickButton(title: "اختر صورة أخرى", primary: false)
        case .extracting:
            preview
            progress("نقرأ النص على جهازك…")
        case .extracted:
            draftEditor
        case .failed(let error):
            NoticeCard(.warning, title: "تعذرت القراءة", message: error.message)
                .accessibilityIdentifier("ocrError")
            if error.canRetryOnSameImage && controller.hasImage {
                Button("عدّل منطقة القص وأعد المحاولة", action: controller.backToCrop)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("ocrBackToCrop")
            }
            pickButton(title: "اختر صورة أخرى", primary: false)
        }
    }

    // MARK: الاختيار

    @ViewBuilder
    private func pickButton(title: String, primary: Bool) -> some View {
        let label = Label(title, systemImage: "photo.on.rectangle")
        #if DEBUG
        if let fixture = UITestSandbox.current?.ocrFixture, fixture != .unsupported {
            styled(Button { loadFixture(fixture) } label: { label }, primary: primary)
                .accessibilityIdentifier("ocrPickImage")
        } else {
            styled(PhotosPicker(selection: $pickerItem, matching: .images) { label }, primary: primary)
                .accessibilityIdentifier("ocrPickImage")
        }
        #else
        styled(PhotosPicker(selection: $pickerItem, matching: .images) { label }, primary: primary)
            .accessibilityIdentifier("ocrPickImage")
        #endif
    }

    @ViewBuilder
    private func styled<V: View>(_ view: V, primary: Bool) -> some View {
        if primary {
            view.buttonStyle(PrimaryButtonStyle())
        } else {
            view.buttonStyle(SecondaryButtonStyle())
        }
    }

    #if DEBUG
    private func loadFixture(_ fixture: UITestSandbox.OCRFixture) {
        #if canImport(UIKit)
        let data = fixture == .sample ? ScreenshotTestSample.pngData() : ScreenshotTestSample.unreadable
        controller.load { data }
        #endif
    }
    #endif

    // MARK: المعاينة والقص

    @ViewBuilder
    private var preview: some View {
        if let handle = controller.image?.handle, CFGetTypeID(handle) == CGImage.typeID {
            let crop = controller.crop
            Image(decorative: handle as! CGImage, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geometry in
                        let height = geometry.size.height
                        VStack(spacing: 0) {
                            Color.black.opacity(0.45).frame(height: height * crop.top)
                            Rectangle().stroke(Palette.teal, lineWidth: 3)
                            Color.black.opacity(0.45).frame(height: height * (1 - crop.bottom))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: 360)
                .opacity(controller.phase == .extracting ? 0.6 : 1)
                .accessibilityElement()
                .accessibilityLabel("الصورة المختارة")
                .accessibilityValue("المنطقة المحددة من \(percent(crop.top)) إلى \(percent(crop.bottom)) من ارتفاعها")
                .accessibilityIdentifier("ocrPreview")
        }
    }

    private var cropControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("حدّد منطقة الاقتباس")
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.navy)
                .accessibilityAddTraits(.isHeader)
            cropSlider(
                title: "بداية المنطقة من الأعلى",
                value: Binding(get: { controller.crop.top }, set: { controller.crop = controller.crop.withTop($0) }),
                identifier: "ocrCropTop"
            )
            cropSlider(
                title: "نهاية المنطقة",
                value: Binding(get: { controller.crop.bottom }, set: { controller.crop = controller.crop.withBottom($0) }),
                identifier: "ocrCropBottom"
            )
            if !controller.crop.isFull {
                Button("استخدم الصورة كاملة") { controller.crop = .full }
                    .siyaqFont(.captionBold)
                    .foregroundStyle(Palette.tealDark)
                    .frame(minHeight: 44)
            }
        }
        .siyaqCard()
    }

    private func cropSlider(title: String, value: Binding<Double>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveRow {
                Text(title)
                    .siyaqFont(.caption)
                    .foregroundStyle(Palette.navy)
                Spacer(minLength: 0)
                Text(percent(value.wrappedValue))
                    .siyaqFont(.small)
                    .foregroundStyle(Palette.muted)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: 0...1, step: 0.01)
                .tint(Palette.tealDark)
                .accessibilityLabel(title)
                .accessibilityValue(percent(value.wrappedValue))
                .accessibilityIdentifier(identifier)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(ArabicFormat.number(Int((value * 100).rounded())))٪"
    }

    // MARK: المسودة

    private var draftEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoticeCard(.warning, title: "راجع النص قبل البحث",
                       message: "هذا نص مستخرج آليًا من صورة، وقد يخطئ في حرف أو تشكيل. ليس نصًا قرآنيًا موثقًا؛ صحّحه ثم ضعه في مربع الاقتباس.")
            if controller.lowConfidenceLines > 0 {
                NoticeCard(.info, message: "بعض الأسطر غير واضحة في الصورة؛ دقّق فيها خاصة.")
            }
            Text("النص المستخرج")
                .siyaqFont(.captionBold)
                .foregroundStyle(Palette.navy)
                .accessibilityHidden(true)
            TextEditor(text: Binding(get: { controller.draft }, set: { controller.draft = $0 }))
                .focused($draftFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 280)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.inputBorder, lineWidth: 1))
                .accessibilityLabel("النص المستخرج")
                .accessibilityHint("قابل للتعديل. راجعه وصحّحه قبل وضعه في مربع الاقتباس")
                .accessibilityIdentifier("ocrDraft")

            Button {
                guard let text = controller.acceptedText else { return }
                controller.discard()
                onUse(text)
                dismiss()
            } label: {
                Label("ضع النص في مربع الاقتباس", systemImage: "arrow.down.doc")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(controller.acceptedText == nil)
            .accessibilityIdentifier("ocrUseText")

            Text(replacesExistingInput
                 ? "سيحل محل النص الموجود في مربع الاقتباس. لن تبدأ المراجعة حتى تضغط «ابدأ المراجعة»."
                 : "لن تبدأ المراجعة حتى تضغط «ابدأ المراجعة».")
                .siyaqFont(.small)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("أعد تحديد المنطقة", action: controller.backToCrop)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("ocrBackToCrop")
        }
    }

    // MARK: الانتظار والإعلانات

    private func progress(_ title: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .accessibilityHidden(true)
            Text(title)
                .siyaqFont(.body)
                .foregroundStyle(Palette.navy)
            Button("إيقاف", action: controller.cancel)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("ocrStop")
        }
        .frame(maxWidth: .infinity)
        .siyaqCard()
        .accessibilityElement(children: .contain)
    }

    private func announce(_ phase: ScreenshotTextController.Phase) {
        let message: String?
        switch phase {
        case .ready: message = "الصورة جاهزة. حدّد منطقة الاقتباس ثم اضغط «استخرج النص»."
        case .extracted: message = "استُخرج النص. راجعه وصحّحه قبل استخدامه."
        case .failed(let error): message = error.message
        default: message = nil
        }
        if let message { AccessibilityNotification.Announcement(message).post() }
    }

    private func close() {
        controller.discard()
        dismiss()
    }
}
