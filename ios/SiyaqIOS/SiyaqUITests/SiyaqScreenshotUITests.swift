import XCTest

/// اختبارات واجهة قراءة الاقتباس من صورة؛ تُشغّل على Xcode والمحاكي.
/// - اختبار الإلغاء يفتح منتقي النظام الحقيقي؛ بقية حالات OCR تستخدم `SIYAQ_UITEST_OCR` (Debug فقط) بصورة مولّدة في الذاكرة
///   أو ببيانات ليست صورة أو يعطّل القارئ. Apple Vision نفسه حقيقي في حالة `sample`.
/// - خدمة بعنوان فارغ: لو بدأت مراجعة خطأً لظهرت شاشة «خدمة المراجعة غير متاحة»، فغيابها دليل على عدم البدء.
/// - الإعلانات الصوتية لا تُرى هنا؛ يُتحقق من الوسوم والقيم وإمكانية الوصول للعناصر مع أكبر خط.
final class SiyaqScreenshotUITests: XCTestCase {

    #if targetEnvironment(simulator)
    /// يُشغّل صراحةً بعد إضافة عينة الاختبار إلى مكتبة المحاكي فقط؛ لا يختار صورة من هاتف المستخدم.
    func testRealPhotoPickerImportsSeededImageAndExtractsLocally() throws {
        guard ProcessInfo.processInfo.environment["SIYAQ_UITEST_SEEDED_PHOTO"] == "1" else {
            throw XCTSkip("يحتاج عينة صور محلية مضافة إلى المحاكي قبل التشغيل")
        }
        // تهيئة مكتبة المحاكي قبل فتح المنتقي؛ أول تشغيل للصور يعرض شاشة تعريف بالنظام.
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["عدم السماح", "Don’t Allow", "Don't Allow"])).firstMatch
            if deny.waitForExistence(timeout: 2) { deny.tap() }
            let onboarding = photos.buttons.matching(NSPredicate(format: "label IN %@", ["متابعة", "Continue"])).firstMatch
            if onboarding.waitForExistence(timeout: 2) { onboarding.tap() }
        }
        let setup = XCTAttachment(string: photos.debugDescription)
        setup.name = "تهيئة مكتبة صور المحاكي"
        setup.lifetime = .keepAlways
        add(setup)
        photos.terminate()
        let app = SiyaqLauncher().launch(mode: "live", baseURL: "", reset: true)
        openReader(app)
        app.buttons["ocrPickImage"].tap()
        let picker = XCTAttachment(string: app.debugDescription)
        picker.name = "منتقي النظام قبل اختيار عينة المحاكي"
        picker.lifetime = .keepAlways
        add(picker)
        // شجرة الوصول الفعلية في iOS26 تعرض شبكة الصور كعناصر Image بهذا المعرف.
        // العينة المضافة إلى المحاكي هي الأحدث؛ النص المستخرج أدناه يثبت اختيارها فعلًا.
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "العينة لم تظهر في مكتبة صور النظام")
        // شبكة النظام تُرسم بعناصر AX Image مرئية لا تعلن isHittable؛ نقر مركز إطارها الفعلي.
        // الإطار مأخوذ من العنصر نفسه، واختبار نص العينة أدناه يثبت الاختيار الصحيح.
        XCTAssertGreaterThan(photo.frame.width, 40)
        XCTAssertTrue(app.frame.contains(photo.frame), "صورة العينة ليست داخل الشاشة")
        let center = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: photo.frame.midX, dy: photo.frame.midY))
        siyaqProof("صورة العينة في شبكة منتقي النظام", app)
        center.tap()
        let extract = app.buttons["ocrExtract"]
        XCTAssertTrue(extract.waitForExistence(timeout: 20), "لم يصل ملف الصورة إلى نافذة القص")
        siyaqReveal(extract, in: app)
        extract.tap()
        let draft = app.textViews["ocrDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 30))
        let text = draft.value as? String ?? ""
        XCTAssertTrue(text.contains("الصلاة") || text.contains("تقربوا"), "لم تُقرأ عينة المكتبة المتوقعة: \(text)")
        XCTAssertFalse(app.staticTexts["خدمة المراجعة غير متاحة"].exists)
        siyaqProof("قراءة ملف من منتقي صور النظام الحقيقي", app)
        app.buttons["ocrClose"].tap()
        XCTAssertTrue(app.textViews["quoteInput"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["quoteInput"].value as? String, "")
    }
    #endif

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ fixture: String, contentSize: String? = nil, file: String = #function) -> XCUIApplication {
        let app = XCUIApplication()
        let base = file.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        app.launchEnvironment = [
            "SIYAQ_UITEST_SANDBOX": "ocr-\(base.prefix(20))-\(UUID().uuidString.prefix(8))",
            "SIYAQ_UITEST_RESET": "1",
            "SIYAQ_UITEST_MODE": "live",
            "SIYAQ_UITEST_BASE_URL": "",
            "SIYAQ_UITEST_OCR": fixture,
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        SiyaqLauncher().waitUntilReady(app)
        return app
    }

    private func openReader(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let open = app.buttons["ocrOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), file: file, line: line)
        siyaqReveal(open, in: app, file: file, line: line)
        open.tap()
        XCTAssertTrue(app.buttons["ocrClose"].waitForExistence(timeout: 10), "نافذة القارئ مفتوحة", file: file, line: line)
    }

    /// يختار صورة الاختبار وينتظر القص، أو يتخطى بصدق إن لم يعلن Vision العربية على هذا الإصدار.
    private func pickSampleAndWaitForCrop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        if app.descendants(matching: .any)["ocrUnavailable"].waitForExistence(timeout: 3) {
            siyaqProof("القارئ العربي غير متاح على هذا الإصدار", app)
            throw XCTSkip("Apple Vision لا يعلن العربية على هذا الإصدار؛ النافذة تعرض عدم التوفر بصدق.")
        }
        let pick = app.buttons["ocrPickImage"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10), "زر اختيار الصورة جاهز", file: file, line: line)
        siyaqReveal(pick, in: app, file: file, line: line)
        pick.tap()
        XCTAssertTrue(app.buttons["ocrExtract"].waitForExistence(timeout: 15), "لم تجهز الصورة", file: file, line: line)
    }

    // MARK: - المسار الأساسي

    /// منتقي صور النظام الفعلي (بلا بديل اختبار): إلغاء الاختيار لا يمس الاقتباس أو يبدأ البحث.
    func testRealPhotoPickerCancellationKeepsQuote() {
        let app = SiyaqLauncher().launch(mode: "live", baseURL: "", reset: true)
        let input = app.textViews["quoteInput"]
        siyaqReveal(input, in: app)
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        input.typeText("قل هو الله أحد")
        if app.buttons["تم"].exists { app.buttons["تم"].tap() }
        openReader(app)
        let pick = app.buttons["ocrPickImage"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        siyaqReveal(pick, in: app)
        pick.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "منتقي صور النظام لم يفتح")
        #if targetEnvironment(simulator)
        _ = app.collectionViews.firstMatch.waitForExistence(timeout: 10)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "شجرة منتقي النظام على المحاكي"
        tree.lifetime = .keepAlways
        add(tree)
        #endif
        cancel.tap()
        XCTAssertTrue(app.buttons["ocrPickImage"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ocrExtract"].exists)
        XCTAssertFalse(app.textViews["ocrDraft"].exists)
        app.buttons["ocrClose"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "قل هو الله أحد")
        XCTAssertFalse(app.staticTexts["خدمة المراجعة غير متاحة"].exists)
    }

    /// صورة ← استخراج محلي ← مسودة قابلة للتعديل ← مربع الاقتباس؛ دون بدء أي مراجعة.
    func testSampleScreenshotGivesEditableDraftAndNeverStartsReview() throws {
        let app = launch("sample")
        openReader(app)
        try pickSampleAndWaitForCrop(app)
        XCTAssertTrue(app.descendants(matching: .any)["ocrPreview"].exists)
        siyaqProof("قص منطقة الاقتباس", app)

        let extract = app.buttons["ocrExtract"]
        siyaqReveal(extract, in: app)
        extract.tap()

        let draft = app.textViews["ocrDraft"]
        let error = app.descendants(matching: .any)["ocrError"]
        XCTAssertTrue(draft.waitForExistence(timeout: 30) || error.exists, "لا مسودة ولا خطأ")
        guard draft.exists else {
            siyaqProof("فشل الاستخراج", app)
            return XCTFail("فشل الاستخراج: \(error.label)")
        }
        XCTAssertTrue(element(containing: "ليس نصًا قرآنيًا موثقًا", in: app).exists, "تنبيه أن النص ليس موثقًا")
        let extracted = draft.value as? String ?? ""
        XCTAssertTrue(extracted.contains("الصلاة") || extracted.contains("تقربوا"), "النص: \(extracted)")
        siyaqProof("مسودة النص المستخرج", app)

        // التعديل قبل الاستخدام.
        siyaqReveal(draft, in: app)
        draft.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "المسودة لها تركيز قبل التعديل")
        draft.typeText(" ")
        let done = app.buttons["تم"]
        if done.exists { done.tap() }
        let use = app.buttons["ocrUseText"]
        siyaqReveal(use, in: app)
        use.tap()

        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["ocrClose"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed, "النافذة أُغلقت قبل فحص المربع")

        let input = app.textViews["quoteInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let inputValue = input.value as? String ?? ""
        XCTAssertTrue(inputValue.contains("الصلاة") || inputValue.contains("تقربوا"), "النص في المربع: \(inputValue)")
        XCTAssertFalse(app.staticTexts["نراجع الاقتباس…"].exists, "لم تبدأ المراجعة")
        XCTAssertFalse(app.staticTexts["خدمة المراجعة غير متاحة"].exists, "لم تُطلب مراجعة")
        XCTAssertFalse(app.textViews["ocrDraft"].exists, "النافذة أُغلقت")
        siyaqProof("النص في مربع الاقتباس دون بحث", app)
    }

    // MARK: - الأخطاء والتوفر

    func testUnreadableImageShowsHonestError() {
        let app = launch("unreadable")
        openReader(app)
        let pick = app.buttons["ocrPickImage"]
        siyaqReveal(pick, in: app)
        pick.tap()
        XCTAssertTrue(element(containing: "تعذرت قراءة هذا الملف كصورة", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ocrExtract"].exists)
        XCTAssertFalse(app.textViews["ocrDraft"].exists)
        siyaqProof("ملف ليس صورة", app)
    }

    func testUnsupportedDeviceShowsNoticeWithoutPicker() {
        let app = launch("unsupported")
        openReader(app)
        XCTAssertTrue(app.descendants(matching: .any)["ocrUnavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "اكتب الاقتباس بنفسك", in: app).exists)
        XCTAssertFalse(app.buttons["ocrPickImage"].exists, "لا اختيار صورة بلا قارئ")
    }

    /// الإغلاق يترك الصورة ولا يمس ما كتبه المستخدم؛ إعادة الفتح تبدأ من جديد.
    func testCloseDiscardsImageAndKeepsTypedInput() throws {
        let app = launch("sample")
        let input = app.textViews["quoteInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        siyaqReveal(input, in: app)
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "مربع الاقتباس له تركيز قبل الكتابة")
        input.typeText("نص كتبه المستخدم")
        let done = app.buttons["تم"]
        if done.exists { done.tap() }

        openReader(app)
        try pickSampleAndWaitForCrop(app)
        app.buttons["ocrClose"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "نص كتبه المستخدم")

        openReader(app)
        XCTAssertTrue(app.buttons["ocrPickImage"].waitForExistence(timeout: 5), "تبدأ من جديد")
        XCTAssertFalse(app.descendants(matching: .any)["ocrPreview"].exists, "الصورة السابقة لم تبقَ")
    }

    // MARK: - إمكانية الوصول والاتجاه

    /// أكبر خط: أدوات القص والأزرار قابلة للوصول؛ المنزلقات بوسوم وقيم عربية؛ زر الإغلاق في جهة البداية (اليمين).
    func testLargestTextSizeRTLAndAccessibleCropControls() throws {
        let app = launch("sample", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openReader(app)
        let close = app.buttons["ocrClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(close.frame.midX, app.frame.midX, "واجهة من اليمين: الإغلاق في جهة البداية")
        try pickSampleAndWaitForCrop(app)

        let top = app.sliders["ocrCropTop"]
        siyaqReveal(top, in: app)
        XCTAssertEqual(top.label, "بداية المنطقة من الأعلى")
        XCTAssertFalse((top.value as? String ?? "").isEmpty, "قيمة مقروءة لـ VoiceOver")
        let bottom = app.sliders["ocrCropBottom"]
        siyaqReveal(bottom, in: app)
        XCTAssertEqual(bottom.label, "نهاية المنطقة")

        let extract = app.buttons["ocrExtract"]
        siyaqReveal(extract, in: app)
        XCTAssertTrue(extract.isHittable)
        siyaqProof("أكبر خط — أدوات القص", app)
    }
}
