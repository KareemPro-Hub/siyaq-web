import XCTest
@testable import Siyaq

/// المرحلة ٤: ما يمكن إثباته آليًا من التباين والرسائل والمشاركة والمحفوظات.
/// الفحص البصري وVoiceOver وDynamic Type الفعلي يحتاج محاكيًا أو جهازًا (انظر قائمة التحقق في التسليم).
final class ContrastTests: XCTestCase {
    private func assertContrast(_ a: UInt32, _ b: UInt32, atLeast minimum: Double, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let ratio = BrandTokens.contrast(a, b)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(label): \(String(format: "%.2f", ratio))", file: file, line: line)
    }

    func testWhiteTextButtonsUseTealDark() {
        // كل زر بنص أبيض على #007F89.
        assertContrast(BrandTokens.white, BrandTokens.tealDark, atLeast: 4.5, "أبيض على tealDark")
        // التركواز الفاتح لا يصلح خلفية لنص أبيض؛ لذا لا يُستخدم لذلك.
        XCTAssertLessThan(BrandTokens.contrast(BrandTokens.white, BrandTokens.teal), 3.0)
    }

    func testBodyAndSecondaryText() {
        assertContrast(BrandTokens.navy, BrandTokens.ground, atLeast: 7, "كحلي على الأرضية")
        assertContrast(BrandTokens.navy, BrandTokens.hero, atLeast: 7, "كحلي على النعناع")
        assertContrast(BrandTokens.navy, BrandTokens.lavenderBackground, atLeast: 7, "كحلي على البنفسجي")
        assertContrast(BrandTokens.navy, BrandTokens.coralBackground, atLeast: 7, "كحلي على المرجاني")
        assertContrast(BrandTokens.navy, BrandTokens.mintBackground, atLeast: 7, "كحلي على النعناعي")
        assertContrast(BrandTokens.eyebrow, BrandTokens.hero, atLeast: 4.5, "عنوان صغير على النعناع")
        assertContrast(BrandTokens.heroText, BrandTokens.hero, atLeast: 4.5, "وصف البطل على النعناع")
        assertContrast(BrandTokens.eyebrow, BrandTokens.segmentTrack, atLeast: 4.5, "تبويب غير محدد")
        assertContrast(BrandTokens.muted, BrandTokens.white, atLeast: 4.5, "ثانوي على البطاقة")
        assertContrast(BrandTokens.error, BrandTokens.ground, atLeast: 4.5, "رسالة خطأ")
    }

    func testIncreasedContrastVariants() {
        assertContrast(BrandTokens.mutedHigh, BrandTokens.ground, atLeast: 6, "ثانوي عند زيادة التباين")
        assertContrast(BrandTokens.eyebrowHigh, BrandTokens.hero, atLeast: 6, "عنوان صغير عند زيادة التباين")
        assertContrast(BrandTokens.placeholderHigh, BrandTokens.white, atLeast: 4.5, "نص بديل عند زيادة التباين")
    }

    /// قيد معروف وموثق: الرمادي المعتمد على الأرضية ٤٫٤٨:١ (أقل بفارق ضئيل من ٤٫٥). لا نغير اللون المعتمد؛
    /// يُصحَّح تلقائيًا عند «زيادة التباين». الاختبار يثبت القيمة حتى لا يتغير أحدهما دون انتباه.
    func testKnownMutedOnGroundLimitation() {
        XCTAssertEqual(BrandTokens.contrast(BrandTokens.muted, BrandTokens.ground), 4.48, accuracy: 0.01)
    }
}

final class MessagesAndSharingTests: XCTestCase {
    func testEveryErrorHasArabicTitleAndMessage() {
        let all: [ReviewError] = [
            .emptyQuote, .tooFewWords, .quoteTooLong, .notConfigured, .insecureEndpoint,
            .offline, .timedOut, .unreachable, .secureConnectionFailed,
            .http(status: 400, message: nil), .http(status: 413, message: nil), .http(status: 415, message: nil),
            .http(status: 503, message: nil), .http(status: 418, message: nil), .invalidResponse, .cancelled,
            .previewUnavailable, .previewQuoteNotInSamples, .previewSelectionNotInSamples,
            .aiNotConfigured, .rateLimited(retryAfterSeconds: nil), .rateLimited(retryAfterSeconds: 12), .explanationNotEligible,
        ]
        let arabic = CharacterSet(charactersIn: "\u{0600}"..."\u{06FF}")
        for error in all {
            XCTAssertFalse(error.title.isEmpty, "\(error)")
            XCTAssertFalse(error.message.isEmpty, "\(error)")
            XCTAssertNotNil(error.message.rangeOfCharacter(from: arabic), "\(error)")
            XCTAssertFalse(error.systemImage.isEmpty)
        }
        // الأخطاء التي لا تُصلحها إعادة المحاولة لا تعرض زرها.
        XCTAssertFalse(ReviewError.aiNotConfigured.canRetry)
        XCTAssertFalse(ReviewError.explanationNotEligible.canRetry)
        XCTAssertFalse(ReviewError.tooFewWords.canRetry)
        // تعذر الاتصال أو التهيئة: رسالة واضحة مع «إعادة المحاولة»، دون إحالة إلى إعدادات.
        for error in [ReviewError.notConfigured, .insecureEndpoint, .offline, .timedOut, .unreachable,
                      .secureConnectionFailed, .invalidResponse, .http(status: 503, message: nil),
                      .http(status: 401, message: nil), .http(status: 403, message: nil)] {
            XCTAssertTrue(error.canRetry, "\(error)")
            for hint in ["«عن سِياق»", "وضع المعاينة", "كلمة الوصول", "كلمة وصول", "عنوان الخدمة", "الوضع الحي"] {
                XCTAssertFalse(error.message.contains(hint), "\(error): \(hint)")
            }
        }
        XCTAssertFalse(ReviewError.http(status: 400, message: nil).canRetry)
    }

    func testShareIncludesTafsirSourcesWithoutTafsirText() throws {
        let result = try Samples.result("01-partial")
        let candidate = try XCTUnwrap(result.selected)
        let text = ShareText.make(result: result, candidate: candidate)

        // كتابان فريدان رغم تكرار مجاهد مرتين.
        XCTAssertEqual(ShareText.tafsirBooks(in: result).map(\.name), ["تفسير مجاهد", "تفسير سفيان الثوري"])
        // رابط موضع النص المعروض (صفحة الكتاب)، لا رابط بيانات API ولا الصفحة الرئيسية.
        XCTAssertTrue(text.contains("التفسير المنقول: تفسير مجاهد — مجاهد بن جبر — https://quranpedia.net/tafsir/an-nisa/43?book=269"), text)
        XCTAssertTrue(text.contains("مصدر النص: الموسوعة القرآنية — https://quranpedia.net/surah/1/4/43"), text)
        XCTAssertTrue(text.contains("تفسير سفيان الثوري"))
        // لا يُشارك نص التفسير نفسه.
        for entry in result.tafsir[0].entries {
            XCTAssertFalse(text.contains(entry.text))
        }
        // النص القرآني يبدأ المشاركة كما ورد (مع أي محارف غير مرئية في المصدر).
        XCTAssertTrue(text.hasPrefix(candidate.verses[0].text))
    }

    func testShareWithoutTafsirHasNoTafsirLine() throws {
        let result = try Samples.result("05-full-no-tafsir")
        let text = ShareText.make(result: result, candidate: try XCTUnwrap(result.selected))
        XCTAssertFalse(text.contains("التفسير المنقول"))
        XCTAssertTrue(text.contains("سورة الإخلاص · الآية ١"))
    }
}

/// المحفوظات تُقرأ من القرص فقط، ولا تحتاج أي خدمة.
final class OfflineSavedReadingTests: XCTestCase {
    func testSavedResultsReloadWithoutAnyService() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiyaqOffline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SavedResultsStore(directory: directory)
        store.save(ReviewOutcome(result: try Samples.result("01-partial"), origin: .live))
        store.save(ReviewOutcome(result: try Samples.result("06-selected-possible"), origin: .preview))

        // «إعادة تشغيل» دون شبكة: مخزن جديد من الملف فقط.
        let reopened = SavedResultsStore(directory: directory)
        XCTAssertEqual(reopened.entries.count, 2)
        let possible = try XCTUnwrap(reopened.entries.first)
        XCTAssertEqual(possible.origin, .preview)
        XCTAssertTrue(possible.result.isSelectedPossible, "التنبيه يبقى بعد الحفظ")
        XCTAssertEqual(possible.result.differences.count, 6)
        // كل ما تعرضه الشاشة متاح محليًا: النص والسياق والتفسير والمصادر.
        let partial = try XCTUnwrap(reopened.entries.last)
        XCTAssertFalse(partial.result.context.isEmpty)
        XCTAssertEqual(partial.result.tafsir.first?.entries.count, 3)
        XCTAssertFalse(ShareText.make(result: partial.result, candidate: try XCTUnwrap(partial.candidate)).isEmpty)
    }
}

/// دورة حركة الإطار، مستقلة عن SwiftUI.
final class KareemEditsTests: XCTestCase {

    func testBeamPhaseStaysInsideUnitRangeAndLoops() {
        let period = InputBorderBeam.period
        XCTAssertEqual(InputBorderBeam.phase(at: 0), 0)
        XCTAssertEqual(InputBorderBeam.phase(at: period / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(InputBorderBeam.phase(at: period * 3 + period / 4), 0.25, accuracy: 1e-9)
        XCTAssertEqual(InputBorderBeam.phase(at: -period / 4), 0.75, accuracy: 1e-9)
        XCTAssertEqual(InputBorderBeam.phase(at: .infinity), 0)
        XCTAssertEqual(InputBorderBeam.phase(at: 5, period: 0), 0)
        for t in stride(from: -20.0, through: 20, by: 0.37) {
            let p = InputBorderBeam.phase(at: t)
            XCTAssertTrue(p >= 0 && p < 1, "\(t) → \(p)")
        }
    }

}
