import Foundation
import Observation

/// يدير قراءة اقتباس من صورة: تحميل ← فحص ← (قص) ← استخراج ← مراجعة المستخدم.
/// - لا يحفظ الصورة ولا بياناتها؛ يحتفظ فقط بنسخة مصغرة في الذاكرة ما دامت النافذة مفتوحة، ثم `discard()`.
/// - كل عملية تحمل رمزًا؛ نتيجة قديمة (صورة سابقة أو استخراج أُلغي) لا تستبدل الأحدث.
/// - النص المستخرج مسودة قابلة للتعديل؛ لا يبدأ أي بحث تلقائيًا.
@MainActor
@Observable
final class ScreenshotTextController {
    enum Phase: Equatable {
        /// لم تُختر صورة.
        case idle
        /// القارئ العربي المحلي غير متاح على هذا الجهاز.
        case unavailable
        case loadingImage
        /// الصورة جاهزة للقص والاستخراج.
        case ready
        case extracting
        /// المسودة جاهزة للمراجعة والتعديل.
        case extracted
        case failed(ScreenshotTextError)
    }

    private(set) var phase: Phase
    /// النص المستخرج القابل للتعديل.
    var draft: String = ""
    var crop: CropBand = .full
    private(set) var lowConfidenceLines = 0
    private(set) var image: PreparedImage? = nil

    var engineName: String { recognizer?.engineName ?? "" }
    var hasImage: Bool { image != nil }
    var isBusy: Bool { phase == .loadingImage || phase == .extracting }

    @ObservationIgnored private let recognizer: (any ArabicTextRecognizing)?
    @ObservationIgnored private let processor: any ScreenshotImageProcessing
    @ObservationIgnored private let limits: ScreenshotLimits
    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private var token = UUID()

    init(recognizer: (any ArabicTextRecognizing)?, processor: any ScreenshotImageProcessing, limits: ScreenshotLimits = .standard) {
        self.recognizer = recognizer
        self.processor = processor
        self.limits = limits
        self.phase = (recognizer?.isArabicSupported ?? false) ? .idle : .unavailable
    }

    // MARK: التحميل

    /// يحمّل صورة جديدة من بيانات في الذاكرة (صورة اختبار الواجهة ومضاعفات الاختبار).
    /// `loader` يعيد nil إذا ألغى المستخدم الاختيار. صورة جديدة تلغي أي تحميل أو استخراج سابق.
    /// منتقي الصور لا يستخدم هذا المسار؛ يستخدم `loadPrepared` بملف يُفحص حجمه قبل قراءته.
    func load(_ loader: @escaping @Sendable () async throws -> Data?) {
        let processor = self.processor
        let limits = self.limits
        loadPrepared {
            guard let data = try await loader() else { return nil }
            try Task.checkCancellation()
            try limits.validate(byteCount: data.count)
            // الفك والتصغير خارج الخيط الرئيسي؛ البيانات الأصلية لا تُخزَّن بعد هذا السطر.
            let prepared = try await Task.detached(priority: .userInitiated) {
                try processor.prepare(data, limits: limits)
            }.value
            try Task.checkCancellation() // المهمة المنفصلة لا ترث الإلغاء؛ لا نُكمل بعده.
            return prepared
        }
    }

    /// يحمّل صورة يجهزها `loader` بنفسه نسخةً مصغرة (منتقي الصور: فحص حجم الملف ثم فك مصغر منه).
    /// nil = ألغى المستخدم. القواعد نفسها: الأحدث يغلب، والإلغاء والإغلاق يُهملان أي نتيجة متأخرة.
    func loadPrepared(_ loader: @escaping @Sendable () async throws -> PreparedImage?) {
        guard phase != .unavailable else { return }
        let current = restart()
        image = nil
        draft = ""
        crop = .full
        lowConfidenceLines = 0
        phase = .loadingImage
        task = Task { [weak self] in
            let outcome: Result<PreparedImage?, ScreenshotTextError>
            do {
                let prepared = try await loader()
                try Task.checkCancellation()
                outcome = .success(prepared)
            } catch let error as ScreenshotTextError {
                outcome = .failure(error)
            } catch is CancellationError {
                return
            } catch {
                outcome = .failure(.loadFailed)
            }
            self?.finishLoad(outcome, token: current)
        }
    }

    private func finishLoad(_ outcome: Result<PreparedImage?, ScreenshotTextError>, token current: UUID) {
        guard current == token else { return } // صورة أحدث اختيرت بعد هذه.
        task = nil
        switch outcome {
        case .success(let prepared?):
            image = prepared
            phase = .ready
        case .success(nil):
            phase = .idle // ألغى المستخدم الاختيار
        case .failure(let error):
            image = nil
            phase = .failed(error)
        }
    }

    // MARK: الاستخراج

    /// يستخرج النص من منطقة القص. نقرة مكررة أثناء الاستخراج لا تبدأ استخراجًا ثانيًا.
    func extract() {
        guard let recognizer, let image, phase == .ready || isRetryableFailure else { return }
        let current = restart()
        phase = .extracting
        let region = crop.visionRegion
        task = Task { [weak self] in
            let outcome: Result<ExtractedText, ScreenshotTextError>
            do {
                let lines = try await recognizer.recognizeLines(in: image, region: region)
                try Task.checkCancellation()
                let extracted = ExtractedTextAssembler.assemble(lines)
                if extracted.text.isEmpty {
                    outcome = .failure(.noTextFound)
                } else if !ExtractedTextAssembler.containsArabicLetters(extracted.text) {
                    outcome = .failure(.noArabicText)
                } else {
                    outcome = .success(extracted)
                }
            } catch is CancellationError {
                return
            } catch let error as ScreenshotTextError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.extractionFailed)
            }
            await self?.finishExtraction(outcome, token: current)
        }
    }

    private var isRetryableFailure: Bool {
        if case .failed(let error) = phase { return error.canRetryOnSameImage && image != nil }
        return false
    }

    private func finishExtraction(_ outcome: Result<ExtractedText, ScreenshotTextError>, token current: UUID) {
        guard current == token else { return } // أُلغي أو بدأت عملية أحدث.
        task = nil
        switch outcome {
        case .success(let extracted):
            draft = extracted.text
            lowConfidenceLines = extracted.lowConfidenceLines
            phase = .extracted
        case .failure(let error):
            phase = .failed(error)
        }
    }

    /// يعود من المسودة أو الفشل إلى القص لإعادة الاستخراج.
    func backToCrop() {
        guard image != nil, !isBusy else { return }
        draft = ""
        phase = .ready
    }

    // MARK: الإلغاء والتنظيف

    /// يوقف العملية الجارية؛ نتيجتها المتأخرة تُهمل.
    func cancel() {
        restart()
        switch phase {
        case .extracting: phase = image == nil ? .idle : .ready
        case .loadingImage: phase = .idle
        default: break
        }
    }

    /// يمسح كل شيء: الصورة المصغرة والمسودة. يُستدعى عند إغلاق النافذة.
    func discard() {
        restart()
        image = nil
        draft = ""
        crop = .full
        lowConfidenceLines = 0
        if phase != .unavailable { phase = .idle }
    }

    /// النص الذي يُوضع في مربع الاقتباس، أو nil إن كانت المسودة فارغة أو لم يكتمل الاستخراج.
    var acceptedText: String? {
        guard phase == .extracted else { return nil }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    @discardableResult
    private func restart() -> UUID {
        task?.cancel()
        task = nil
        token = UUID()
        return token
    }
}
