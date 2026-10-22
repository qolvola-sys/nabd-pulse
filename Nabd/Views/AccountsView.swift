import SwiftUI
import UIKit

enum AccountSort: String, CaseIterable, Identifiable {
    case views, posts, followers, name, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .views: return "الأكثر مشاهدة"
        case .posts: return "الأكثر منشورات"
        case .followers: return "الأكثر متابعة"
        case .name: return "أبجدي"
        case .recent: return "الأحدث تحديثاً"
        }
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var search = ""
    @State private var sort: AccountSort = .views
    @State private var selected: Account?
    @State private var showAdd = false
    @State private var pendingDelete: Account?

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
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { account in
                            AccountRow(account: account, maxViews: maxViews)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.haptic(.impact)
                                    selected = account
                                }
                                .contextMenu {
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
                    }
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
            Text("ستُحذف بياناته من نبض فقط، ولن يتأثر حساب TikTok.")
        }
    }

    private var maxViews: Int64 {
        max(store.accounts.map { $0.views }.max() ?? 1, 1)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("الحسابات")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("\(store.accounts.count) حساباً مرتبطاً بنبض")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
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
            stripItem(title: "المنشورات", value: Num.compact(Int64(store.summary.posts)), tint: Theme.cyan)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
            stripItem(title: "المشاهدات", value: Num.compact(store.summary.views), tint: Theme.violet)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24)
            stripItem(title: "المتصل", value: "\(store.connectedCount)/\(store.accounts.count)", tint: Theme.green)
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
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
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
                    message: "الصق روابط حسابات TikTok (حتى ١٠٠ رابط دفعة واحدة) وسنرتّب لك المنشورات والمشاهدات.",
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
                    Text(Num.compact(account.views))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text("مشاهدة")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                statColumn(value: Num.full(Int64(account.posts)), label: "منشور")
                statColumn(value: Num.compact(account.avgViewsPerPost), label: "متوسط")
                statColumn(value: Num.compact(account.followers), label: "متابع")

                Spacer(minLength: 2)

                statusChip
                    .layoutPriority(1)
            }

            ProgressBarLine(
                value: Double(account.views) / Double(max(maxViews, 1)),
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
                .minimumScaleFactor(0.72)
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
        } else if !account.connected {
            Chip(text: "غير مربوط", color: Theme.gold, icon: "link.badge.plus")
        } else if account.status == "error" {
            Chip(text: "خطأ", color: Theme.red)
        } else if account.coverage < 0.95 && account.coverage > 0 {
            Chip(text: "جزئي", color: Theme.violet, icon: "chart.pie.fill")
        }
    }
}
