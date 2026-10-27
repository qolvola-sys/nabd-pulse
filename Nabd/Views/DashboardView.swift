import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    var onOpenSettings: () -> Void = {}
    var onOpenAccounts: () -> Void = {}

    @State private var selectedAccount: Account?
    @State private var wavePhase: CGFloat = 0
    @State private var showAllWeeklyAccounts = false

    private var hasViews: Bool { store.summary.loadedVideos > 0 && store.summary.views > 0 }

    private var hasVideoEngagementData: Bool {
        store.summary.likes + store.summary.comments + store.summary.shares > 0
    }

    private var heroValue: Int64 {
        hasViews ? store.summary.views : store.summary.totalLikes
    }

    private var heroExact: Bool {
        hasViews ? store.summary.viewsExact : store.summary.profileExact
    }

    private var heroScopeLabel: String {
        guard hasViews else { return "إجمالي الإعجابات" }
        return store.summary.allPostsLoaded ? "إجمالي مشاهدات المنشورات" : "مشاهدات المنشورات المحمّلة"
    }

    private var dailyExact: Bool {
        store.summary.dailyComplete && store.summary.dailyViewsExact
    }

    private var weeklyExact: Bool {
        store.summary.weeklyComplete && store.summary.weeklyViewsExact
    }

    private var weeklyFootnote: String {
        if store.summary.weeklyComplete && store.summary.weeklyViewsExact {
            return "كل منشورات آخر ٧ أيام محمّلة، والنتيجة دقيقة 100%."
        }
        if !store.summary.weeklyComplete && !store.summary.weeklyViewsExact {
            return "≈ النتيجة من المنشورات المحمّلة، ومشاهدات TikTok العامة مقرّبة."
        }
        if !store.summary.weeklyComplete {
            return AppVariant.incompleteWeeklyNote
        }
        return "≈ مشاهدات الفيديو العامة يقرّبها TikTok؛ النتيجة تقريبية."
    }

    private var posts24hText: String {
        let value = Int64(store.summary.posts24h)
        return store.summary.dailyComplete ? Num.full(value) : Num.atLeast(value)
    }

    private var views24hText: String {
        Num.maybeApprox(store.summary.views24h, exact: dailyExact)
    }

    private var posts7dText: String {
        let value = Int64(store.summary.posts7d)
        return store.summary.weeklyComplete ? Num.full(value) : Num.atLeast(value)
    }

    private func account24hViewsText(_ account: Account) -> String {
        Num.maybeApprox(account.views24h, exact: account.dailyComplete && account.dailyViewsExact)
    }

    private func account24hPostsText(_ account: Account) -> String {
        account.dailyComplete ? Num.full(Int64(account.posts24h)) : Num.atLeast(Int64(account.posts24h))
    }

    private func accountWeeklyViewsText(_ account: Account) -> String {
        Num.maybeApprox(account.weeklyViews, exact: account.weeklyScoreExact)
    }

    private var topFive: [Account] {
        Array(store.topAccounts.prefix(5))
    }

    private var donutSegments: [DonutSegment] {
        let top = Array(store.topAccounts.prefix(4))
        var segments = top.enumerated().map { index, account in
            DonutSegment(
                label: account.displayName,
                value: hasViews ? account.views : account.likes,
                color: Theme.chartPalette[index % Theme.chartPalette.count]
            )
        }
        let rest = store.topAccounts.dropFirst(4).reduce(Int64(0)) { $0 + (hasViews ? $1.views : $1.likes) }
        if rest > 0 {
            segments.append(DonutSegment(label: "حسابات أخرى", value: rest, color: Theme.textTertiary))
        }
        return segments
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header

                if store.source == .demo {
                    demoBanner
                }

                heroCard
                last24hCard
                weeklyCard
                statsGrid

                if !store.needsReconnect.isEmpty {
                    reconnectCard
                }

                distributionCard
                topAccountsCard
                weeklyTopAccountsCard
                syncSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .refreshable {
            await store.syncAll()
        }
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: true)) {
                wavePhase = -5
            }
        }
        .sheet(item: $selectedAccount) { account in
            AccountDetailView(account: account)
                .environmentObject(store)
        }
    }

    // MARK: - الرأس

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(AppVariant.name)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.text)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.8), radius: 5)
                    Text(store.source.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                #if MUTABAA
                if store.spacesEnabled {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.cyan)
                        Text(store.activeSpaceName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(Theme.textTertiary)
                        Text(Dates.todayArabic())
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textTertiary)
                    }
                } else {
                    Text(Dates.todayArabic())
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                #else
                Text(Dates.todayArabic())
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                #endif
            }

            Spacer()

            Button {
                store.haptic(.impact)
                onOpenSettings()
            } label: {
                ZStack {
                    Circle().fill(Theme.surface)
                    Circle().strokeBorder(Theme.border, lineWidth: 1)
                    Text(AppVariant.mark)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cyan)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var statusColor: Color {
        switch store.source {
        case .live: return Theme.green
        case .direct: return Theme.cyan
        case .demo: return Theme.gold
        case .cache: return Theme.violet
        case .empty: return Theme.red
        }
    }

    // MARK: - تنبيه الوضع التجريبي

    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "flask.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.gold)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.gold.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text("وضع العرض التجريبي")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("الأرقام تمثيلية لـ \(DemoData.brands.count) حساباً. أوقف الوضع التجريبي وأضف روابطك لعرض البيانات الحقيقية.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            Button("إعدادات") { onOpenSettings() }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: 0x061016))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.gold))
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.gold.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - البطاقة الرئيسية

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x171E2C), Color(hex: 0x0E131D)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Theme.cyan.opacity(0.22))
                .frame(width: 150, height: 150)
                .blur(radius: 55)
                .offset(x: -70, y: 95)
            Circle()
                .fill(Theme.pink.opacity(0.18))
                .frame(width: 170, height: 170)
                .blur(radius: 60)
                .offset(x: 210, y: -60)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: hasViews ? "play.rectangle.fill" : "hand.thumbsup.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.cyan)
                        Text(heroScopeLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Text("TikTok")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }

                Text(Num.maybeApprox(heroValue, exact: heroExact))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 12)

                Text(hasViews
                     ? "\(Num.full(Int64(store.summary.loadedVideos))) منشوراً محمّلاً من \(Num.full(Int64(store.summary.posts)))"
                     : "إعجاب ظاهر للعامة")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.top, 2)

                if hasViews && !store.summary.viewsExact {
                    Text("≈ مشاهدات الفيديو العامة يقرّبها TikTok")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Theme.gold.opacity(0.9))
                        .padding(.top, 3)
                }

                PulseWave(phase: wavePhase)
                    .stroke(Theme.brand, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(height: 46)
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 8)
                    .padding(.top, 6)
                    .clipped()

                HStack(spacing: 0) {
                    heroStat(value: posts24hText, caption: "منشور ٢٤ س")
                    divider
                    heroStat(value: views24hText, caption: "مشاهدة ٢٤ س")
                    divider
                    heroStat(value: Num.full(Int64(store.summary.accounts)), caption: "حساب")
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.cyan.opacity(0.28), Theme.borderSoft.opacity(0.4), Theme.pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border.opacity(0.7))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 4)
    }

    private func heroStat(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - آخر ٢٤ ساعة

    private var accounts24h: [Account] {
        store.accounts
            .filter { $0.posts24h > 0 || $0.views24h > 0 }
            .sorted { $0.views24h > $1.views24h }
    }

    /// ترتيب كل حسابات المساحة بمشاهدات آخر ٧ أيام. الحسابات بلا مشاهدات
    /// تبقى في «البقية» حتى لا تختفي من القسم.
    private var weeklyAccounts: [Account] {
        store.accounts.sorted { first, second in
            if first.weeklyViews == second.weeklyViews {
                return first.followers > second.followers
            }
            return first.weeklyViews > second.weeklyViews
        }
    }

    private var weeklyTopFive: [Account] {
        Array(weeklyAccounts.prefix(5))
    }

    private var weeklyRest: [Account] {
        Array(weeklyAccounts.dropFirst(5))
    }

    private var last24hCard: some View {
        VStack(spacing: 13) {
            SectionHeader(
                title: "آخر ٢٤ ساعة",
                subtitle: "مشاهدات المنشورات التي نُشرت خلال آخر ٢٤ ساعة",
                actionTitle: "كل الحسابات",
                action: { onOpenAccounts() }
            )

            HStack(spacing: 10) {
                miniMetric(
                    value: posts24hText,
                    label: "منشور جديد",
                    icon: "square.stack.3d.up.fill",
                    tint: Theme.cyan
                )
                miniMetric(
                    value: views24hText,
                    label: "مشاهدة",
                    icon: "play.fill",
                    tint: Theme.violet
                )
            }

            if store.isLoading && store.accounts.isEmpty {
                Text("جارٍ جلب الأرقام من TikTok…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if accounts24h.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                    Text(store.accounts.isEmpty
                         ? "أضف رابط حساب TikTok لعرض إحصاءات آخر ٢٤ ساعة."
                         : "لا توجد منشورات جديدة خلال آخر ٢٤ ساعة.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(accounts24h.prefix(5).enumerated()), id: \.element.id) { index, account in
                        Button {
                            store.haptic(.impact)
                            selectedAccount = account
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(account: account, size: 32, showVerified: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text("@" + account.handle)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Theme.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(account24hViewsText(account)) مشاهدة")
                                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Text("\(account24hPostsText(account)) منشور")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Theme.textTertiary)
                                }
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))

                        if index < min(accounts24h.count, 5) - 1 {
                            HairlineDivider().opacity(0.5)
                        }
                    }
                }
            }
            if !store.summary.dailyComplete || !store.summary.dailyViewsExact {
                Text(store.summary.dailyComplete
                     ? "≈ مشاهدات الفيديو العامة يقرّبها TikTok."
                     : "الحسابات التي نشرت أكثر من ١٠ منشورات في ٢٤ ساعة تظهر من أحدث ١٠ فقط.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .card(padding: 16)
    }

    private func miniMetric(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
    }

    // MARK: - التقييم الأسبوعي

    private var weeklyCard: some View {
        VStack(spacing: 14) {
            SectionHeader(
                title: "التقييم الأسبوعي",
                subtitle: AppVariant.weekdaySubtitle,
                actionTitle: "كل الحسابات",
                action: { onOpenAccounts() }
            )

            HStack(alignment: .center, spacing: 16) {
                WeeklyScoreRing(score: store.summary.weeklyScore, exact: weeklyExact)

                VStack(alignment: .leading, spacing: 10) {
                    weeklyMetric(
                        icon: "play.fill",
                        tint: Theme.violet,
                        value: Num.maybeApprox(store.summary.weeklyViews, exact: weeklyExact),
                        label: "مشاهدة لمنشورات ٧ أيام"
                    )
                    weeklyMetric(
                        icon: "square.stack.3d.up.fill",
                        tint: Theme.cyan,
                        value: posts7dText,
                        label: "منشور في ٧ أيام"
                    )
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text(WeeklyScore.label(for: store.summary.weeklyScore))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(WeeklyScoreStyle.color(for: store.summary.weeklyScore))
                }

                Spacer(minLength: 0)
            }

            Text(weeklyFootnote)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 2)
        }
        .card(padding: 18)
    }

    private func weeklyMetric(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 23, height: 23)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    // MARK: - شبكة الإحصاءات

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(
                title: "المنشورات",
                value: Num.full(Int64(store.summary.posts)),
                icon: "square.stack.3d.up.fill",
                tint: Theme.cyan,
                hint: "على \(store.summary.accounts) حساباً"
            )
            StatCard(
                title: hasViews ? "متوسط المشاهدات" : "متوسط الإعجابات",
                value: hasViews
                    ? Num.maybeApprox(store.summary.avgViews, exact: store.summary.viewsExact)
                    : Num.maybeApprox(averageLikesPerPost, exact: store.summary.profileExact),
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.violet,
                hint: hasViews
                    ? (store.summary.allPostsLoaded ? "لكل منشور" : "للمنشورات المحمّلة")
                    : "لكل منشور"
            )
            StatCard(
                title: "المتابعون",
                value: Num.maybeApprox(store.totalFollowers, exact: store.summary.profileExact),
                icon: "person.3.fill",
                tint: Theme.pink,
                hint: "مجموع الحسابات"
            )
            if hasVideoEngagementData {
                StatCard(
                    title: "معدل التفاعل",
                    value: Num.percent(engagementRate),
                    icon: "hand.thumbsup.fill",
                    tint: Theme.gold,
                    hint: "للمنشورات المحمّلة"
                )
            } else {
                StatCard(
                    title: "إجمالي الإعجابات",
                    value: Num.maybeApprox(store.summary.totalLikes, exact: store.summary.profileExact),
                    icon: "hand.thumbsup.fill",
                    tint: Theme.gold,
                    hint: store.summary.profileExact ? "رقم عام دقيق" : "رقم عام مقرّب"
                )
            }
        }
    }

    private var averageLikesPerPost: Int64 {
        store.summary.posts > 0 ? store.summary.totalLikes / Int64(store.summary.posts) : 0
    }

    private var engagementRate: Double {
        guard store.summary.views > 0 else { return 0 }
        let interactions = store.summary.likes + store.summary.comments + store.summary.shares
        return Double(interactions) / Double(store.summary.views)
    }

    // MARK: - إعادة الربط

    private var reconnectCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.needsReconnect.count) حساباً يحتاج إعادة ربط")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("اضغط الحساب من قائمة الحسابات ثم «ربط الحساب».")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button("عرض") { onOpenAccounts() }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.red)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.red.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.red.opacity(0.2), lineWidth: 1))
    }

    // MARK: - التوزيع

    private var distributionCard: some View {
        VStack(spacing: 16) {
            SectionHeader(
                title: hasViews
                    ? (store.summary.allPostsLoaded ? "توزيع المشاهدات" : "توزيع مشاهدات المنشورات المحمّلة")
                    : "توزيع الإعجابات",
                subtitle: hasViews && !store.summary.allPostsLoaded
                    ? "من المنشورات المحمّلة — أكبر ٤ حسابات + الباقي"
                    : "أكبر ٤ حسابات + الباقي"
            )

            HStack(alignment: .center, spacing: 18) {
                DonutChart(
                    segments: donutSegments,
                    centerValue: hasViews
                        ? Num.maybeApprox(store.summary.views, exact: store.summary.viewsExact)
                        : Num.maybeApprox(store.summary.totalLikes, exact: store.summary.profileExact),
                    centerCaption: hasViews ? "مشاهدة" : "إعجاب"
                )

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(donutSegments) { segment in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 7, height: 7)
                            Text(segment.label)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(shareText(segment.value))
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.text)
                        }
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private func shareText(_ value: Int64) -> String {
        let total = max(hasViews ? store.summary.views : store.summary.totalLikes, 1)
        return Num.percent(Double(value) / Double(total))
    }

    // MARK: - الأعلى مشاهدة

    private var topAccountsCard: some View {
        VStack(spacing: 14) {
            SectionHeader(
                title: hasViews ? "الأعلى مشاهدة" : "الأعلى إعجاباً",
                subtitle: hasViews && !store.summary.allPostsLoaded
                    ? "حسب المنشورات المحمّلة"
                    : "أفضل الحسابات أداءً",
                actionTitle: "كل الحسابات",
                action: { onOpenAccounts() }
            )

            if store.isLoading && store.accounts.isEmpty {
                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 11) {
                            SkeletonBlock(height: 38, width: 38, radius: 12)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(height: 10, width: 110)
                                SkeletonBlock(height: 8, width: 70)
                            }
                            Spacer()
                            SkeletonBlock(height: 12, width: 50)
                        }
                    }
                }
            } else if topFive.isEmpty {
                EmptyStateView(
                    icon: "person.badge.plus",
                    title: "لا توجد حسابات بعد",
                    message: "أضف روابط حساباتك من تبويب الحسابات لتبدأ.",
                    actionTitle: "إضافة حسابات",
                    action: { onOpenAccounts() }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topFive.enumerated()), id: \.element.id) { index, account in
                        Button {
                            store.haptic(.impact)
                            selectedAccount = account
                        } label: {
                            HStack(spacing: 11) {
                                RankBadge(index: index)
                                AvatarView(account: account, size: 38, showVerified: false)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Text(account.displayName)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        if account.isVerified {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(Theme.cyan)
                                        }
                                    }
                                    ProgressBarLine(
                                        value: Double(hasViews ? account.views : account.likes) / Double(max((hasViews ? topFive.first?.views : topFive.first?.likes) ?? 1, 1)),
                                        height: 4
                                    )
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(hasViews
                                         ? Num.maybeApprox(account.views, exact: account.viewsExact)
                                         : Num.maybeApprox(account.likes, exact: account.profileExact))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("\(Num.full(Int64(account.posts))) منشور")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Theme.textTertiary)
                                }
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))

                        if index < topFive.count - 1 {
                            HairlineDivider().opacity(0.6)
                        }
                    }
                }
            }
        }
        .card(padding: 18)
    }

    // MARK: - الأعلى مشاهدة هذا الأسبوع

    private var weeklyTopAccountsCard: some View {
        VStack(spacing: 14) {
            SectionHeader(
                title: "أكثر الحسابات مشاهدة في آخر أسبوع",
                subtitle: "أقوى ٥ حسابات بمشاهدات منشورات آخر ٧ أيام، ثم بقية الحسابات",
                actionTitle: "كل الحسابات",
                action: { onOpenAccounts() }
            )

            if store.isLoading && store.accounts.isEmpty {
                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 11) {
                            SkeletonBlock(height: 24, width: 24, radius: 12)
                            SkeletonBlock(height: 36, width: 36, radius: 12)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(height: 10, width: 120)
                                SkeletonBlock(height: 8, width: 80)
                            }
                            Spacer()
                            SkeletonBlock(height: 12, width: 52)
                        }
                    }
                }
            } else if weeklyAccounts.isEmpty {
                EmptyStateView(
                    icon: "person.badge.plus",
                    title: "لا توجد حسابات بعد",
                    message: "أضف حساباتك من تبويب الحسابات لعرض ترتيب مشاهدات آخر أسبوع.",
                    actionTitle: "إضافة حسابات",
                    action: { onOpenAccounts() }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(weeklyTopFive.enumerated()), id: \.element.id) { index, account in
                        weeklyAccountRow(account, rank: index)
                        if index < weeklyTopFive.count - 1 || (showAllWeeklyAccounts && !weeklyRest.isEmpty) {
                            HairlineDivider().opacity(0.55)
                        }
                    }

                    if !weeklyRest.isEmpty {
                        if showAllWeeklyAccounts {
                            ForEach(Array(weeklyRest.enumerated()), id: \.element.id) { offset, account in
                                weeklyAccountRow(account, rank: offset + 5)
                                if offset < weeklyRest.count - 1 {
                                    HairlineDivider().opacity(0.55)
                                }
                            }

                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showAllWeeklyAccounts = false
                                }
                                store.haptic(.selection)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("إخفاء بقية الحسابات")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Spacer(minLength: 0)
                                }
                                .foregroundColor(Theme.textTertiary)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showAllWeeklyAccounts = true
                                }
                                store.haptic(.selection)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("عرض بقية الحسابات")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(Num.full(Int64(weeklyRest.count)))
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.surfaceRaised))
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(Theme.cyan)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.violet)
                Text("المشاهدات هي مجموع مشاهدات المنشورات المنشورة خلال آخر ٧ أيام. الأرقام التي تظهر بدون ≈ دقيقة 100%، والحسابات التي لم تُقرأ كل منشوراتها تظهر بعلامة تقريب.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: 18)
    }

    private func weeklyAccountRow(_ account: Account, rank: Int) -> some View {
        Button {
            store.haptic(.impact)
            selectedAccount = account
        } label: {
            HStack(spacing: 10) {
                RankBadge(index: rank)
                AvatarView(account: account, size: 35, showVerified: false)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(account.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        if account.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(Theme.cyan)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(account.weeklyViews > 0
                             ? "\(accountWeeklyViewsText(account)) مشاهدة"
                             : "لا مشاهدات هذا الأسبوع")
                        if account.weeklyViews > 0 {
                            Text("·")
                            Text("\(Num.full(Int64(account.posts7d))) منشور")
                        }
                    }
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    if account.weeklyViews > 0 {
                        ProgressBarLine(
                            value: Double(account.weeklyViews) / Double(max(weeklyAccounts.first?.weeklyViews ?? 1, 1)),
                            gradient: Theme.violetGradient,
                            height: 3
                        )
                    }
                }

                Spacer(minLength: 6)

                if account.weeklyViews > 0 {
                    WeeklyScoreBadge(score: account.weeklyScore, compact: true, exact: account.weeklyScoreExact)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    // MARK: - المزامنة

    private var syncSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.syncAll() }
            } label: {
                HStack(spacing: 9) {
                    if store.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: 0x061016)))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(store.isSyncing ? "جارٍ المزامنة…" : "مزامنة الكل")
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(store.isSyncing)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9.5))
                Text("آخر تحديث: \(Dates.relative(store.summary.lastSyncedAt))")
                    .font(.system(size: 10.5))
            }
            .foregroundColor(Theme.textTertiary)

            if store.summary.accounts > 0 {
                Text(AppVariant.readsEveryWeeklyPost
                     ? "التقييم الأسبوعي في «المتابعة» يُحسب من كل منشورات آخر ٧ أيام لكل حساب. الأرقام التي تظهر بدون ≈ دقيقة 100%: كل ١٠٬٠٠٠ مشاهدة = نقطة، و١٬٠٠٠٬٠٠٠ = 100%."
                     : "بيانات TikTok التي تظهر بدون ≈ دقيقة 100%. مشاهدات الفيديو العامة يقرّبها TikTok وتظهر بعلامة ≈. التقييم من 100: كل ١٠٬٠٠٠ مشاهدة = نقطة، و١٬٠٠٠٬٠٠٠ = 100%.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 2)
    }
}
