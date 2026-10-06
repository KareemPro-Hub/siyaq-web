import SwiftUI

/// مقدمة محلية خفيفة: ظهور، مسح بالعدسة، لمعة واحدة، ثم اسم العلامة.
/// عدسة المقدمة بلا شرطة انعكاس؛ أصل الأيقونة العادية المعتمدة لا يتغير.
struct LaunchView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var arabicSize: CGFloat = 33

    @State private var appeared = false
    @State private var lensX: CGFloat = 0.72
    @State private var lensY: CGFloat = 0.42
    @State private var lensAngle: Double = -16
    @State private var sheen: CGFloat = -0.7
    @State private var nameVisible = false

    private var holdForPreview: Bool {
        #if DEBUG
        UITestSandbox.current != nil && ProcessInfo.processInfo.environment["SIYAQ_UITEST_OPENING"] == "hold"
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(212, max(140, geometry.size.width * 0.53))
            VStack(spacing: 22) {
                animatedIcon(side: side)
                    .environment(\.layoutDirection, .leftToRight)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text("سياق")
                        .font(.system(size: min(arabicSize, 46), weight: .bold))
                        // يبقى الاسم نصًا لقارئ الشاشة؛ الحروف المرئية من أصل الشعار.
                        .foregroundStyle(.clear)
                        .frame(width: min(arabicSize, 46) * 3.4,
                               height: min(arabicSize, 46) * 1.4)
                        .overlay {
                            Image("OpeningWordmark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Palette.navy)
                                .accessibilityHidden(true)
                        }
                        .opacity(nameVisible ? 1 : 0)
                        .offset(y: nameVisible || reduceMotion ? 0 : 5)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.85), value: nameVisible)
                        .accessibilityIdentifier("openingArabicName")
                    Text("Siyaq")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .tracking(3)
                        .foregroundStyle(Palette.tealDark)
                        .environment(\.layoutDirection, .leftToRight)
                        .opacity(nameVisible ? 1 : 0)
                        .offset(y: nameVisible || reduceMotion ? 0 : 4)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.85).delay(0.18), value: nameVisible)
                        .accessibilityIdentifier("openingEnglishName")
                }
                .accessibilityHidden(!nameVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, geometry.size.height * 0.055)
        }
        .background(Palette.ground.ignoresSafeArea())
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await runOpening()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    appeared = true
                    lensX = 0.56
                    lensY = 0.51
                    lensAngle = 0
                    nameVisible = true
                }
                if !holdForPreview { onFinish() }
            }
        }
    }

    private func animatedIcon(side: CGFloat) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x193C82), Color(hex: 0x152553)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                word(side: side)
                // شريط متدرج، يمر مرة واحدة على الحروف فقط ولا يضيء الخلفية.
                LinearGradient(colors: [.clear, .white.opacity(0.12), .white.opacity(0.8), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: side * 0.34, height: side)
                    .rotationEffect(.degrees(18))
                    .offset(x: side * sheen)
                    .frame(width: side, height: side)
                    .mask(word(side: side))
                movingLens(side: side)
                    .position(x: side * lensX, y: side * lensY)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        }
        .frame(width: side, height: side)
        .shadow(color: Palette.navy.opacity(0.13), radius: 18, x: 0, y: 12)
    }

    private func word(side: CGFloat) -> some View {
        Image("OpeningWordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: side * 0.84, height: side * 0.35)
            .foregroundStyle(Color(hex: 0xDDF7EE))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    private func movingLens(side: CGFloat) -> some View {
        let diameter = side * 0.40
        return ZStack {
            Capsule()
                .fill(Color(hex: 0x00C3D0))
                .frame(width: side * 0.085, height: side * 0.29)
                .rotationEffect(.degrees(-42))
                .offset(x: diameter * 0.45, y: diameter * 0.49)
            Circle()
                // لون زجاج مستقل ومعتم: لا تظهر الحروف الأصلية أو المقبض خلف النسخة المكبرة.
                .fill(LinearGradient(colors: [Color(hex: 0x899BB5), Color(hex: 0x20466A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    word(side: side)
                        .scaleEffect(1.16)
                        .offset(x: (0.5 - lensX) * side * 1.16,
                                y: (0.5 - lensY) * side * 1.16)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                }
                .overlay {
                    Circle().stroke(Color(hex: 0x00C3D0), lineWidth: side * 0.026)
                }
                .overlay {
                    Circle().inset(by: side * 0.017)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(lensAngle))
        .shadow(color: Palette.navy.opacity(0.06), radius: 1, x: 0, y: 1)
    }

    @MainActor
    private func runOpening() async {
        // الرجوع من الخلفية أثناء المقدمة يكمل بأقصر مسار، ولا يبدأ حلقة حركة جديدة.
        if appeared {
            guard !holdForPreview else { return }
            lensX = 0.56
            lensY = 0.51
            lensAngle = 0
            nameVisible = true
            onFinish()
            return
        }
        do {

            if reduceMotion {
                appeared = true
                lensX = 0.56
                lensY = 0.51
                lensAngle = 0
                nameVisible = true

                try await Task.sleep(for: .seconds(1))
            } else {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
                try await Task.sleep(for: .milliseconds(250))

                withAnimation(.easeInOut(duration: 0.72)) {
                    lensX = 0.31
                    lensY = 0.56
                    lensAngle = 9
                }
                try await Task.sleep(for: .milliseconds(740))
                withAnimation(.easeInOut(duration: 0.66)) {
                    lensX = 0.56
                    lensY = 0.51
                    lensAngle = 0
                }
                try await Task.sleep(for: .milliseconds(690))
                withAnimation(.easeInOut(duration: 0.65)) { sheen = 0.7 }
                try await Task.sleep(for: .milliseconds(650))
                nameVisible = true

                // يكتمل ظهور الاسمين أولًا، ثم وقفة ثابتة ثانية كاملة قبل الانتقال.
                try await Task.sleep(for: .milliseconds(1030))
                try await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, !holdForPreview else { return }
            onFinish()
        } catch is CancellationError {

            // لا مهام غير مملوكة للشاشة أو انتقال متأخر بعد خروج التطبيق للخلفية.
        } catch {
            onFinish()
        }
    }
}
