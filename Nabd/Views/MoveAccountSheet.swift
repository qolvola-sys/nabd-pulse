import SwiftUI
import UIKit

#if MUTABAA
/// نافذة اختيار المجموعة التي يُنقل إليها الحساب داخل المساحة النشطة.
/// المجموعات هي نفس تقسيمات قائمة «المتابعة» (٣ حسابات لكل مجموعة)،
/// واختيار مجموعة ينقل الحساب إلى أول موضع فيها مع إبقاء أدوات الضبط الدقيق.
struct MoveAccountSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    private let groupSize = 3

    private struct AccountGroup: Identifiable {
        let id: Int
        let accounts: [Account]
    }

    private var currentIndex: Int {
        store.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
    }

    private var total: Int {
        max(store.accounts.count, 1)
    }

    private var currentGroupIndex: Int {
        currentIndex / groupSize
    }

    private var groups: [AccountGroup] {
        guard !store.accounts.isEmpty else { return [] }
        return stride(from: 0, to: store.accounts.count, by: groupSize).map { start in
            AccountGroup(
                id: start / groupSize,
                accounts: Array(store.accounts[start..<min(start + groupSize, store.accounts.count)])
            )
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 12) {
                header
                groupList
                fineTuning
            }
            .padding(.top, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(account: account, size: 42, showVerified: false)

            VStack(alignment: .leading, spacing: 3) {
                Text("نقل إلى مجموعة")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("@\(account.handle) · المجموعة \(Num.full(Int64(currentGroupIndex + 1))) من \(Num.full(Int64(max(groups.count, 1))))")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 18)
    }

    private var groupList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 9) {
                ForEach(groups) { group in
                    groupRow(group)
                }

                if groups.count <= 1 {
                    Text("أضف حسابات أكثر لتظهر مجموعات إضافية يمكن النقل بينها.")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
    }

    private func groupRow(_ group: AccountGroup) -> some View {
        let accent = Theme.chartPalette[group.id % Theme.chartPalette.count]
        let isCurrent = group.id == currentGroupIndex
        let isFront = isCurrent && currentIndex == group.id * groupSize

        return Button {
            move(toGroup: group.id)
        } label: {
            HStack(spacing: 11) {
                Text(Num.full(Int64(group.id + 1)))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(isCurrent ? Color(hex: 0x061016) : accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isCurrent ? accent : accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isCurrent ? .clear : accent.opacity(0.24), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("المجموعة \(Num.full(Int64(group.id + 1)))")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Theme.text)
                        if isCurrent {
                            Text("الحالية")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(accent.opacity(0.12)))
                        }
                    }

                    HStack(spacing: 6) {
                        HStack(spacing: -7) {
                            ForEach(group.accounts) { member in
                                AvatarView(account: member, size: 20, showVerified: false)
                                    .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1.5))
                            }
                        }
                        Text("\(Num.full(Int64(group.accounts.count))) من الحسابات")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                if isFront {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("في المقدمة")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(accent)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(isCurrent ? "إلى المقدمة" : "نقل")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .foregroundColor(Theme.cyan)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.08) : Theme.surface.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isCurrent ? accent.opacity(0.34) : Theme.borderSoft, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .disabled(isFront)
        .opacity(isFront ? 0.82 : 1)
        .accessibilityIdentifier("move-group-\(group.id + 1)")
    }

    private var fineTuning: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                Text("ضبط دقيق")
                    .font(.system(size: 10, weight: .bold))
                Spacer(minLength: 4)
                Text("الموضع \(Num.full(Int64(currentIndex + 1))) من \(Num.full(Int64(total)))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .foregroundColor(Theme.textTertiary)

            HStack(spacing: 8) {
                fineButton(title: "أعلى القائمة", icon: "arrow.up.to.line", enabled: currentIndex > 0) {
                    move(toPosition: 0)
                }
                fineButton(title: "خطوة لأعلى", icon: "chevron.up", enabled: currentIndex > 0) {
                    move(by: -1)
                }
            }

            HStack(spacing: 8) {
                fineButton(title: "خطوة لأسفل", icon: "chevron.down", enabled: currentIndex < total - 1) {
                    move(by: 1)
                }
                fineButton(title: "أسفل القائمة", icon: "arrow.down.to.line", enabled: currentIndex < total - 1) {
                    move(toPosition: total - 1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Theme.bg.opacity(0), Theme.bg.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func fineButton(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(enabled ? Theme.text : Theme.textTertiary.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.surfaceRaised.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(!enabled)
    }

    private func move(toGroup group: Int) {
        let target = group * groupSize
        guard target != currentIndex else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toGroup: group, groupSize: groupSize)
        }
        store.showToast("تم نقل @\(account.handle) إلى المجموعة \(Num.full(Int64(group + 1)))", .success)
        dismiss()
    }

    private func move(toPosition position: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toPosition: position)
        }
    }

    private func move(by offset: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, by: offset)
        }
    }
}
#endif
