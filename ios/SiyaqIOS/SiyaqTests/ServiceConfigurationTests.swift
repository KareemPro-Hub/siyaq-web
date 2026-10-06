import XCTest
@testable import Siyaq
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// الاتصال بخدمة سِياق من إعدادات البناء فقط (طلب كريم ٣ أكتوبر): لا وضع معاينة ولا عنوان ولا كلمة وصول في الواجهة.
final class ServiceConfigurationTests: XCTestCase {

    func testCleanedIgnoresBlanksAndUnexpandedBuildVariables() {
        XCTAssertEqual(ServiceConfiguration.cleaned(" https://siyaq.example \n"), "https://siyaq.example")
        XCTAssertEqual(ServiceConfiguration.cleaned(nil), "")
        XCTAssertEqual(ServiceConfiguration.cleaned("$(SIYAQ_SERVICE_BASE_URL)"), "")
    }

    func testLiveConfigurationBuildsTheReviewEndpointWithoutCredentials() throws {
        let choice = try ServiceConfiguration(source: .live(baseURL: "https://siyaq.example")).makeReviewService()
        XCTAssertEqual(choice.origin, .live)
        let live = try XCTUnwrap(choice.service as? LiveReviewService)
        XCTAssertEqual(live.endpoint.absoluteString, "https://siyaq.example/api/review")
        let request = try live.makeRequest(quote: "لا تقربوا الصلاة", selection: nil)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "لا أسرار ولا بيانات دخول في الطلب")
        let explain = try XCTUnwrap(try ServiceConfiguration(source: .live(baseURL: "https://siyaq.example")).makeExplanationService() as? LiveExplanationService)
        XCTAssertNil(try explain.makeRequest(quote: "لا تقربوا الصلاة", selection: nil).value(forHTTPHeaderField: "Authorization"))
    }

    func testMissingOrInsecureBuildSettingFailsClearly() {
        XCTAssertThrowsError(try ServiceConfiguration(source: .live(baseURL: "")).makeReviewService()) {
            XCTAssertEqual($0 as? ReviewError, .notConfigured)
        }
        XCTAssertThrowsError(try ServiceConfiguration(source: .live(baseURL: "http://siyaq.example")).makeReviewService())
    }

    /// الأمثلة المسجلة أداة اختبار فقط، ونتيجتها موسومة «معاينة» دائمًا فلا تختلط بنتيجة حقيقية.
    func testRecordedSamplesAreTaggedAsPreview() throws {
        let choice = try ServiceConfiguration(source: .recordedSamples).makeReviewService()
        XCTAssertEqual(choice.origin, .preview)
        XCTAssertTrue(choice.service is PreviewReviewService)
    }

    /// خارج مساحة اختبار الواجهة، التهيئة الحالية هي إعداد البناء نفسه (لا شيء محفوظ من المستخدم).
    func testCurrentConfigurationComesFromTheBuildWhenNotInUITestSandbox() {
        guard UITestSandbox.current == nil else { return }
        XCTAssertEqual(ServiceConfiguration.current, ServiceConfiguration.bundled())
    }

    func testLegacyConnectionSettingsAreRemoved() throws {
        let suite = "siyaq.test.legacy." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preview", forKey: "siyaq.reviewMode")
        defaults.set("https://old.example", forKey: "siyaq.serviceBaseURL")
        defaults.set(true, forKey: "siyaq.useSystemFont")
        defaults.set("keep", forKey: "siyaq.other")
        LegacyConnectionSettings.removeStoredValues(defaults: defaults, includeKeychain: false)
        for key in LegacyConnectionSettings.defaultsKeys { XCTAssertNil(defaults.object(forKey: key), key) }
        XCTAssertEqual(defaults.string(forKey: "siyaq.other"), "keep")
    }

    /// العنوان يأتي من إعدادات البناء في الخطتين، لا نص ثابت ولا قيمة فارغة.
    func testInfoPlistsTakeTheServiceFromBuildSettings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var checked = 0
        for name in ["Info.plist", "Info.Release.plist"] {
            let url = root.appendingPathComponent("Siyaq").appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            XCTAssertTrue(text.contains("<key>SiyaqServiceBaseURL</key>\n\t<string>$(SIYAQ_SERVICE_BASE_URL)</string>"), name)
            checked += 1
        }
        let project = root.appendingPathComponent("SiyaqIOS.xcodeproj/project.pbxproj")
        if let text = try? String(contentsOf: project, encoding: .utf8) {
            XCTAssertEqual(text.components(separatedBy: #"SIYAQ_SERVICE_BASE_URL = "https://www.mysiyaq.com";"#).count - 1, 2)
            XCTAssertFalse(text.contains("SettingsSection.swift"))
        }
        _ = checked
    }
}
