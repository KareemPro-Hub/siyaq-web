import XCTest

final class SiyaqUITests: XCTestCase {
    func testOpeningShowsBrandBeforeHome() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true,
                                        extraEnvironment: ["SIYAQ_UITEST_OPENING": "hold"])
        XCTAssertTrue(app.staticTexts["openingArabicName"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["openingArabicName"].label, "سياق")
        XCTAssertEqual(app.staticTexts["openingEnglishName"].label, "Siyaq")
        XCTAssertFalse(app.textViews["quoteInput"].exists, "لا تظهر الرئيسية خلف المقدمة")
        proof("الافتتاحية — الأيقونة والاسمان", app)
    }

    func testOpeningCompletesAndDoesNotReplayOnForeground() {
        let app = SiyaqLauncher().launch(mode: "preview", reset: true)
        XCTAssertTrue(app.textViews["quoteInput"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.textViews["quoteInput"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["openingArabicName"].exists)
        proof("عودة مباشرة للرئيسية بعد الخلفية", app)
    }

    private func app() -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["SIYAQ_UITEST_LIVE_BASE_URL"]
            ?? "https://siyaq-theta.vercel.app"
        return SiyaqLauncher().launch(mode: "live", baseURL: base, reset: true)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func proof(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHomeAndTabs() {
        let app = app()
        XCTAssertTrue(app.textViews["الاقتباس القرآني"].waitForExistence(timeout: 10))
        proof("الرئيسية", app)
        tapSiyaqTab("المحفوظات", in: app)
        XCTAssertTrue(app.staticTexts["لا توجد محفوظات بعد"].waitForExistence(timeout: 5))
        proof("المحفوظات", app)
        tapSiyaqTab("عن سِياق", in: app)
        XCTAssertTrue(app.staticTexts["تطبيق سِياق"].waitForExistence(timeout: 5))
    }

    func testEmptyQuoteIsRejected() {
        let app = app()
        let submit = app.buttons["ابدأ المراجعة"]
        reveal(submit, in: app)
        submit.tap()
        XCTAssertTrue(app.staticTexts["اكتب اقتباسًا أو اختر أحد الأمثلة أولًا."].waitForExistence(timeout: 5))
        proof("التحقق من الإدخال", app)
    }

    func testLiveReviewAndContext() {
        let app = app()
        let example = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "لا تقربوا الصلاة")).firstMatch
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        reveal(example, in: app)
        example.tap()
        XCTAssertTrue(app.staticTexts["اقتباسك في سياقه."].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["سورة النساء · الآية ٤٣"].exists)
        XCTAssertFalse(app.staticTexts["نتيجة من أمثلة المعاينة المسجلة، وليست مراجعة حية."].exists)
        proof("مراجعة حية", app)
        let context = app.buttons["السياق"]
        reveal(context, in: app)
        context.tap()
        proof("السياق", app)
    }
}
