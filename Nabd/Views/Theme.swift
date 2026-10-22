import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(hex: 0x07090D)
    static let bgSoft = Color(hex: 0x0B0F16)
    static let surface = Color(hex: 0x11161F)
    static let surfaceRaised = Color(hex: 0x161C28)
    static let border = Color(hex: 0x232B3A)
    static let borderSoft = Color(hex: 0x1A2130)

    static let text = Color(hex: 0xF3F6FA)
    static let textSecondary = Color(hex: 0x96A1B4)
    static let textTertiary = Color(hex: 0x5F6A7D)

    static let cyan = Color(hex: 0x25F4EE)
    static let pink = Color(hex: 0xFE2C55)
    static let violet = Color(hex: 0x7C5CFF)
    static let gold = Color(hex: 0xFFC24B)
    static let green = Color(hex: 0x3DDC97)
    static let red = Color(hex: 0xFF5A6E)

    static let brand = LinearGradient(
        colors: [Color(hex: 0x25F4EE), Color(hex: 0x6BE7F5), Color(hex: 0xFE2C55)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cyanGradient = LinearGradient(
        colors: [Color(hex: 0x25F4EE), Color(hex: 0x35C9E8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [Color(hex: 0xFE2C55), Color(hex: 0xFF7A5C)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let violetGradient = LinearGradient(
        colors: [Color(hex: 0x7C5CFF), Color(hex: 0xB45CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let chartPalette: [Color] = [
        Color(hex: 0x25F4EE), Color(hex: 0x7C5CFF), Color(hex: 0xFE2C55), Color(hex: 0xFFC24B), Color(hex: 0x3DDC97),
    ]

    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 16
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.violet.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 460
            )
            RadialGradient(
                colors: [Theme.cyan.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 420
            )
            LinearGradient(
                colors: [.clear, Theme.bg.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.radius
    var raised: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(raised ? Theme.surfaceRaised : Theme.surface.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.border.opacity(0.9), Theme.borderSoft.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.radius, raised: Bool = false) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, raised: raised))
    }

    func gradientTextMask(_ gradient: LinearGradient = Theme.brand) -> some View {
        overlay(gradient).mask(self)
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.cyanGradient
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: 0x061016))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(gradient)
                    .shadow(color: Theme.cyan.opacity(configuration.isPressed ? 0.1 : 0.3), radius: 18, y: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
