import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case accounts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "الرئيسية"
        case .accounts: return "الحسابات"
        case .settings: return "الإعدادات"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "waveform.path.ecg"
        case .accounts: return "person.2"
        case .settings: return "slider.horizontal.3"
        }
    }

    var activeIcon: String {
        switch self {
        case .dashboard: return "waveform.path.ecg"
        case .accounts: return "person.2.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab

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
        .onAppear { store.bootstrap() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { store.refreshIfStale() }
        }
    }

    private var spacesTopInsetEnabled: Bool {
        #if MUTABAA
        return store.spacesEnabled
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
