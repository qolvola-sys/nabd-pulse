import SwiftUI
import UIKit

#if MUTABAA
/// نافذة إدارة مجموعات الحساب داخل المساحة النشطة.
/// تسمح بالنقل إلى أي مجموعة (حتى ٧ حسابات)، وإنشاء مجموعة
/// جديدة ونقل الحساب إليها، وإعادة تسمية أي مجموعة، مع
/// ضبط دقيق للموضع داخل المجموعة الحالية.
struct MoveAccountSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var groupEditor: GroupEditorRequest?

    private struct GroupEditorRequest: Identifiable {
        let id = UUID()
        let groupID: String?
        let mode: GroupEditorSheet.Mode
    }

    private var groups: [AccountGroup] {
        store.groups
    }

    private var currentGroupID: String? {
        store.groupID(for: account.id)
    }

    private var currentInfo: (group: AccountGroup, index: Int, total: Int)? {
        store.groupInfo(for: account.id)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $groupEditor) { request in
            GroupEditorSheet(mode: request.mode) { name in
                saveGroupEditor(request, name: name)
            }
            .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(account: account, size: 42, showVerified: false)

            VStack(alignment: .leading, spacing: 3) {
                Text("نقل إلى مجموعة")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                    .accessibilityIdentifier("move-sheet-title")
                Text(headerSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
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
            .accessibilityIdentifier("move-sheet-close")
        }
        .padding(.horizontal, 18)
    }

    private var headerSubtitle: String {
        guard let info = currentInfo else {
            return "@\(account.handle) · بدون مجموعة"
        }
        return "@\(account.handle) · \(info.group.name) · \(Num.full(Int64(info.index + 1))) من \(Num.full(Int64(info.total)))"
    }

    private var groupList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 9) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    groupRow(group, index: index)
                }

                createGroupButton
                    .padding(.top, 2)

                Text("تتسع كل مجموعة حتى \(Num.full(Int64(AccountGroup.capacity))) حسابات. اسم أي مجموعة قابل للتغيير في أي وقت.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
    }

    private func groupRow(_ group: AccountGroup, index: Int) -> some View {
        let accent = Theme.chartPalette[index % Theme.chartPalette.count]
        let members = store.accounts(in: group.id)
        let isCurrent = group.id == currentGroupID
        let isAtTop = isCurrent && (currentInfo?.index ?? 0) == 0
        let isFull = members.count >= AccountGroup.capacity
        let canMove = !isAtTop && (isCurrent || !isFull)

        return HStack(spacing: 8) {
            Button {
                move(to: group, memberCount: members.count, isCurrent: isCurrent)
            } label: {
                HStack(spacing: 11) {
                    Text(Num.full(Int64(index + 1)))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(isCurrent ? Color(hex: 0x061016) : accent)
                        .frame(width: 42, height: 42)
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
                            Text(group.name)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
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
                                ForEach(members.prefix(5)) { member in
                                    AvatarView(account: member, size: 20, showVerified: false)
                                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1.5))
                                }
                            }
                            Text("\(Num.full(Int64(members.count))) من \(Num.full(Int64(AccountGroup.capacity)))")
                                .font(.system(size: 9))
                                .foregroundColor(isFull ? Theme.gold : Theme.textTertiary)
                        }
                    }

                    Spacer(minLength: 4)

                    statusLabel(
                        isAtTop: isAtTop,
                        isCurrent: isCurrent,
                        isFull: isFull,
                        accent: accent
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))
            .disabled(!canMove)
            .accessibilityIdentifier("move-group-\(index + 1)")

            Button {
                beginRename(group, memberCount: members.count)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.surfaceRaised.opacity(0.9)))
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .accessibilityIdentifier("rename-group-\(index + 1)")
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
        .opacity(canMove ? 1 : 0.78)
    }

    @ViewBuilder
    private func statusLabel(isAtTop: Bool, isCurrent: Bool, isFull: Bool, accent: Color) -> some View {
        if isAtTop {
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("في المقدمة")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(accent)
        } else if isCurrent {
            VStack(spacing: 2) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 13, weight: .bold))
                Text("إلى المقدمة")
                    .font(.system(size: 8.5, weight: .semibold))
            }
            .foregroundColor(Theme.cyan)
        } else if isFull {
            VStack(spacing: 2) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("ممتلئة")
                    .font(.system(size: 8.5, weight: .semibold))
            }
            .foregroundColor(Theme.gold)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 13, weight: .bold))
                Text("نقل")
                    .font(.system(size: 8.5, weight: .semibold))
            }
            .foregroundColor(Theme.cyan)
        }
    }

    private var createGroupButton: some View {
        Button {
            beginCreateGroup()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("مجموعة جديدة")
                    .font(.system(size: 11, weight: .bold))
                Spacer(minLength: 4)
                Text("وتنقل الحساب إليها")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
            }
            .foregroundColor(Theme.cyan)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.cyan.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.cyan.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityIdentifier("create-group-sheet")
    }

    private var fineTuning: some View {
        let info = currentInfo
        let index = info?.index ?? 0
        let total = max(info?.total ?? 1, 1)
        let groupName = info?.group.name ?? "بدون مجموعة"
        let canMoveUp = info != nil && index > 0
        let canMoveDown = info != nil && index < total - 1

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                Text("ضبط دقيق داخل \(groupName)")
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("الموضع \(Num.full(Int64(index + 1))) من \(Num.full(Int64(total)))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .accessibilityIdentifier("fine-position")
            }
            .foregroundColor(Theme.textTertiary)

            HStack(spacing: 8) {
                fineButton(title: "أعلى المجموعة", icon: "arrow.up.to.line", enabled: canMoveUp) {
                    moveToGroupTop()
                }
                .accessibilityIdentifier("fine-top")

                fineButton(title: "خطوة لأعلى", icon: "chevron.up", enabled: canMoveUp) {
                    moveWithinGroup(by: -1)
                }
                .accessibilityIdentifier("fine-up")
            }

            HStack(spacing: 8) {
                fineButton(title: "خطوة لأسفل", icon: "chevron.down", enabled: canMoveDown) {
                    moveWithinGroup(by: 1)
                }
                .accessibilityIdentifier("fine-down")

                fineButton(title: "أسفل المجموعة", icon: "arrow.down.to.line", enabled: canMoveDown) {
                    moveToGroupBottom()
                }
                .accessibilityIdentifier("fine-bottom")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
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

    private func move(to group: AccountGroup, memberCount: Int, isCurrent: Bool) {
        if isCurrent {
            guard let info = currentInfo, info.index > 0 else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                store.moveAccount(account.id, toPositionInGroup: 0)
            }
            store.showToast("تم نقل @\(account.handle) إلى مقدمة \(group.name)", .success)
            return
        }

        guard memberCount < AccountGroup.capacity else {
            store.showToast(
                "المجموعة ممتلئة — السعة \(Num.full(Int64(AccountGroup.capacity))) حسابات",
                .info
            )
            return
        }

        let moved = withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toGroup: group.id)
        }
        guard moved else {
            store.showToast("تعذّر نقل الحساب إلى هذه المجموعة", .info)
            return
        }
        store.showToast("تم نقل @\(account.handle) إلى \(group.name)", .success)
        dismiss()
    }

    private func moveToGroupTop() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toPositionInGroup: 0)
        }
    }

    private func moveToGroupBottom() {
        guard let info = currentInfo else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, toPositionInGroup: info.total - 1)
        }
    }

    private func moveWithinGroup(by offset: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            store.moveAccount(account.id, by: offset)
        }
    }

    private func beginCreateGroup() {
        store.haptic(.selection)
        groupEditor = GroupEditorRequest(
            groupID: nil,
            mode: .create(
                suggestedName: store.suggestedGroupName,
                groupCount: store.groups.count
            )
        )
    }

    private func beginRename(_ group: AccountGroup, memberCount: Int) {
        store.haptic(.selection)
        groupEditor = GroupEditorRequest(
            groupID: group.id,
            mode: .rename(currentName: group.name, memberCount: memberCount)
        )
    }

    private func saveGroupEditor(_ request: GroupEditorRequest, name: String) -> Bool {
        if let groupID = request.groupID {
            guard store.renameGroup(groupID, to: name) else { return false }
            store.showToast("تم تغيير اسم المجموعة", .success)
            return true
        }

        guard let group = store.createGroup(named: name) else { return false }
        if store.moveAccount(account.id, toGroup: group.id) {
            store.showToast("تم إنشاء «\(group.name)» ونقل @\(account.handle) إليها", .success)
            // تُغلق نافذة التسمية أولًا، ثم نافذة النقل بعدها بقليل.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                dismiss()
            }
        } else {
            store.showToast("تم إنشاء «\(group.name)» — انقل الحساب إليها من القائمة", .info)
        }
        return true
    }
}
#endif
