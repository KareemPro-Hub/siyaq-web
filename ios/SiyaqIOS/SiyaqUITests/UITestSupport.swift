import XCTest

/// تشغيل التطبيق داخل مساحة اختبار معزولة (Debug فقط).
/// كل اختبار يأخذ اسم مساحة فريدًا، فلا تُلمس محفوظات المستخدم ولا إعداداته أبدًا.
struct SiyaqLauncher {
    let sandbox: String

    init(_ testName: String = #function) {
        // اسم آمن: أحرف لاتينية وأرقام وشرطات فقط (يطابق UITestSandbox.sanitizedName).
        let base = testName.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        sandbox = "ui-\(base.prefix(24))-\(UUID().uuidString.prefix(8))"
    }

    /// يشغّل التطبيق. reset=true يبدأ بمساحة فارغة؛ false يحاكي إعادة فتح التطبيق على البيانات نفسها.
    /// mode: preview = الأمثلة المسجلة لأداة الاختبار؛ live = baseURL (ولو فارغًا). بدائل في الذاكرة فقط، لا في الواجهة.
    @discardableResult
    func launch(mode: String, baseURL: String? = nil, reset: Bool,
                extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        var environment = [
            "SIYAQ_UITEST_SANDBOX": sandbox,
            "SIYAQ_UITEST_MODE": mode,
        ]
        if reset { environment["SIYAQ_UITEST_RESET"] = "1" }
        // نمرر عنوانًا دائمًا (ولو فارغًا) حتى لا يتسرب عنوان من تشغيل سابق للمساحة نفسها.
        environment["SIYAQ_UITEST_BASE_URL"] = baseURL ?? ""
        environment.merge(extraEnvironment) { _, new in new }
        app.launchEnvironment = environment
        app.launch()
        if environment["SIYAQ_UITEST_OPENING"] != "hold" {
            waitUntilReady(app)
        }
        return app
    }

    /// الرحلات تبدأ بعد ظهور الرئيسية وانتهاء تلاشي المقدمة، لا أثناء بدء التطبيق.
    func waitUntilReady(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.textViews["quoteInput"].waitForExistence(timeout: 20),
                      "لم تظهر الرئيسية بعد المقدمة", file: file, line: line)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.staticTexts["openingArabicName"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "المقدمة لم تنتهِ قبل بدء الرحلة", file: file, line: line)
    }
}

extension XCTestCase {
    /// iOS26 قد يعرض تمثيلين للعنصر نفسه؛ نحدد زر التبويب الأصلي بمعرّفه ثم نتحقق من قابليته للنقر.
    func tapSiyaqTab(_ title: String, in app: XCUIApplication,
                    file: StaticString = #filePath, line: UInt = #line) {
        let identified = app.tabBars.buttons.matching(NSPredicate(format: "label == %@ AND identifier != ''", title))
        let target = identified.count == 1 ? identified.element(boundBy: 0) : app.tabBars.buttons[title]
        XCTAssertTrue(target.waitForExistence(timeout: 8), "التبويب غير موجود: \(title)", file: file, line: line)
        XCTAssertTrue(target.isHittable, "التبويب غير قابل للنقر: \(title)", file: file, line: line)
        target.tap()
    }
    /// يمرر حتى يصبح العنصر قابلًا للنقر.
    func siyaqReveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.minY < app.frame.minY { app.swipeDown() }
            else { app.swipeUp() }
        }
        if !(element.exists && element.isHittable) { siyaqProof("عنصر غير ظاهر", app) }
        XCTAssertTrue(element.exists && element.isHittable, "العنصر غير ظاهر: \(element)", file: file, line: line)
    }

    /// أي عنصر يحتوي وسمه على النص (للعناصر المدمجة مثل البطاقات والتنبيهات).
    func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func button(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// SwiftUI Link يظهر كرابط على iOS 27، وكزر في بعض إصدارات النظام السابقة.
    func sourceLink(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let link = app.links[title].firstMatch
        return link.exists ? link : app.buttons[title].firstMatch
    }

    /// يكتب في مربع الاقتباس ثم يبدأ المراجعة.
    func submit(_ quote: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let input = app.textViews["quoteInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), file: file, line: line)
        input.tap()
        if !quote.isEmpty { input.typeText(quote) }
        let done = app.buttons["تم"]
        if done.exists { done.tap() }
        let start = app.buttons["startReview"]
        siyaqReveal(start, in: app, file: file, line: line)
        start.tap()
    }

    func siyaqProof(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
