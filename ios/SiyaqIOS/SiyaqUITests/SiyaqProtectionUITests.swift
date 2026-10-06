import XCTest

/// اختبارات واجهة المرحلتين ١٣ و١٤ (تسليم Cowork). كتبت على Linux ولم تُشغَّل؛ يشغّلها Codex على Xcode.
/// - كل اختبار في مساحة معزولة (`SIYAQ_UITEST_SANDBOX`)؛ لا تُمس محفوظات المستخدم ولا إعداداته.
/// - تهيئة المحفوظات (`SIYAQ_UITEST_SEED` و`SIYAQ_UITEST_LOCK_STORE`) موجودة في Debug فقط داخل مساحة الاختبار.
/// - لا شبكة ولا OpenAI: الأمثلة المسجلة لأداة الاختبار، أو خدمة بعنوان فارغ (بدائل في مساحة الاختبار فقط، لا في الواجهة).
/// - الإعلانات الصوتية لا تُرى في XCUITest؛ يُثبت هنا الأثر الظاهر (الحالة والتنبيه)، والإعلان نفسه يحتاج VoiceOver على جهاز.
final class SiyaqProtectionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - المرحلة ١٣: الخدمة غير المتاحة

    /// خدمة غير مضبوطة في البناء: لا رسالة إعدادات تحت المربع؛ تُفتح شاشة خطأ مع «إعادة المحاولة» و«تعديل الاقتباس»،
    /// والعودة تحفظ نص المستخدم كما هو.
    func testUnavailableServiceShowsRetryAndKeepsQuote() {
        let app = SiyaqLauncher().launch(mode: "live", baseURL: "", reset: true)
        let example = button(containing: "قل هو الله أحد", in: app)
        siyaqReveal(example, in: app)
        example.tap()

        XCTAssertTrue(app.staticTexts["خدمة المراجعة غير متاحة"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(containing: "إعادة المحاولة", in: app).exists)
        XCTAssertFalse(app.buttons["افتح إعدادات الخدمة"].exists)
        XCTAssertFalse(app.staticTexts["نراجع الاقتباس…"].exists, "لا طلب بلا عنوان")
        siyaqProof("الخدمة غير المتاحة مع إعادة المحاولة", app)

        let edit = button(containing: "تعديل الاقتباس", in: app)
        siyaqReveal(edit, in: app)
        edit.tap()
        let input = app.textViews["quoteInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue((input.value as? String ?? "").contains("قل هو الله أحد"))
    }

    // MARK: - المرحلة ١٤: حماية المحفوظات

    /// فشل النسخ الاحتياطي لملف تالف جزئيًا: السليم يُقرأ، والتنبيه الدائم يبقى بعد إغلاق الرسالة،
    /// والإزالة تُرفض دون أن تتغير الحالة إلى «حفظ»، ثم يتعافى التطبيق عند إعادة الفتح بعد زوال المانع.
    func testBackupFailureIsReadOnlyThenRecovers() {
        let launcher = SiyaqLauncher()
        var app = launcher.launchSeeded(mode: "preview", reset: true,
                                  extra: ["SIYAQ_UITEST_SEED": "partial-corrupt", "SIYAQ_UITEST_LOCK_STORE": "1"])
        dismissStoreAlert(in: app, expecting: "تعذر حفظ نسخة احتياطية")

        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["المحفوظات للقراءة فقط"].waitForExistence(timeout: 5), "التنبيه الدائم بعد إغلاق الرسالة")
        XCTAssertTrue(button(containing: "سورة النساء · الآية ٤٣", in: app).waitForExistence(timeout: 5), "السليم يُقرأ")
        siyaqProof("فشل النسخ الاحتياطي — قراءة فقط", app)

        assertRemovalRefused(in: app)

        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["المحفوظات للقراءة فقط"].exists, "التنبيه باق بعد محاولة فاشلة")
        app.terminate()

        // زوال المانع (المجلد قابل للكتابة): النسخ الاحتياطي ينجح، والحماية تزول، والإزالة تعمل.
        app = launcher.launch(mode: "preview", reset: false)
        dismissStoreAlert(in: app, expecting: "حُفظت نسخة من الملف الأصلي")
        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(button(containing: "سورة النساء · الآية ٤٣", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["المحفوظات للقراءة فقط"].exists, "لا تنبيه بعد التعافي")

        tapSiyaqTab("مراجعة", in: app)
        openPartialExample(in: app)
        app.buttons["saveResult"].tap()
        XCTAssertTrue(app.buttons["حفظ النتيجة"].waitForExistence(timeout: 5), "الإزالة تعمل بعد التعافي")
        XCTAssertFalse(app.alerts["المحفوظات"].exists)
        siyaqProof("التعافي بعد زوال المانع", app)
    }

    /// صيغة أحدث من المدعوم: قراءة فقط، والتنبيه يبقى بعد إغلاق الرسالة وبعد إعادة الفتح،
    /// والحفظ والإزالة يُرفضان دون إعلان نجاح ولا إعادة كتابة.
    func testNewerFormatStaysReadOnly() {
        let launcher = SiyaqLauncher()
        var app = launcher.launchSeeded(mode: "preview", reset: true, extra: ["SIYAQ_UITEST_SEED": "newer-format"])
        dismissStoreAlert(in: app, expecting: "صيغة إصدار أحدث")

        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["المحفوظات للقراءة فقط"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "صيغة إصدار أحدث", in: app).exists)
        XCTAssertTrue(button(containing: "سورة النساء · الآية ٤٣", in: app).exists, "ما أمكن قراءته معروض")

        assertRemovalRefused(in: app)

        // حفظ نتيجة جديدة يُرفض أيضًا.
        tapSiyaqTab("مراجعة", in: app)
        popToHome(in: app)
        let other = button(containing: "قل هو الله أحد", in: app)
        siyaqReveal(other, in: app)
        other.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 10))
        app.buttons["saveResult"].tap()
        dismissStoreAlert(in: app, expecting: "صيغة إصدار أحدث")
        XCTAssertTrue(app.buttons["حفظ النتيجة"].exists, "لم يُحفظ")
        app.terminate()

        app = launcher.launch(mode: "preview", reset: false)
        dismissStoreAlert(in: app, expecting: "صيغة إصدار أحدث")
        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["المحفوظات للقراءة فقط"].waitForExistence(timeout: 5), "لم يُكتب فوقها بصيغة أقدم")
        siyaqProof("صيغة أحدث — قراءة فقط بعد إعادة الفتح", app)
    }

    // MARK: - مساعدات

    /// يفتح النتيجة المحفوظة نفسها من الأمثلة ويحاول إزالتها: تُرفض، ويظهر التنبيه، ويبقى الزر «إزالة».
    private func assertRemovalRefused(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tapSiyaqTab("مراجعة", in: app)
        openPartialExample(in: app, file: file, line: line)
        let remove = app.buttons["إزالة من المحفوظات"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "النتيجة معروفة كمحفوظة", file: file, line: line)
        remove.tap()
        dismissStoreAlert(in: app, expecting: "للقراءة", file: file, line: line)
        XCTAssertTrue(app.buttons["إزالة من المحفوظات"].exists, "لم تُعلن إزالة ولم تتغير الحالة", file: file, line: line)
        XCTAssertFalse(app.buttons["حفظ النتيجة"].exists, file: file, line: line)
    }

    private func openPartialExample(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        popToHome(in: app)
        let example = button(containing: "لا تقربوا الصلاة", in: app)
        XCTAssertTrue(example.waitForExistence(timeout: 5), file: file, line: line)
        siyaqReveal(example, in: app, file: file, line: line)
        example.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 10), file: file, line: line)
    }

    /// تنبيه «المحفوظات» برسالة تحتوي النص المتوقع، ثم إغلاقه.
    private func dismissStoreAlert(in app: XCUIApplication, expecting text: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let alert = app.alerts["المحفوظات"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "لم يظهر تنبيه المحفوظات", file: file, line: line)
        let body = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(body.exists, "نص التنبيه لا يحتوي: \(text)", file: file, line: line)
        alert.buttons["حسنًا"].tap()
        // عند التشغيل قد تعيد القراءة (عند تفعيل المشهد) إظهار الرسالة نفسها مرة؛ تُغلق مرة أخرى دون اعتبارها خطأ.
        if alert.waitForExistence(timeout: 1.5) { alert.buttons["حسنًا"].tap() }
        XCTAssertTrue(gone(alert, within: 5), file: file, line: line)
    }

    /// الرئيسية لا تُظهر شريط تنقل؛ أي زر رجوع ظاهر يعني نتيجة مفتوحة فوقها.
    private func popToHome(in app: XCUIApplication) {
        for _ in 0..<3 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.isHittable else { return }
            back.tap()
        }
    }

    private func gone(_ element: XCUIElement, within seconds: TimeInterval) -> Bool {
        let vanished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [vanished], timeout: seconds) == .completed
    }
}

extension SiyaqLauncher {
    /// مثل `launch` مع متغيرات تهيئة إضافية لمساحة الاختبار نفسها (Debug فقط في التطبيق).
    /// في ملف مستقل حتى لا يتغير `UITestSupport.swift` عند الدمج.
    @discardableResult
    func launchSeeded(mode: String, reset: Bool, extra: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        var environment = [
            "SIYAQ_UITEST_SANDBOX": sandbox,
            "SIYAQ_UITEST_MODE": mode,
            "SIYAQ_UITEST_BASE_URL": "",
        ]
        if reset { environment["SIYAQ_UITEST_RESET"] = "1" }
        environment.merge(extra) { $1 }
        app.launchEnvironment = environment
        app.launch()
        waitUntilReady(app)
        return app
    }
}
