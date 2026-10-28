import SwiftUI
import UIKit

enum AccountSort: String, CaseIterable, Identifiable {
    #if MUTABAA
    case manual
    #endif
    case weekly, views24h, posts24h, views, posts, followers, name, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        #if MUTABAA
        case .manual: return "ترتيب يدوي"
        #endif
        case .weekly: return "تقييم الأسبوع"
        case .views24h: return "الأكثر مشاهدة ٢٤س"
        case .posts24h: return "الأكثر نشراً ٢٤س"
        case .views: return "مشاهدات المنشورات المحمّلة"
        case .posts: return "إجمالي المنشورات"
        case .followers: return "الأكثر متابعة"
        case .name: return "أبجدي"
        case .recent: return "الأحدث تحديثاً"
        }
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// الصفحة تُعرض افتراضياً لحسابات TikTok، ويمكن فتحها مستقلة لفيسبوك.
    var platform: AccountPlatform = .tiktok

    @State private var search = ""
    @State private var sort: AccountSort = {
        #if MUTABAA
        return .manual
        #else
        return .weekly
        #endif
    }()
    @State private var selected: Account?
    @State private var showAdd = false
    @State private var pendingDelete: Account?
    @State private var movingAccount: Account?
    @State private var showFacebook = false
    #if MUTABAA
    @State private var groupEditor: GroupEditorRequest?
    #endif

    private var platformAccounts: [Account] {
        store.accounts.filter { $0.platform == platform }
    }

    private var platformSummary: Summary {
        Summary.make(from: platformAccounts)
    }

    private var filtered: [Account] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = platformAccounts
        if !query.isEmpty {
            list = list.filter {
                $0.handle.lowercased().contains(query) ||
                $0.displayName.lowercased().contains(query)
            }
        }
        switch sort {
        #if MUTABAA
        case .manual:
            // نحافظ على ترتيب المساحة كما حفظه المستخدم.
            break
        #endif
        case .weekly: list.sort { $0.weeklyViews > $1.weeklyViews }
        case .views24h: list.sort { $0.views24h > $1.views24h }
        case .posts24h: list.sort { $0.posts24h > $1.posts24h }
        case .views: list.sort { $0.views > $1.views }
        case .posts: list.sort { $0.posts > $1.posts }
        case .followers: list.sort { $0.followers > $1.followers }
        case .name: list.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .recent: list.sort { ($0.lastSyncedAt ?? "") > ($1.lastSyncedAt ?? "") }
        }
        return list
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                #if MUTABAA
                if platform != .tiktok && !store.isDirect {
                    directLockedCard
                }
                #endif
                summaryStrip
                #if MUTABAA
                if platform == .instagram {
                    likesStrip
                }
                if platform == .tiktok {
                    facebookEntryCard
                }
                #endif
                SearchField(text: $search)
                sortChips

                if store.isLoading && platformAccounts.isEmpty {
                    loadingRows
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    #if MUTABAA
                    if sort == .manual || !store.spacesEnabled {
                        groupedAccountsList
                    } else {
                        flatAccountsList
                    }
                    #else
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { account in
                            accountCard(account)
                        }
                    }
                    #endif
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .refreshable {
            await store.syncAll()
        }
        .task {
            // معاينة تلقائية داخل CI: --sheet=add أو --sheet=detail
            let args = ProcessInfo.processInfo.arguments
            guard let flag = args.first(where: { $0.hasPrefix("--sheet=") }) else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if flag == "--sheet=add" {
                showAdd = true
            } else if flag == "--sheet=detail", selected == nil {
                selected = store.topAccounts.first { $0.platform == platform }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAccountsView(platform: platform)
                .environmentObject(store)
        }
        .sheet(item: $selected) { account in
            AccountDetailView(account: account)
                .environmentObject(store)
        }
        .sheet(item: $movingAccount) { account in
            #if MUTABAA
            MoveAccountSheet(account: account)
                .environmentObject(store)
            #else
            EmptyView()
            #endif
        }
        #if MUTABAA
        .sheet(item: $groupEditor) { request in
            GroupEditorSheet(mode: request.mode) { name in
                saveGroupEditor(request, name: name)
            }
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showFacebook) {
            ZStack {
                AppBackground()
                AccountsView(platform: .facebook)
                    .environmentObject(store)
            }
        }
        #endif
        .confirmationDialog(
            "إزالة \(pendingDelete?.handleLabel ?? "")؟",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("إزالة الحساب", role: .destructive) {
                if let account = pendingDelete {
                    Task { await store.delete(account) }
                }
                pendingDelete = nil
            }
            Button("إلغاء", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("ستُحذف بياناته من \(AppVariant.name) فقط، ولن يتأثر حساب \(platform.title).")
        }
    }

    private var maxViews: Int64 {
        max(platformAccounts.map { $0.views24h }.max() ?? 1, 1)
    }

    #if MUTABAA
    private var facebookCount: Int {
        store.accounts.filter { $0.platform == .facebook }.count
    }

    /// مدخل ظاهر دائماً داخل تبويب الحسابات، حتى لو كان شريط المساحات
    /// مخفياً في الوضع التجريبي أو عند استخدام الخادم.
    private var facebookEntryCard: some View {
        Button {
            store.haptic(.impact)
            showFacebook = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.cyan.opacity(0.13))
                    Image(systemName: "globe")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.cyan)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("صفحات فيسبوك")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("أضف الصفحات واقرأ المنشورات ومشاهدات الفيديو")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                if facebookCount > 0 {
                    Text(Num.full(Int64(facebookCount)))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.cyan.opacity(0.12)))
                }

                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.cyan.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityIdentifier("accounts-open-facebook")
    }

    private var directLockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(platform.title) يحتاج الوضع المباشر", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.gold)

            Text(store.isDemo
                 ? "أنت في الوضع التجريبي. أوقفه لتقرأ أرقام \(platform.title) الحقيقية."
                 : "أنت تستخدم الخادم الخاص. \(platform.title) يقرأ الحسابات العامة مباشرة دون خادم. حسابات الخادم تبقى محفوظة ويمكن الرجوع إليها.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)

            Button {
                store.enableDirectMode()
                store.showToast("تم تشغيل الوضع المباشر", .success)
                store.haptic(.success)
            } label: {
                Label("تشغيل الوضع المباشر", systemImage: "bolt.fill")
            }
            .buttonStyle(GradientButtonStyle(height: 44))
        }
        .card(padding: 14)
    }
    #endif

    private func accountCard(_ account: Account) -> some View {
        AccountRow(account: account, maxViews: maxViews)
            .contentShape(Rectangle())
            .onTapGesture {
                store.haptic(.impact)
                selected = account
            }
            .contextMenu {
                #if MUTABAA
                if canReorder {
                    Button {
                        movingAccount = account
                        store.haptic(.selection)
                    } label: {
                        Label("نقل إلى مجموعة…", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("move-to-group-menu")
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.moveAccount(account.id, by: -1)
                        }
                    } label: {
                        Label("تحريك لأعلى", systemImage: "chevron.up")
                    }
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.moveAccount(account.id, by: 1)
                        }
                    } label: {
                        Label("تحريك لأسفل", systemImage: "chevron.down")
                    }
                    Divider()
                }
                #endif

                Button {
                    Task { await store.sync(account) }
                } label: {
                    Label("مزامنة الآن", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    copyLink(account)
                } label: {
                    Label("نسخ الرابط", systemImage: "link")
                }
                Button {
                    openAccountLink(account)
                } label: {
                    Label("فتح في \(platform.title)", systemImage: "arrow.up.right.square")
                }
                Divider()
                Button(role: .destructive) {
                    pendingDelete = account
                } label: {
                    Label("إزالة الحساب", systemImage: "trash")
                }
            }
    }

    #if MUTABAA
    /// مجموعة كما تُعرض في القائمة، مع الحسابات المطابقة للبحث فقط.
    private struct DisplayGroup: Identifiable {
        let id: String
        let name: String
        let accounts: [Account]
        /// العدد الفعلي في المجموعة، وليس عدد نتائج البحث.
        let totalCount: Int
        let index: Int
        let isManaged: Bool
    }

    private struct GroupEditorRequest: Identifiable {
        let id = UUID()
        let groupID: String?
        let mode: GroupEditorSheet.Mode
    }

    private var hasCustomGroups: Bool {
        store.spacesEnabled && !store.groups.isEmpty
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canReorder: Bool {
        store.isDirect && sort == .manual && !isSearching
    }

    private var flatAccountsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(filtered) { account in
                accountCard(account)
            }
        }
    }

    private var displayGroups: [DisplayGroup] {
        guard !filtered.isEmpty else { return [] }

        if hasCustomGroups && sort == .manual {
            var result: [DisplayGroup] = []
            var claimed = Set<String>()

            for (index, group) in store.groups.enumerated() {
                let members = filtered.filter { store.groupID(for: $0.id) == group.id }
                claimed.formUnion(members.map(\.id))
                if isSearching && members.isEmpty { continue }
                result.append(
                    DisplayGroup(
                        id: group.id,
                        name: group.name,
                        accounts: members,
                        // السعة مشتركة بين المنصتين، لذا نعرض العدد الفعلي
                        // لكل حسابات المجموعة وليس حسابات المنصة وحدها.
                        totalCount: store.accounts(in: group.id).count,
                        index: index,
                        isManaged: true
                    )
                )
            }

            // لا نُخفي أي حساب إن كانت العضوية قديمة أو ناقصة.
            let orphans = filtered.filter { !claimed.contains($0.id) }
            if !orphans.isEmpty {
                result.append(
                    DisplayGroup(
                        id: "__other",
                        name: "حسابات أخرى",
                        accounts: orphans,
                        totalCount: orphans.count,
                        index: store.groups.count,
                        isManaged: false
                    )
                )
            }
            return result
        }

        // الوضع التجريبي/الخادم، أو الترتيب حسب مقياس: تقسيم بصري فقط.
        let starts = stride(from: 0, to: filtered.count, by: AccountGroup.capacity)
        return starts.enumerated().map { index, start in
            let members = Array(filtered[start..<min(start + AccountGroup.capacity, filtered.count)])
            return DisplayGroup(
                id: "auto-\(index)",
                name: "المجموعة \(Num.full(Int64(index + 1)))",
                accounts: members,
                totalCount: members.count,
                index: index,
                isManaged: false
            )
        }
    }

    private var groupedAccountsList: some View {
        LazyVStack(spacing: 0) {
            if canReorder {
                groupToolbar
                    .padding(.bottom, 12)
            }

            ForEach(displayGroups) { group in
                groupSection(group)
                if group.id != displayGroups.last?.id {
                    groupSeparator
                }
            }
        }
    }

    private var groupToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("المجموعات")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(Theme.cyan)

                Text("\(Num.full(Int64(store.groups.count))) مجموعات · حتى \(Num.full(Int64(AccountGroup.capacity))) حسابات لكل مجموعة")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            Button {
                beginCreateGroup()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("مجموعة جديدة")
                        .font(.system(size: 10.5, weight: .bold))
                }
                .foregroundColor(Theme.cyan)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cyan.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.cyan.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .accessibilityIdentifier("create-group")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }

    private func groupSection(_ group: DisplayGroup) -> some View {
        let accent = Theme.chartPalette[group.index % Theme.chartPalette.count]
        return VStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: accent.opacity(0.7), radius: 4)
                Text(group.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                Text("\(Num.full(Int64(group.totalCount))) من \(Num.full(Int64(AccountGroup.capacity)))")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .accessibilityIdentifier("group-count-\(group.index)")
                Spacer(minLength: 4)

                if group.isManaged && canReorder {
                    Button {
                        beginRenameGroup(group)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("تسمية")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.surface.opacity(0.8)))
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rename-group-\(group.index + 1)")
                }
            }
            .padding(.horizontal, 4)

            if group.accounts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 10, weight: .semibold))
                    Text(isSearching ? "لا نتائج في هذه المجموعة" : "لا حسابات \(platform.title) في هذه المجموعة بعد")
                        .font(.system(size: 9.5))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            } else {
                ForEach(group.accounts) { account in
                    VStack(spacing: 8) {
                        accountCard(account)
                        if canReorder {
                            reorderBar(account)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.14),
                            Theme.surface.opacity(0.50),
                            accent.opacity(0.04),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(accent.opacity(0.24), lineWidth: 1)
        )
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

    private func beginRenameGroup(_ group: DisplayGroup) {
        guard group.isManaged,
              let stored = store.groups.first(where: { $0.id == group.id }) else { return }
        store.haptic(.selection)
        groupEditor = GroupEditorRequest(
            groupID: stored.id,
            mode: .rename(currentName: stored.name, memberCount: group.totalCount)
        )
    }

    private func saveGroupEditor(_ request: GroupEditorRequest, name: String) -> Bool {
        if let groupID = request.groupID {
            guard store.renameGroup(groupID, to: name) else { return false }
            store.showToast("تم تغيير اسم المجموعة", .success)
            return true
        }
        guard let group = store.createGroup(named: name) else { return false }
        store.showToast("تم إنشاء «\(group.name)»", .success)
        return true
    }

    private var groupSeparator: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Theme.red.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            HStack(spacing: 5) {
                Image(systemName: "square.split.2x1.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("فاصل المجموعات")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .foregroundColor(Theme.red)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.red.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Theme.red.opacity(0.28), lineWidth: 1))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.red.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
        }
        .padding(.vertical, 14)
    }

    private func reorderBar(_ account: Account) -> some View {
        let groupID = store.groupID(for: account.id)
        let members = groupID.map { groupID in
            platformAccounts.filter { store.groupID(for: $0.id) == groupID }
        } ?? platformAccounts
        let index = members.firstIndex(where: { $0.id == account.id }) ?? 0
        let count = max(members.count, 1)
        let groupName = groupID.flatMap { groupID in
            store.groups.first(where: { $0.id == groupID })?.name
        }
        let positionText: String
        if let groupName {
            positionText = "\(groupName) · الموضع \(Num.full(Int64(index + 1))) من \(Num.full(Int64(count)))"
        } else {
            positionText = "الموضع \(Num.full(Int64(index + 1))) من \(Num.full(Int64(count)))"
        }

        return HStack(spacing: 8) {
            Text(positionText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("position-\(account.handle)")

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    store.moveAccount(account.id, by: -1)
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(index > 0 ? Theme.cyan : Theme.textTertiary.opacity(0.35))
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    store.moveAccount(account.id, by: 1)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(index < count - 1 ? Theme.cyan : Theme.textTertiary.opacity(0.35))
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .disabled(index >= count - 1)

            Button {
                movingAccount = account
                store.haptic(.selection)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("نقل إلى مجموعة")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundColor(Theme.cyan)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cyan.opacity(0.10)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.cyan.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("move-to-group-bar")
        }
        .padding(.horizontal, 2)
    }
    #endif

    /// لا توجد منشورات مقروءة لأي حساب في هذه المنصة بعد، فالأرقام
    /// المعروضة ستكون أصفاراً غير حقيقية. نعرض «—» بدلاً منها.
    private var platformNumbersUnavailable: Bool {
        platform != .tiktok
            && platformSummary.loadedVideos == 0
            && platformAccounts.contains { $0.status == "pending" }
    }

    private var posts24hText: String {
        if platformNumbersUnavailable { return "—" }
        return platformSummary.dailyComplete
            ? Num.full(Int64(platformSummary.posts24h))
            : Num.atLeast(Int64(platformSummary.posts24h))
    }

    private var views24hText: String {
        if platformNumbersUnavailable { return "—" }
        return Num.maybeApprox(
            platformSummary.views24h,
            exact: platformSummary.dailyComplete && platformSummary.dailyViewsExact
        )
    }

    private var weeklyViewsText: String {
        if platformNumbersUnavailable { return "—" }
        return Num.maybeApprox(
            platformSummary.weeklyViews,
            exact: platformSummary.weeklyComplete && platformSummary.weeklyViewsExact
        )
    }

    private var weeklyScoreText: String {
        if platformNumbersUnavailable { return "—" }
        let exact = platformSummary.weeklyComplete && platformSummary.weeklyViewsExact
        return Num.score(platformSummary.weeklyScore, exact: exact) + "%"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if platform != .tiktok {
                        Image(systemName: platform.icon)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(platform == .facebook ? Theme.cyan : Theme.pink)
                    }
                    Text(platform == .tiktok ? "الحسابات" : "حسابات \(platform.title)")
                        .font(.system(size: platform == .tiktok ? 26 : 22, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                #if MUTABAA
                if store.spacesEnabled {
                    Text("\(platformAccounts.count) \(platform == .facebook ? "صفحة" : "حساباً") في مساحة «\(store.activeSpaceName)»")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(platformAccounts.count) \(platform == .facebook ? "صفحة" : "حساباً") في \(AppVariant.name)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                }
                #else
                Text("\(platformAccounts.count) \(platform == .facebook ? "صفحة" : "حساباً") في \(AppVariant.name)")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                #endif
            }
            Spacer()
            Button {
                store.haptic(.impact)
                showAdd = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("إضافة")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundColor(Color(hex: 0x061016))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.cyanGradient))
                .shadow(color: Theme.cyan.opacity(0.28), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle())
            .disabled(platform != .tiktok && !store.isDirect)
            .opacity(platform != .tiktok && !store.isDirect ? 0.45 : 1)

            if platform != .tiktok {
                Button {
                    store.haptic(.impact)
                    Task { await store.syncAll() }
                } label: {
                    Group {
                        if store.isSyncing {
                            ProgressView()
                                .tint(Theme.cyan)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(store.isSyncing)
                .accessibilityLabel("مزامنة حسابات \(platform.title)")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surfaceRaised))
                        .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("إغلاق صفحة \(platform.title)")
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            stripItem(title: "منشورات ٢٤س", value: posts24hText, tint: Theme.cyan)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
            stripItem(title: "مشاهدات ٢٤س", value: views24hText, tint: Theme.violet)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
            stripItem(title: "مشاهدات ٧ أيام", value: weeklyViewsText, tint: Theme.cyan)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
            stripItem(title: "تقييم المنصة", value: weeklyScoreText, tint: WeeklyScoreStyle.color(for: platformSummary.weeklyScore))
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }

    private func stripItem(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// إحصاءات تفاعل إنستغرام في بطاقة منفصلة عن المشاهدات.
    private var likesStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.pink)
                Text("إعجابات منشورات إنستغرام")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 4)
                Text("آخر ٢٤ ساعة و٧ أيام")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }

            HStack(spacing: 0) {
                stripItem(
                    title: "إعجابات ٢٤س",
                    value: platformNumbersUnavailable
                        ? "—"
                        : Num.maybeApprox(platformSummary.likes24h, exact: platformSummary.dailyComplete),
                    tint: Theme.pink
                )
                Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
                stripItem(
                    title: "إعجابات ٧ أيام",
                    value: platformNumbersUnavailable
                        ? "—"
                        : Num.maybeApprox(platformSummary.likes7d, exact: platformSummary.weeklyComplete),
                    tint: Theme.violet
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.pink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.pink.opacity(0.18), lineWidth: 1)
        )
    }

    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AccountSort.allCases) { option in
                    SortChip(title: option.title, selected: sort == option) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            sort = option
                        }
                        store.haptic(.selection)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(height: 46, width: 46, radius: 15)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 11, width: 120)
                        SkeletonBlock(height: 8, width: 80)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        SkeletonBlock(height: 11, width: 60)
                        SkeletonBlock(height: 8, width: 40)
                    }
                }
                .card(padding: 14, radius: 20)
            }
        }
    }

    private var emptyMessage: String {
        if platform == .facebook {
            #if MUTABAA
            if store.spacesEnabled {
                return "الصق روابط صفحات فيسبوك العامة (حتى ٥٠٠ رابط دفعة واحدة) وستُضاف إلى مساحة «\(store.activeSpaceName)» مع منشوراتها ومشاهدات فيديوها."
            }
            #endif
            return "الصق روابط صفحات فيسبوك العامة (حتى ٥٠٠ رابط دفعة واحدة) وسنرتّب لك المنشورات ومشاهدات الفيديو."
        }
        if platform == .instagram {
            #if MUTABAA
            if store.spacesEnabled {
                return "الصق روابط حسابات إنستغرام العامة (instagram.com/username أو @username) وستُضاف إلى مساحة «\(store.activeSpaceName)» مع مشاهداتها وإعجاباتها اليومية والأسبوعية."
            }
            #endif
            return "الصق روابط حسابات إنستغرام العامة (instagram.com/username أو @username) وسنرتّب لك المشاهدات والإعجابات اليومية والأسبوعية."
        }
        #if MUTABAA
        if store.spacesEnabled {
            return "الصق روابط حسابات TikTok (حتى ٥٠٠ رابط دفعة واحدة) وستُضاف إلى مساحة «\(store.activeSpaceName)» مع إحصاءاتها."
        }
        return "الصق روابط حسابات TikTok (حتى ٥٠٠ رابط دفعة واحدة) وسنرتّب لك المنشورات والمشاهدات."
        #else
        return "الصق روابط حسابات TikTok (حتى ١٠٠ رابط دفعة واحدة) وسنرتّب لك المنشورات والمشاهدات."
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            if !search.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "لا نتائج",
                    message: "جرّب اسماً آخر أو امسح البحث.",
                    actionTitle: "مسح البحث",
                    action: { search = "" }
                )
            } else {
                EmptyStateView(
                    icon: platform == .tiktok ? "person.badge.plus" : platform.icon,
                    title: platform == .tiktok ? "ابدأ بإضافة حساباتك" : "ابدأ بإضافة حسابات \(platform.title)",
                    message: emptyMessage,
                    actionTitle: platform != .tiktok && !store.isDirect ? "تشغيل الوضع المباشر" : "إضافة روابط",
                    action: {
                        if platform != .tiktok && !store.isDirect {
                            store.enableDirectMode()
                            store.showToast("تم تشغيل الوضع المباشر", .success)
                        } else {
                            showAdd = true
                        }
                    }
                )
            }
        }
        .card(padding: 6)
    }

    private func copyLink(_ account: Account) {
        UIPasteboard.general.string = account.url
        store.showToast("تم نسخ رابط \(account.handleLabel)", .success)
        store.haptic(.selection)
    }

    private func openAccountLink(_ account: Account) {
        guard let url = URL(string: account.url) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - صف الحساب

struct AccountRow: View {
    let account: Account
    let maxViews: Int64

    private var palette: Color {
        Theme.chartPalette[account.paletteIndex % Theme.chartPalette.count]
    }

    /// الأرقام غير متاحة فعلاً عندما لم تُقرأ أي منشورات بعد.
    private var numbersUnavailable: Bool {
        account.status == "pending" && account.fetchedVideos == 0
    }

    private var views24hText: String {
        if numbersUnavailable { return "—" }
        return Num.maybeApprox(account.views24h, exact: account.dailyComplete && account.dailyViewsExact)
    }

    private var posts24hText: String {
        if numbersUnavailable { return "—" }
        return account.dailyComplete ? Num.full(Int64(account.posts24h)) : Num.atLeast(Int64(account.posts24h))
    }

    private var avg24hText: String {
        if numbersUnavailable { return "—" }
        return Num.maybeApprox(account.avgViews24h, exact: account.dailyComplete && account.dailyViewsExact)
    }

    private var weeklyViewsText: String {
        if numbersUnavailable { return "—" }
        return Num.maybeApprox(account.weeklyViews, exact: account.weeklyScoreExact)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(account: account, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(account.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        if account.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.cyan)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: account.platform.icon)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(account.isFacebook ? Theme.cyan : Theme.pink)
                        Text(account.handleLabel)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    if numbersUnavailable,
                       let reason = account.error,
                       !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 8.5))
                            .foregroundColor(Theme.gold)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(views24hText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("مشاهدة ٢٤س")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                statColumn(value: posts24hText, label: "منشور ٢٤س")
                statColumn(value: avg24hText, label: "متوسط ٢٤س")
                statColumn(value: Num.maybeApprox(account.followers, exact: account.profileExact), label: "متابع")

                Spacer(minLength: 2)

                statusChip
                    .layoutPriority(1)
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.violet)
                Text("مشاهدات ٧ أيام")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                Text(weeklyViewsText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 4)
                WeeklyScoreBadge(score: account.weeklyScore, compact: true, exact: account.weeklyScoreExact)
            }

            if account.isInstagram {
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Theme.pink)
                    Text("إعجابات ٢٤س")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                    Text(numbersUnavailable ? "—" : Num.maybeApprox(account.likes24h, exact: account.dailyComplete))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                    Text("٧ أيام")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                    Text(numbersUnavailable ? "—" : Num.maybeApprox(account.likes7d, exact: account.weeklyComplete))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            ProgressBarLine(
                value: Double(account.views24h) / Double(max(maxViews, 1)),
                gradient: LinearGradient(colors: [palette.opacity(0.9), palette.opacity(0.4)], startPoint: .leading, endPoint: .trailing),
                height: 3
            )
        }
        .card(padding: 14, radius: 20)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(minWidth: 52, alignment: .leading)
    }

    @ViewBuilder
    private var statusChip: some View {
        if account.status == "needs_reconnect" {
            Chip(text: "أعد الربط", color: Theme.red, icon: "exclamationmark.triangle.fill")
        } else if account.status == "error" || account.status == "cached" {
            Chip(text: "آخر بيانات محفوظة", color: Theme.textSecondary, icon: "clock.arrow.circlepath")
        } else if account.status == "pending" {
            Chip(text: "بانتظار التحديث", color: Theme.gold, icon: "clock")
        } else if account.status == "public" {
            Chip(text: "بيانات مباشرة", color: Theme.cyan, icon: "globe")
        } else if !account.connected {
            Chip(text: "غير مربوط", color: Theme.gold, icon: "link.badge.plus")
        } else if account.coverage < 0.95 && account.coverage > 0 {
            Chip(text: "جزئي", color: Theme.violet, icon: "chart.pie.fill")
        }
    }
}
