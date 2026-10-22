import SwiftUI
import UIKit

// MARK: - الصورة الرمزية

struct AvatarView: View {
    let account: Account
    var size: CGFloat = 48
    var showVerified: Bool = true

    private var palette: Color {
        Theme.chartPalette[account.paletteIndex % Theme.chartPalette.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.opacity(0.95), palette.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(account.initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: 0x081018))

            if let raw = account.avatarUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if showVerified && account.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.24))
                    .foregroundColor(Theme.cyan)
                    .background(Circle().fill(Theme.bg).padding(1.5))
                    .padding(2)
            }
        }
    }
}

// MARK: - بطاقة إحصاءة

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = Theme.cyan
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint.opacity(0.14)))
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let hint {
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }
}

// MARK: - شارة

struct Chip: View {
    let text: String
    var color: Color = Theme.cyan
    var filled: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(filled ? Color(hex: 0x061016) : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(filled ? color : color.opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(filled ? .clear : color.opacity(0.22), lineWidth: 1)
        )
    }
}

struct RankBadge: View {
    let index: Int

    var body: some View {
        let colors: [Color] = [Theme.gold, Color(hex: 0xC7D2E0), Color(hex: 0xD08B5C)]
        return ZStack {
            Circle()
                .fill(index < 3 ? colors[index].opacity(0.18) : Theme.surfaceRaised)
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(index < 3 ? colors[index] : Theme.textSecondary)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - عنوان قسم

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.cyan)
                }
            }
        }
    }
}

// MARK: - شريط نسبة

struct ProgressBarLine: View {
    var value: Double
    var gradient: LinearGradient = Theme.cyanGradient
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderSoft)
                Capsule()
                    .fill(gradient)
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - حلقة التوزيع

struct DonutSegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Int64
    let color: Color
}

struct DonutChart: View {
    let segments: [DonutSegment]
    let centerValue: String
    let centerCaption: String

    private var total: Double {
        max(1, segments.reduce(0) { $0 + Double(max($1.value, 0)) })
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.borderSoft, lineWidth: 14)

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let start = segments.prefix(index).reduce(0.0) { $0 + Double(max($1.value, 0)) / total }
                let share = Double(max(segment.value, 0)) / total
                Circle()
                    .trim(from: CGFloat(start) + 0.004, to: CGFloat(start + max(0, share - 0.008)))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: total)
            }

            VStack(spacing: 2) {
                Text(centerValue)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(centerCaption)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(width: 132, height: 132)
    }
}

// MARK: - حقل البحث

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "ابحث باسم الحساب أو المعرف"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .font(.system(size: 13.5))
                .foregroundColor(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }
}

struct SortChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? Color(hex: 0x061016) : Theme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? Theme.cyan : Theme.surface)
                )
                .overlay(
                    Capsule().strokeBorder(selected ? .clear : Theme.borderSoft, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - تنبيه عائم

struct ToastView: View {
    let toast: Toast

    private var tint: Color {
        switch toast.style {
        case .success: return Theme.green
        case .error: return Theme.red
        case .info: return Theme.cyan
        }
    }

    private var icon: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceRaised)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - حالة فارغة

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 70, height: 70)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: 0x061016))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.cyan))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }
}

// MARK: - هيكل تحميل

struct SkeletonBlock: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var radius: CGFloat = 7
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surfaceRaised)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: phase * geo.size.width * 1.7)
                }
                .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - مشاركة ملف

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - خط فاصل متدرّج

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Theme.border.opacity(0.8), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}
