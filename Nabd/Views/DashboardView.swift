import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    var onOpenSettings: () -> Void = {}
    var onOpenAccounts: () -> Void = {}

    @State private var selectedAccount: Account?
    @State private var wavePhase: CGFloat = 0

    private var topFive: [Account] {
        Array(store.topAccounts.prefix(5))
    }

    private var donutSegments: [DonutSegment] {
        let top = Array(store.topAccounts.prefix(4))
        var segments = top.enumerated().map { index, account in
            DonutSegment(
                label: account.displayName,
                value: account.views,
                color: Theme.chartPalette[index % Theme.chartPalette.count]
            )
        }
        let rest = store.topAccounts.dropFirst(4).reduce(Int64(0)) { $0 + $1.views }
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
                statsGrid

                if !store.needsReconnect.isEmpty {
                    reconnectCard
                }

                distributionCard
                topAccountsCard
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
                    Text("نبض")
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
                Text(Dates.todayArabic())
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button {
                store.haptic(.impact)
                onOpenSettings()
            } label: {
                ZStack {
                    Circle().fill(Theme.surface)
                    Circle().strokeBorder(Theme.border, lineWidth: 1)
                    Text("ن")
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
                Text("الأرقام تمثيلية لـ \(DemoData.brands.count) حساباً. اربط الخادم لعرض بياناتك الحقيقية.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            Button("ربط") { onOpenSettings() }
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
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.cyan)
                        Text("إجمالي المشاهدات")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Text("TikTok")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }

                Text(Num.compact(store.summary.views))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 12)

                Text(Num.full(store.summary.views) + " مشاهدة")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.top, 2)

                PulseWave(phase: wavePhase)
                    .stroke(Theme.brand, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(height: 46)
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 8)
                    .padding(.top, 6)
                    .clipped()

                HStack(spacing: 0) {
                    heroStat(value: Num.compact(Int64(store.summary.posts)), caption: "منشور")
                    divider
                    heroStat(value: Num.compact(Int64(store.summary.accounts)), caption: "حساب")
                    divider
                    heroStat(value: Num.compact(store.totalFollowers), caption: "متابع")
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
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - شبكة الإحصاءات

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(
                title: "المنشورات",
                value: Num.compact(Int64(store.summary.posts)),
                icon: "square.stack.3d.up.fill",
                tint: Theme.cyan,
                hint: "على \(store.summary.accounts) حساباً"
            )
            StatCard(
                title: "متوسط المشاهدات",
                value: Num.compact(store.summary.avgViews),
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.violet,
                hint: "لكل منشور"
            )
            StatCard(
                title: "المتابعون",
                value: Num.compact(store.totalFollowers),
                icon: "person.3.fill",
                tint: Theme.pink,
                hint: "مجموع الحسابات"
            )
            StatCard(
                title: "معدل التفاعل",
                value: Num.percent(engagementRate),
                icon: "hand.thumbsup.fill",
                tint: Theme.gold,
                hint: "إعجاب وتعليق ومشاركة"
            )
        }
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
            SectionHeader(title: "توزيع المشاهدات", subtitle: "أكبر ٤ حسابات + الباقي")

            HStack(alignment: .center, spacing: 18) {
                DonutChart(
                    segments: donutSegments,
                    centerValue: Num.compact(store.summary.views),
                    centerCaption: "مشاهدة"
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
        let total = max(store.summary.views, 1)
        return Num.percent(Double(value) / Double(total))
    }

    // MARK: - الأعلى مشاهدة

    private var topAccountsCard: some View {
        VStack(spacing: 14) {
            SectionHeader(
                title: "الأعلى مشاهدة",
                subtitle: "أفضل الحسابات أداءً",
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
                                        value: Double(account.views) / Double(max(topFive.first?.views ?? 1, 1)),
                                        height: 4
                                    )
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Num.compact(account.views))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.text)
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
                Text("المشاهدات المحسوبة من المنشورات المتاحة عبر TikTok API، وقد تقل عن إجمالي الحساب إذا تجاوزت المنشورات حد السحب.")
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
