import SwiftUI

@main
struct SiyaqApp: App {
    // في Release تكون UITestSandbox.current دائمًا nil، فتبقى المحفوظات في Application Support/Siyaq كما هي.
    // الاتصال بالخدمة من إعدادات البناء (ServiceConfiguration)؛ لا إعدادات يحفظها المستخدم.
    @State private var store = SavedResultsStore(directory: UITestSandbox.current?.directory)

    init() {
        // تنظيف ما حفظته إعدادات الاتصال المحذوفة (الوضع، العنوان، كلمة الوصول). مساحة الاختبار لا تمس Keychain.
        let sandbox = UITestSandbox.current
        LegacyConnectionSettings.removeStoredValues(defaults: sandbox?.defaults ?? .standard,
                                                    includeKeychain: sandbox == nil)
    }

    var body: some Scene {
        WindowGroup {
            AppOpeningView()
                .environment(store)
        }
    }
}

/// مرة واحدة لكل بدء تشغيل، ولا تعاد عند تبديل التبويبات أو العودة من الخلفية.
private struct AppOpeningView: View {
    @State private var showingOpening = true
    @State private var departing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            if !showingOpening || departing {
                // لا يُدرج TabView في معاملة حركة؛ المقدمة وحدها تتلاشى فوقه.
                RootView()
                    .transaction { transaction in
                        if departing {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                    .zIndex(0)
            }
            if showingOpening {
                LaunchView {
                    if reduceMotion {
                        showingOpening = false
                    } else {
                        withAnimation(.easeInOut(duration: 0.55)) { departing = true }
                    }
                }
                .opacity(departing ? 0 : 1)
                .scaleEffect(departing ? 1.05 : 1)
                .allowsHitTesting(false)
                .zIndex(1)
            }
        }
        .preferredColorScheme(.light)
        .task(id: departing) {
            guard departing else { return }
            do {
                try await Task.sleep(for: .milliseconds(550))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showingOpening = false
                    departing = false
                }
            } catch is CancellationError {
                // الإغلاق يلغي الانتقال المملوك للشاشة.
            } catch {
                showingOpening = false
                departing = false
            }
        }
    }
}

enum AppTab: Hashable {
    case review
    case saved
    case about
}

/// التبويبات الأصلية: مراجعة، المحفوظات، عن سِياق والمصادر.
struct RootView: View {
    @Environment(SavedResultsStore.self) private var store

    @State private var tab: AppTab = .review
    @State private var session = ReviewSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            HomeView(session: session, selectedTab: $tab)
                .tabItem { Label("مراجعة", systemImage: "magnifyingglass") }
                .tag(AppTab.review)

            SavedListView()
                .tabItem { Label("المحفوظات", systemImage: "bookmark") }
                .tag(AppTab.saved)

            AboutView()
                .tabItem { Label("عن سِياق", systemImage: "doc.text") }
                .tag(AppTab.about)
        }
        .tint(Palette.tealDark)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        // طلب كريم (٣ أكتوبر): يبقى التطبيق على خط النظام الذي يعمل به الآن، دون مفتاح تبديل.
        .environment(\.siyaqUsesSystemFont, true)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            // إن تعذر فتح المحفوظات أو نسخها احتياطيًا عند التشغيل، نعيد المحاولة عند العودة للواجهة.
            if phase == .active, store.shouldRetryOnForeground {
                store.reload()
            }
        }
        .alert(
            "المحفوظات",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("حسنًا", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
