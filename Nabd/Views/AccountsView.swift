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

    private var filtered: [Account] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = store.accounts
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
                summaryStrip
                SearchField(text: $search)
                sortChips

                if store.isLoading && store.accounts.isEmpty {
                    loadingRows
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    #if MUTABAA
                    groupedAccountsList
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
                selected = store.topAccounts.first
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAccountsView()
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
        .confirmationDialog(
            "إزالة @\(pendingDelete?.handle ?? "")؟",
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
            Text("ستُحذف بياناته من \(AppVariant.name) فقط، ولن يتأثر حساب TikTok.")
        }
    }

    private var maxViews: Int64 {
        max(store.accounts.map { $0.views24h }.max() ?? 1, 1)
    }

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
                    openInTikTok(account)
                } label: {
                    Label("فتح في TikTok", systemImage: "arrow.up.right.square")
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
    private struct AccountGroup: Identifiable {
        let id: Int
        let accounts: [Account]
    }

    private var accountGroups: [AccountGroup] {
        guard !filtered.isEmpty else { return [] }
        return stride(from: 0, to: filtered.count, by: 3).map { start in
            AccountGroup(
                id: start / 3,
                accounts: Array(filtered[start..<min(start + 3, filtered.count)])
            )
        }
    }

    private var canReorder: Bool {
        store.isDirect &&
        sort == .manual &&
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var groupedAccountsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(accountGroups) { group in
                groupSection(group)
                if group.id < accountGroups.count - 1 {
                    groupSeparator
                }
            }
        }
    }

    private func groupSection(_ group: AccountGroup) -> some View {
        let accent = Theme.chartPalette[group.id % Theme.chartPalette.count]
        return VStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: accent.opacity(0.7), radius: 4)
                Text("المجموعة \(Num.full(Int64(group.id + 1)))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                Text("\(Num.full(Int64(group.accounts.count))) من الحسابات")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                Spacer(minLength: 0)
                if canReorder {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9, weight: .bold))
                        Text("رتّب بالأسهم أو انقل إلى مجموعة")
                            .font(.system(size: 8.5))
                    }
                    .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            ForEach(group.accounts) { account in
                VStack(spacing: 8) {
                    accountCard(account)
                    if canReorder {
                        reorderBar(account)
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
        let index = store.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
        let count = store.accounts.count

        return HStack(spacing: 8) {
            Text("المجموعة \(Num.full(Int64(index / 3 + 1))) · الموضع \(Num.full(Int64(index + 1))) من \(Num.full(Int64(count)))")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textTertiary)

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
        }
        .padding(.horizontal, 2)
    }
    #endif

    private var posts24hText: String {
        store.summary.dailyComplete
            ? Num.full(Int64(store.summary.posts24h))
            : Num.atLeast(Int64(store.summary.posts24h))
    }

    private var views24hText: String {
        Num.maybeApprox(
            store.summary.views24h,
            exact: store.summary.dailyComplete && store.summary.dailyViewsExact
        )
    }

    private var weeklyViewsText: String {
        Num.maybeApprox(
            store.summary.weeklyViews,
            exact: store.summary.weeklyComplete && store.summary.weeklyViewsExact
        )
    }

    private var weeklyScoreText: String {
        let exact = store.summary.weeklyComplete && store.summary.weeklyViewsExact
        return Num.score(store.summary.weeklyScore, exact: exact) + "%"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("الحسابات")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                #if MUTABAA
                if store.spacesEnabled {
                    Text("\(store.accounts.count) حساباً في مساحة «\(store.activeSpaceName)»")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(store.accounts.count) حساباً في \(AppVariant.name)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                }
                #else
                Text("\(store.accounts.count) حساباً في \(AppVariant.name)")
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
            stripItem(title: "تقييم المنصة", value: weeklyScoreText, tint: WeeklyScoreStyle.color(for: store.summary.weeklyScore))
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
                    icon: "person.badge.plus",
                    title: "ابدأ بإضافة حساباتك",
                    message: emptyMessage,
                    actionTitle: "إضافة روابط",
                    action: { showAdd = true }
                )
            }
        }
        .card(padding: 6)
    }

    private func copyLink(_ account: Account) {
        UIPasteboard.general.string = account.url
        store.showToast("تم نسخ رابط @\(account.handle)", .success)
        store.haptic(.selection)
    }

    private func openInTikTok(_ account: Account) {
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

    private var views24hText: String {
        Num.maybeApprox(account.views24h, exact: account.dailyComplete && account.dailyViewsExact)
    }

    private var posts24hText: String {
        account.dailyComplete ? Num.full(Int64(account.posts24h)) : Num.atLeast(Int64(account.posts24h))
    }

    private var avg24hText: String {
        Num.maybeApprox(account.avgViews24h, exact: account.dailyComplete && account.dailyViewsExact)
    }

    private var weeklyViewsText: String {
        Num.maybeApprox(account.weeklyViews, exact: account.weeklyScoreExact)
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
                    Text("@" + account.handle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
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
