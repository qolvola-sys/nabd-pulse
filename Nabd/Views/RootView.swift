import SwiftUI
import UIKit
import Combine

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case accounts
    #if MUTABAA
    case reports
    #endif
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "الرئيسية"
        case .accounts: return "الحسابات"
        #if MUTABAA
        case .reports: return "التقارير"
        #endif
        case .settings: return "الإعدادات"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "waveform.path.ecg"
        case .accounts: return "person.2"
        #if MUTABAA
        case .reports: return "tablecells"
        #endif
        case .settings: return "slider.horizontal.3"
        }
    }

    var activeIcon: String {
        switch self {
        case .dashboard: return "waveform.path.ecg"
        case .accounts: return "person.2.fill"
        #if MUTABAA
        case .reports: return "tablecells.fill"
        #endif
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    #if MUTABAA
    @EnvironmentObject private var reports: ReportsManager
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab
    @State private var showWhatsNew = false
    @State private var showFacebookFromWhatsNew = false
    @State private var showInstagramFromWhatsNew = false
    #if MUTABAA
    private let scheduleTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    #endif

    init() {
        // يُستخدم لمعاينة الشاشات داخل CI: --screen=accounts
        let requested = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--screen=") }?
            .replacingOccurrences(of: "--screen=", with: "")
        _tab = State(initialValue: requested.flatMap(AppTab.init(rawValue:)) ?? .dashboard)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()

            Group {
                switch tab {
                case .dashboard:
                    DashboardView(onOpenSettings: { switchTab(.settings) },
                                  onOpenAccounts: { switchTab(.accounts) })
                case .accounts:
                    AccountsView()
                #if MUTABAA
                case .reports:
                    ReportsView()
                #endif
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let toast = store.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 6)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
                .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $tab)
                .padding(.bottom, 4)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: Theme.bg.opacity(0), location: 0),
                            .init(color: Theme.bg.opacity(0.92), location: 0.32),
                            .init(color: Theme.bg, location: 0.7),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
        }
        .spacesTopInset(spacesTopInsetEnabled)
        .modifier(AppLayoutDirectionModifier())
        .preferredColorScheme(.dark)
        .tint(Theme.cyan)
        .onAppear {
            store.bootstrap()
            runReportsCheck()
            showWhatsNewIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.refreshIfStale()
                runReportsCheck()
            }
        }
        #if MUTABAA
        .onReceive(scheduleTimer) { _ in
            runReportsCheck()
        }
        .alert("جديد في \(AppVariant.version)", isPresented: $showWhatsNew) {
            Button("فتح إنستغرام") {
                showInstagramFromWhatsNew = true
            }
            Button("حسناً", role: .cancel) {}
        } message: {
            Text("تم تثبيت هذه النسخة بنجاح.\n\n• إصلاح جذري لموجز الريلز: كان يرسل ترويسة Safari فيرفضه إنستغرام بـ401 دائماً. السبب مقيَّس من تجربة مباشرة: المسار يقبل ترويسة تطبيق أندرويد فقط، ومعها Origin وReferer.\n• صار يعيد المحاولة مرة واحدة بعد ٥ ثوانٍ عند 401/429، وإن تكرر الرفض يتوقف عشر دقائق لكل الحسابات بدل إهدار المزامنة.\n• سطر التشخيص يعرض رمز الرفض بدقة: «reels p1 401» بدل «unavailable».\n• الحالة المتوقعة الآن: «reels ✓12 · 7/7d» — أي الأسبوع كامل من طلب واحد لكل حساب.\n\nملاحظة: إن بقي الرفض فالمصدر الثاني يعمل تلقائياً ويعطيك ٦ من ٧، فلا تتوقف القراءة.\n\nملاحظة: ملفات Excel القديمة تحتفظ بتنسيقها؛ أنشئ تقريراً جديداً بعد التحديث.")
        }
        .fullScreenCover(isPresented: $showFacebookFromWhatsNew) {
            ZStack {
                AppBackground()
                AccountsView(platform: .facebook)
                    .environmentObject(store)
            }
        }
        .fullScreenCover(isPresented: $showInstagramFromWhatsNew) {
            ZStack {
                AppBackground()
                AccountsView(platform: .instagram)
                    .environmentObject(store)
            }
        }
        #endif
    }

    /// يعرض تنبيهاً مرة واحدة بعد تثبيت نسخة جديدة، ليتأكد المستخدم
    /// أن التحديث وصل فعلاً وليس نسخة قديمة.
    private func showWhatsNewIfNeeded() {
        let key = "nabd.lastSeenVersion"
        let current = AppVariant.version
        guard !current.isEmpty else { return }
        if UserDefaults.standard.string(forKey: key) != current {
            UserDefaults.standard.set(current, forKey: key)
            showWhatsNew = true
        }
    }

    /// التوليد التلقائي لا يعمل في الخلفية على iOS. نفحص الموعد عند فتح
    /// التطبيق، وعند عودته للنشاط، ومرة كل دقيقة أثناء بقائه مفتوحاً.
    private func runReportsCheck() {
        #if MUTABAA
        Task {
            await reports.autoGenerateIfNeeded(store: store)
        }
        #endif
    }

    private var spacesTopInsetEnabled: Bool {
        #if MUTABAA
        // شريط فيسبوك يبقى ظاهراً دائماً في «المتابعة»، حتى في وضع
        // الخادم أو التجريبي، لأن هذه الأوضاع كانت تخفي المدخل سابقاً.
        return true
        #else
        return false
        #endif
    }

    private func switchTab(_ target: AppTab) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { tab = target }
        store.haptic(.selection)
    }
}

/// «المتابعة» عربية بالكامل، ونترك اتجاه الواجهة للنظام بدل فرض RTL يدويًا.
/// الفرض اليدوي كان يجعل نصوص قوائم الضغط المطوّل تُعكس أفقياً.
/// «نبض» يحتفظ بالسلوك السابق دون أي تغيير.
private struct AppLayoutDirectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if MUTABAA
        content
        #else
        content.environment(\.layoutDirection, .rightToLeft)
        #endif
    }
}

private extension View {
    /// في «نبض» يعيد هذا المعدّل العرض كما هو تمامًا. في «المتابعة»
    /// يضيف شريط المساحات فقط عندما تكون المساحات فعّالة.
    @ViewBuilder
    func spacesTopInset(_ enabled: Bool) -> some View {
        #if MUTABAA
        if enabled {
            safeAreaInset(edge: .top, spacing: 0) {
                SpacesBar()
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct TabBar: View {
    @Binding var selection: AppTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = tab
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selection == tab ? tab.activeIcon : tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(selection == tab ? Theme.cyan : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.cyan.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Theme.cyan.opacity(0.22), lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "tab-pill", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surfaceRaised.opacity(0.96))
                .shadow(color: .black.opacity(0.5), radius: 22, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

struct PulseWave: Shape {
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        let points: [CGFloat] = [0, 0.10, 0.20, 0.28, 0.34, 0.40, 0.47, 0.55, 0.62, 0.72, 0.82, 0.90, 1.0]
        let heights: [CGFloat] = [0, 0, 2, 2, 16, 2, 2, 26, 2, 2, 12, 2, 0]

        path.move(to: CGPoint(x: 0, y: midY))
        for (index, point) in points.enumerated() {
            let x = width * point
            let amplitude = heights[index] * (1 - abs(point - 0.5) * 0.9)
            let y = midY - amplitude + phase
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}
