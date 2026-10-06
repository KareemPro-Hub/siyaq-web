import XCTest

/// اختبارات واجهة إضافية لتسليم Cowork (المرحلة ٦).
/// - كل اختبار في مساحة معزولة (`SIYAQ_UITEST_SANDBOX`)؛ لا تُمس محفوظات المستخدم.
/// - تعتمد على أمثلة المحرك المعتمدة المضمنة (وضع المعاينة) فلا تحتاج شبكة ولا OpenAI.
/// - اختبار حي واحد اختياري يعمل فقط إذا مُرر `SIYAQ_UITEST_LIVE_BASE_URL` لبيئة الاختبار.
/// - اسم الصنف مختلف عن `SiyaqUITests` لدى Codex حتى يُدمجا معًا دون تعارض.
final class SiyaqFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // إعدادات الاتصال (الوضع، العنوان، كلمة الوصول) حُذفت من الواجهة بطلب كريم (٣ أكتوبر)،
    // فحُذف معها testPrivateAccessSettingsSaveAndRemove وتجربة SecureField التشخيصية.

    /// لا إعدادات اتصال في «عن سِياق»: لا وضع معاينة ولا عنوان ولا كلمة وصول، ويبقى سطر الإصدار.
    func testAboutHasNoConnectionSettings() {
        let app = SiyaqLauncher().launch(mode: "live", baseURL: "", reset: true)
        tapSiyaqTab("عن سِياق", in: app)
        XCTAssertTrue(app.staticTexts["تطبيق سِياق"].waitForExistence(timeout: 5))
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(element(containing: "سِياق — الإصدار", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        XCTAssertFalse(app.textFields["عنوان خدمة المراجعة"].exists)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        for text in ["الإعدادات", "مصدر النتائج", "الوضع الحي", "وضع المعاينة", "حفظ العنوان", "حفظ الوصول", "إزالة الوصول"] {
            XCTAssertFalse(element(containing: text, in: app).exists, text)
        }
        siyaqProof("عن سِياق دون إعدادات اتصال", app)
    }

    // MARK: - الاختيار بين المواضع

    /// choices: القائمة محدودة وتصرّح بذلك، ولا يختار التطبيق نيابة عن المستخدم.
    /// في المعاينة لا توجد نتيجة مسجلة لاختيار موضع من «غفور رحيم»، فتظهر رسالة صريحة بدل نتيجة مختلقة.
    func testChoicesListIsLimitedAndNeverAutoSelects() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        let example = button(containing: "غفور رحيم", in: app)
        siyaqReveal(example, in: app)
        example.tap()

        XCTAssertTrue(app.staticTexts["أي موضع تقصد؟"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "تعرض القائمة ١٢ من ٤٢ موضعًا", in: app).exists)
        XCTAssertFalse(app.staticTexts["اقتباسك في سياقه."].exists, "لا اختيار تلقائي")
        siyaqProof("اختيار الموضع — قائمة محدودة", app)

        let first = button(containing: "سورة البقرة · الآية ١٧٣", in: app)
        siyaqReveal(first, in: app)
        first.tap()
        XCTAssertTrue(element(containing: "غير مسجلة في أمثلة المعاينة", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["اقتباسك في سياقه."].exists)
    }

    /// possible ← اختيار ٤:٤٣: يبقى تحذير التشابه ومقارنة الألفاظ، ولا يُعرض طلب شرح.
    func testPossibleSelectionKeepsWarningAndComparison() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        let example = button(containing: "لا تقربوا الصلاه وانتم سكارى", in: app)
        siyaqReveal(example, in: app)
        example.tap()

        XCTAssertTrue(app.staticTexts["مواضع محتملة."].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "تشابه محتمل، وليس إثباتًا", in: app).exists)

        let candidate = button(containing: "سورة النساء · الآية ٤٣", in: app)
        siyaqReveal(candidate, in: app)
        candidate.tap()

        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "موضع محتمل اخترته، وليس مطابقة مؤكدة", in: app).exists)
        XCTAssertTrue(element(containing: "مقارنة الألفاظ", in: app).exists)
        XCTAssertFalse(app.buttons["explainButton"].exists)
        siyaqProof("تشابه محتمل مختار", app)
    }

    /// اختياري: الاختيار بين المواضع على خدمة حية محلية. يُتخطى إن لم يُمرر العنوان.
    func testLiveChoiceSelectionOpensChosenVerse() throws {
        guard let base = ProcessInfo.processInfo.environment["SIYAQ_UITEST_LIVE_BASE_URL"], !base.isEmpty else {
            throw XCTSkip("SIYAQ_UITEST_LIVE_BASE_URL غير مضبوط؛ هذا الاختبار يحتاج خدمة المراجعة المحلية.")
        }
        let app = SiyaqLauncher().launch(mode: "live", baseURL: base, reset: true)
        let example = button(containing: "غفور رحيم", in: app)
        siyaqReveal(example, in: app)
        example.tap()
        XCTAssertTrue(app.staticTexts["أي موضع تقصد؟"].waitForExistence(timeout: 40))
        let candidate = button(containing: "سورة البقرة · الآية ١٨٢", in: app)
        siyaqReveal(candidate, in: app)
        candidate.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["سورة البقرة · الآية ١٨٢"].exists)
        siyaqProof("اختيار موضع حي", app)
    }

    /// عينة كريم بعد OCR: تُعرض كتشابه محتمل، ثم يُختار الموضع وتُعرض مصادره المباشرة.
    func testLiveIbrahimMissingTafsirLinksToTheContainingDorarPassage() throws {
        guard let base = ProcessInfo.processInfo.environment["SIYAQ_UITEST_LIVE_BASE_URL"], !base.isEmpty else {
            throw XCTSkip("عنوان الخدمة الحية غير مضبوط لفحص رابط المقطع")
        }
        let app = SiyaqLauncher().launch(mode: "live", baseURL: base, reset: true)
        submit("ولا تحسبن الله غافلا عما يعمل الظالمون", in: app)
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 40))
        let tafsir = app.buttons["التفسير"]
        siyaqReveal(tafsir, in: app)
        tafsir.tap()
        let title = "تفسير سورة إبراهيم، الآيات ٤٢–٤٦ في الدرر السنية"
        let passage = sourceLink(title, in: app)
        XCTAssertTrue(passage.waitForExistence(timeout: 8))
        siyaqReveal(passage, in: app)
        XCTAssertFalse(element(containing: "فهرس تفسير سورة إبراهيم", in: app).exists)
        siyaqProof("إبراهيم٤٢ — الإحالة إلى مقطع الدرر المحدد", app)
    }

    func testLiveIbrahim43ShowsItsApprovedTafsirAndSources() throws {
        guard let base = ProcessInfo.processInfo.environment["SIYAQ_UITEST_LIVE_BASE_URL"], !base.isEmpty else {
            throw XCTSkip("عنوان الخدمة الحية غير مضبوط لفحص تفسير إبراهيم٤٣")
        }
        let app = SiyaqLauncher().launch(mode: "live", baseURL: base, reset: true)
        submit("مهطعين مقنعي", in: app)
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 40))
        XCTAssertTrue(element(containing: "سورة إبراهيم", in: app).exists)
        let tafsir = app.buttons["التفسير"]
        siyaqReveal(tafsir, in: app)
        tafsir.tap()
        XCTAssertTrue(app.staticTexts["تفسير مجاهد"].firstMatch.waitForExistence(timeout: 8))
        let link = sourceLink("افتح التفسير في مصدره", in: app)
        siyaqReveal(link, in: app)
        siyaqProof("إبراهيم٤٣ — تفسير مجاهد للآية المحددة", app)
        let sources = app.buttons["المصدر"]
        siyaqReveal(sources, in: app)
        sources.tap()
        siyaqReveal(sourceLink("افتح التفسير في مصدره", in: app), in: app)
        siyaqProof("إبراهيم٤٣ — إحالة بطاقة المصدر للآية والكتاب", app)
    }

    func testLiveOCRNoiseRequiresSelectionAndShowsTafsirSources() throws {
        guard let base = ProcessInfo.processInfo.environment["SIYAQ_UITEST_LIVE_BASE_URL"], !base.isEmpty else {
            throw XCTSkip("الخدمة المحلية غير مضبوطة لاختبار عينة OCR الحية")
        }
        let app = SiyaqLauncher().launch(mode: "live", baseURL: base, reset: true)
        submit("قال تعالى :\n{يا أَيُّهَا الَّذِينَ آمَنُوا لا تَقْرَبُوا الصَّلَاةَ وَأَنتُمْ سُكَارَىٰ\nحَتَّىٰ تَعْلَمُوا مَا تَقُولُونَ وَلَا جُنُبًا إِلَّا عَابِرِي سَبِيلٍ\nحَتَّىٰ تَغْتَسِلُوا وَإِن كُنتُم مَّرْضَىٰ أَوْ عَلَىٰ سَفَرٍ\nأَوْ جَاءَ أَحَدٌ مِّنكُم مِّنَ الْغَائِطِ أَوْ لَامَسْتُمُ Ne/a\nالنِّسَاءَ فَلَمْ تَجِدُوا مَاءً فَتَيَمَّمُوا صَعِيدًا طَيِّبًا Mae/\nAig0/A\nفَامْسَحُوا بِوُجُوهِكُمْ وَأَيْدِيكُمْ * إِنَّ اللَّهَ\nالغردور كَانَ عَفُوًّا غَفُورًا}", in: app)
        XCTAssertTrue(app.staticTexts["مواضع محتملة."].waitForExistence(timeout: 40))
        XCTAssertTrue(element(containing: "تشابه محتمل، وليس إثباتًا", in: app).exists)
        XCTAssertFalse(app.staticTexts["اقتباسك في سياقه."].exists)
        let candidate = button(containing: "سورة النساء · الآية ٤٣", in: app)
        siyaqReveal(candidate, in: app)
        candidate.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 40))
        XCTAssertTrue(element(containing: "موضع محتمل اخترته، وليس مطابقة مؤكدة", in: app).exists)
        let tafsir = app.buttons["التفسير"]
        siyaqReveal(tafsir, in: app)
        tafsir.tap()
        XCTAssertTrue(app.staticTexts["تفسير مجاهد"].firstMatch.waitForExistence(timeout: 5))
        siyaqReveal(sourceLink("افتح التفسير في مصدره", in: app), in: app)
        siyaqProof("عينة OCR الحية — تفسير الموضع المختار", app)
        let source = app.buttons["المصدر"]
        siyaqReveal(source, in: app)
        source.tap()
        let verseSource = sourceLink("افتح الآية في مصدرها", in: app)
        XCTAssertTrue(verseSource.waitForExistence(timeout: 5))
        siyaqReveal(verseSource, in: app)
        siyaqReveal(sourceLink("افتح التفسير في مصدره", in: app), in: app)
        siyaqProof("عينة OCR الحية — المصادر المباشرة", app)
    }

    // MARK: - الحفظ وإعادة الفتح ودون شبكة

    /// حفظ ← إغلاق كامل ← فتح: النتيجة موجودة وتُفتح بنصها وتاريخها.
    func testSavedResultSurvivesRelaunch() {
        let launcher = SiyaqLauncher()
        var app = launcher.launch(mode: "preview", reset: true)
        saveFirstExample(in: app)
        app.terminate()

        app = launcher.launch(mode: "preview", reset: false)
        tapSiyaqTab("المحفوظات", in: app)
        let row = button(containing: "سورة النساء · الآية ٤٣", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "محفوظة في", in: app).exists)
        siyaqProof("محفوظات بعد إعادة الفتح", app)
    }

    /// قراءة المحفوظات مع خدمة غير قابلة للوصول (منفذ مغلق محليًا) في الوضع الحي:
    /// المحفوظات تعمل، والمراجعة الجديدة تُظهر خطأ ولا تتحول للمعاينة.
    func testSavedResultsReadableWithoutService() {
        let launcher = SiyaqLauncher()
        var app = launcher.launch(mode: "preview", reset: true)
        saveFirstExample(in: app)
        app.terminate()

        // منفذ 9 (discard) مغلق على المحاكي ← فشل اتصال فوري. HTTP المحلي مسموح في Debug فقط.
        app = launcher.launch(mode: "live", baseURL: "http://127.0.0.1:9", reset: false)
        tapSiyaqTab("المحفوظات", in: app)
        let row = button(containing: "سورة النساء · الآية ٤٣", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 5))
        let tafsirTab = app.buttons["التفسير"]
        siyaqReveal(tafsirTab, in: app)
        tafsirTab.tap()
        XCTAssertTrue(app.staticTexts["تفسير مجاهد"].waitForExistence(timeout: 5))
        siyaqProof("قراءة المحفوظات دون خدمة", app)

        tapSiyaqTab("مراجعة", in: app)
        let example = button(containing: "قل هو الله أحد", in: app)
        siyaqReveal(example, in: app)
        example.tap()
        XCTAssertTrue(app.staticTexts["تعذرت المراجعة"].waitForExistence(timeout: 30))
        XCTAssertTrue(button(containing: "إعادة المحاولة", in: app).exists, "فشل الاتصال يعرض «إعادة المحاولة»")
        XCTAssertFalse(app.staticTexts["نتيجة من أمثلة المعاينة المسجلة، وليست مراجعة حية."].exists, "لا تحول تلقائي للمعاينة")
    }

    /// الحفظ مرتين لا يكرر النتيجة: الزر يتحول إلى «إزالة»، والقائمة فيها صف واحد.
    func testSavingTwiceDoesNotDuplicate() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        saveFirstExample(in: app)
        // الضغط مرة ثانية يزيل، والثالثة يعيد الحفظ — النتيجة صف واحد فقط.
        app.buttons["saveResult"].tap()
        XCTAssertTrue(app.buttons["حفظ النتيجة"].waitForExistence(timeout: 5))
        app.buttons["saveResult"].tap()
        XCTAssertTrue(app.buttons["إزالة من المحفوظات"].waitForExistence(timeout: 5))

        tapSiyaqTab("المحفوظات", in: app)
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "سورة النساء · الآية ٤٣"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - الحذف بتأكيد

    /// «إلغاء» في التأكيد يبقي النتيجة؛ «حذف» يزيلها ويبقى الحذف بعد إعادة الفتح.
    func testDeleteRequiresConfirmationAndPersists() {
        let launcher = SiyaqLauncher()
        var app = launcher.launch(mode: "preview", reset: true)
        saveFirstExample(in: app)

        tapSiyaqTab("المحفوظات", in: app)
        let row = button(containing: "سورة النساء · الآية ٤٣", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let trash = app.buttons["حذف من المحفوظات"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.tap()
        siyaqProof("تأكيد الحذف قبل الإلغاء", app)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["إلغاء", "Cancel"])).firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // iOS26 يعرض تأكيد الحذف كقائمة منبثقة بلا زر إلغاء؛ منطقة الاستبعاد ظهرت في فحص AX الفعلي.
            let dismiss = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
        }
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].exists, "الإلغاء يبقي النتيجة")

        trash.tap()
        let confirm = app.buttons["حذف"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        siyaqProof("تأكيد الحذف", app)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["لا توجد محفوظات بعد"].waitForExistence(timeout: 5))

        app.terminate()
        app = launcher.launch(mode: "preview", reset: false)
        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["لا توجد محفوظات بعد"].waitForExistence(timeout: 5))
    }

    // MARK: - المشاركة

    /// تظهر قائمة مشاركة النظام. محتوى النص (الآية والموضع والمصادر) مُثبت باختبارات الوحدة.
    func testShareSheetOpensFromResult() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        let example = button(containing: "لا تقربوا الصلاة", in: app)
        siyaqReveal(example, in: app)
        example.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 10))

        app.buttons["shareResult"].tap()
        let sheet = app.otherElements["ActivityListView"]
        let copy = app.buttons.matching(NSPredicate(format: "label IN %@", ["Copy", "نسخ"])).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10) || copy.waitForExistence(timeout: 2), "لم تظهر قائمة المشاركة")
        siyaqProof("قائمة المشاركة", app)
    }

    // MARK: - التحقق من الإدخال

    func testOneWordIsRejected() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        submit("kalima", in: app)
        XCTAssertTrue(app.staticTexts["اكتب كلمتين على الأقل من الاقتباس."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["نراجع الاقتباس…"].exists, "لا طلب عند رفض الإدخال")
    }

    func testOverlongQuoteShowsCounterAndIsRejected() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        submit(String(repeating: "ab ", count: 334), in: app)
        XCTAssertTrue(element(containing: "الاقتباس أطول من المسموح", in: app).waitForExistence(timeout: 5))
        let counter = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", "١٠٠٠", "حرف")).firstMatch
        siyaqProof("رفض الاقتباس الطويل والعداد", app)
        XCTAssertTrue(counter.exists, app.debugDescription)
    }

    /// بناء بلا خدمة مضبوطة: شاشة خطأ واضحة مع «إعادة المحاولة»، بلا زر إعدادات ولا نتيجة من الأمثلة.
    func testMissingServiceShowsRetryWithoutSettingsOrSamples() {
        let app = SiyaqLauncher().launch(mode: "live", baseURL: "", reset: true)
        let example = button(containing: "قل هو الله أحد", in: app)
        siyaqReveal(example, in: app)
        example.tap()
        XCTAssertTrue(app.staticTexts["خدمة المراجعة غير متاحة"].waitForExistence(timeout: 5), app.debugDescription)
        let retry = button(containing: "إعادة المحاولة", in: app)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(button(containing: "إعدادات", in: app).exists)
        XCTAssertFalse(button(containing: "وضع المعاينة", in: app).exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["خدمة المراجعة غير متاحة"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["نتيجة من أمثلة المعاينة المسجلة، وليست مراجعة حية."].exists, "لا أمثلة بدل النتيجة")
        siyaqProof("خدمة غير متاحة مع إعادة المحاولة", app)
    }

    // MARK: - مساعدات

    /// يفتح «لا تقربوا الصلاة» من الأمثلة ويحفظ النتيجة.
    private func saveFirstExample(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let example = button(containing: "لا تقربوا الصلاة", in: app)
        XCTAssertTrue(example.waitForExistence(timeout: 10), file: file, line: line)
        siyaqReveal(example, in: app, file: file, line: line)
        example.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 10), file: file, line: line)
        let save = app.buttons["saveResult"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), file: file, line: line)
        save.tap()
        XCTAssertTrue(app.buttons["إزالة من المحفوظات"].waitForExistence(timeout: 5), file: file, line: line)
    }
}
