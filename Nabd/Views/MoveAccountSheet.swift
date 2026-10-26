import SwiftUI
import UIKit

#if MUTABAA
/// نافذة اختيار أي موضع للحساب داخل المساحة النشطة.
struct MoveAccountSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    private var currentIndex: Int {
        store.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
    }

    private var total: Int {
        max(store.accounts.count, 1)
    }

    private var positions: [Int] {
        Array(1...total)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 12) {
                header
                quickActions
                positionList
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
                Text("تحريك الحساب")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("@\(account.handle) · الموضع الحالي \(Num.full(Int64(currentIndex + 1))) من \(Num.full(Int64(total)))")
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

    private var quickActions: some View {
        HStack(spacing: 9) {
            Button {
                move(to: 0)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 11, weight: .bold))
                    Text("إلى الأعلى")
                }
            }
            .buttonStyle(GhostButtonStyle(height: 42))
            .disabled(currentIndex == 0)
            .opacity(currentIndex == 0 ? 0.45 : 1)

            Button {
                move(to: total - 1)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11, weight: .bold))
                    Text("إلى الأسفل")
                }
            }
            .buttonStyle(GhostButtonStyle(height: 42))
            .disabled(currentIndex >= total - 1)
            .opacity(currentIndex >= total - 1 ? 0.45 : 1)
        }
        .padding(.horizontal, 18)
    }

    private var positionList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(positions, id: \.self) { position in
                    positionRow(position)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private func positionRow(_ position: Int) -> some View {
        let index = position - 1
        let occupant = store.accounts.indices.contains(index) ? store.accounts[index] : nil
        let isCurrent = index == currentIndex

        return Button {
            move(to: index)
        } label: {
            HStack(spacing: 11) {
                Text(Num.full(Int64(position)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isCurrent ? Color(hex: 0x061016) : Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isCurrent ? Theme.cyan : Theme.surface))
                    .overlay(Circle().strokeBorder(isCurrent ? .clear : Theme.border, lineWidth: 1))

                if let occupant {
                    AvatarView(account: occupant, size: 30, showVerified: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrent ? "موضع الحساب الآن" : "الموضع \(Num.full(Int64(position)))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(isCurrent ? Theme.cyan : Theme.text)
                    if let occupant {
                        Text(isCurrent
                             ? "@\(occupant.handle)"
                             : "الحساب الحالي هنا: @\(occupant.handle)")
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if isCurrent {
                    Chip(text: "الحالي", color: Theme.cyan)
                } else {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? Theme.cyan.opacity(0.07) : Theme.surface.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.cyan.opacity(0.25) : Theme.borderSoft, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .disabled(isCurrent)
    }

    private func move(to index: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toPosition: index)
        }
        dismiss()
    }
}
#endif
