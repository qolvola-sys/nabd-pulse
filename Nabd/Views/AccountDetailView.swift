import SwiftUI
import UIKit

struct AccountDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var detail: Account?
    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
    @State private var confirmDelete = false
    @State private var isSyncing = false

    private var current: Account { detail ?? account }

    private var handleText: String {
        current.isFacebook ? current.handle : "@" + current.handle
    }

    private var dailyExact: Bool {
        current.dailyComplete && current.dailyViewsExact
    }

    private var weeklyExact: Bool {
        current.weeklyComplete && current.weeklyViewsExact
    }

    private var views24hText: String {
        Num.maybeApprox(current.views24h, exact: dailyExact)
    }

    private var posts24hText: String {
        current.dailyComplete ? Num.full(Int64(current.posts24h)) : Num.atLeast(Int64(current.posts24h))
    }

    private var weeklyViewsText: String {
        Num.maybeApprox(current.weeklyViews, exact: weeklyExact)
    }

    private var posts7dText: String {
        current.weeklyComplete ? Num.full(Int64(current.posts7d)) : Num.atLeast(Int64(current.posts7d))
    }

    private var weeklyFootnote: String {
        if current.isFacebook {
            if current.weeklyComplete && current.weeklyViewsExact {
                return "كل منشورات آخر ٧ أيام المتاحة علناً محمّلة، ومشاهدات الفيديو دقيقة 100%."
            }
            if !current.weeklyComplete {
                return "≈ تُعرض أحدث ٢٠ منشوراً علنياً؛ قد تكون هناك منشورات أقدم لم يعرضها فيسبوك للزائر."
            }
            return "≈ مشاهدات فيسبوك متاحة للفيديو فقط؛ المنشورات النصية والصور لا تكشف مشاهدات عامة."
        }
        if current.weeklyComplete && current.weeklyViewsExact {
            return "كل منشورات آخر ٧ أيام محمّلة، والنتيجة دقيقة 100% (١٬٠٠٠٬٠٠٠ مشاهدة = 100%)."
        }
        if !current.weeklyComplete && !current.weeklyViewsExact {
            return AppVariant.readsEveryWeeklyPost
                ? "≈ بعض منشورات آخر ٧ أيام لم تُقرأ بعد، ومشاهدات TikTok العامة مقرّبة."
                : "≈ النتيجة من أحدث ١٠ منشورات فقط، ومشاهدات TikTok العامة مقرّبة."
        }
        if !current.weeklyComplete {
            return AppVariant.incompleteWeeklyNote
        }
        return "≈ مشاهدات الفيديو العامة يقرّبها TikTok؛ النتيجة تقريبية."
    }

    private var palette: Color {
        Theme.chartPalette[current.paletteIndex % Theme.chartPalette.count]
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeader
                    last24hCard
                    weeklyCard
                    if !current.connected && !current.publicStats {
                        connectCard
                    }
                    statsGrid
                    engagementRow
                    coverageCard
                    videosSection
                    colorSpacer
                }
                .padding(.horizontal, 18)
                .padding(.top, 58)
                .padding(.bottom, 120)
            }
            .refreshable { await load(forceSync: true) }

            closeButton
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task { await load() }
        .confirmationDialog("إزالة \(handleText)؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("إزالة من \(AppVariant.name)", role: .destructive) {
                Task {
                    await store.delete(current)
                    dismiss()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لن يتأثر \(current.isFacebook ? "حساب فيسبوك" : "حساب TikTok") نفسه.")
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    private var closeButton: some View {
        HStack {
            Button {
                store.haptic(.selection)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            Spacer()

            Menu {
                Button {
                    UIPasteboard.general.string = current.url
                    store.showToast("تم نسخ الرابط", .success)
                } label: { Label("نسخ الرابط", systemImage: "link") }
                Button {
                    if let url = URL(string: current.url) { UIApplication.shared.open(url) }
                } label: { Label("فتح في \(current.platform.title)", systemImage: "arrow.up.right.square") }
                Button {
                    Task { await load(forceSync: true) }
                } label: { Label("مزامنة الآن", systemImage: "arrow.triangle.2.circlepath") }
                if current.connected {
                    Button {
                        Task { await store.disconnect(current) }
                    } label: { Label("فصل الحساب", systemImage: "link.badge.minus") }
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: { Label("إزالة الحساب", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: - الترويسة

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.opacity(0.18))
                    .frame(width: 104, height: 104)
                    .blur(radius: 22)
                AvatarView(account: current, size: 76)
            }

            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text(current.displayName)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                    if current.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.cyan)
                    }
                }
                Text(handleText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: 7) {
                Chip(
                    text: current.platform.title,
                    color: current.isFacebook ? Theme.cyan : Theme.pink,
                    icon: current.platform.icon
                )
                Chip(
                    text: current.statusLabel,
                    color: current.publicStats ? Theme.cyan : (current.connected ? (current.isHealthy ? Theme.green : Theme.gold) : Theme.gold),
                    icon: current.publicStats ? "globe" : (current.connected ? "checkmark.circle.fill" : "link.badge.plus")
                )
                if current.isVerified {
                    Chip(text: "موثّق", color: Theme.cyan, icon: "checkmark.seal.fill")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - آخر ٢٤ ساعة

    private var last24hCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.cyan)
                Text("إحصاءات آخر ٢٤ ساعة")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("الآن")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.cyan.opacity(0.12)))
            }

            HStack(spacing: 0) {
                detailMetric(
                    value: posts24hText,
                    label: "منشور جديد",
                    icon: "square.stack.3d.up.fill",
                    tint: Theme.cyan
                )
                Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 34)
                detailMetric(
                    value: views24hText,
                    label: "مشاهدة",
                    icon: "play.fill",
                    tint: Theme.violet
                )
            }

            Text(current.dailyComplete && current.dailyViewsExact
                 ? "كل منشورات آخر ٢٤ ساعة المتاحة محمّلة، والمشاهدات دقيقة 100%."
                 : (current.isFacebook
                    ? "≈ مشاهدات فيسبوك متاحة للفيديو فقط، وتُعرض أحدث ٢٠ منشوراً علنياً."
                    : (current.dailyComplete
                       ? "≈ مشاهدات الفيديو العامة يقرّبها TikTok."
                       : (AppVariant.readsEveryWeeklyPost
                          ? "بعض منشورات آخر ٢٤ ساعة لم تُقرأ بعد؛ تُعرض المنشورات المحمّلة."
                          : "الحساب نشر أكثر من ١٠ منشورات في ٢٤ ساعة؛ تُعرض أحدث ١٠ فقط."))))
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 15)
    }

    private func detailMetric(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - التقييم الأسبوعي

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.violet)
                Text("التقييم الأسبوعي")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                WeeklyScoreBadge(score: current.weeklyScore, exact: weeklyExact)
            }

            HStack(alignment: .center, spacing: 16) {
                WeeklyScoreRing(score: current.weeklyScore, size: 84, lineWidth: 7, exact: weeklyExact)

                VStack(alignment: .leading, spacing: 9) {
                    weeklyStat(
                        icon: "play.fill",
                        tint: Theme.violet,
                        value: weeklyViewsText,
                        label: "مشاهدة لمنشورات ٧ أيام"
                    )
                    weeklyStat(
                        icon: "square.stack.3d.up.fill",
                        tint: Theme.cyan,
                        value: posts7dText,
                        label: "منشور في ٧ أيام"
                    )
                    Text(WeeklyScore.label(for: current.weeklyScore))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(WeeklyScoreStyle.color(for: current.weeklyScore))
                }

                Spacer(minLength: 0)
            }

            Text(weeklyFootnote)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 15)
    }

    private func weeklyStat(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.cyan)
                Text("اربط الحساب لعرض المشاهدات")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            Text("البيانات العامة محدّثة الآن (منشورات، متابعون، إعجابات). مشاهدات الفيديو تحتاج تسجيل دخول مرة واحدة لحسابك على TikTok، وتُحفظ الصلاحية على خادمك الخاص ويمكن فصلها في أي وقت.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(4)

            Button {
                Task { await store.connect(current) }
            } label: {
                HStack(spacing: 7) {
                    if store.connectingAccountID == current.id {
                        ProgressView().tint(Color(hex: 0x061016)).scaleEffect(0.8)
                    } else {
                        Image(systemName: "link").font(.system(size: 13, weight: .bold))
                    }
                    Text(store.connectingAccountID == current.id ? "جارٍ الربط…" : "ربط الحساب لعرض المشاهدات")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 46))
            .disabled(store.isDemo)

            if store.isDemo {
                Text("أوقف الوضع التجريبي واتصل بالخادم أولاً.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.gold)
            }
        }
        .card(padding: 16)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(title: "المنشورات", value: Num.maybeApprox(Int64(current.posts), exact: current.postsCountExact), icon: "square.stack.3d.up.fill", tint: Theme.cyan)
            StatCard(
                title: "المشاهدات",
                value: current.hasViewData ? Num.maybeApprox(current.views, exact: current.viewsExact) : "—",
                icon: "play.fill",
                tint: Theme.violet,
                hint: current.hasViewData
                    ? (current.allPostsLoaded ? "كل المنشورات" : "من المنشورات المحمّلة")
                    : "لا توجد بيانات عامة"
            )
            StatCard(
                title: current.hasViewData ? "متوسط المشاهدات" : "متوسط الإعجابات",
                value: current.hasViewData
                    ? Num.maybeApprox(current.avgViewsPerPost, exact: current.viewsExact)
                    : Num.maybeApprox(current.avgLikesPerPost, exact: current.profileExact),
                icon: "chart.bar.fill",
                tint: Theme.pink,
                hint: current.hasViewData && !current.allPostsLoaded ? "للمنشورات المحمّلة" : nil
            )
            StatCard(title: "المتابعون", value: Num.maybeApprox(current.followers, exact: current.profileExact), icon: "person.3.fill", tint: Theme.gold)
        }
    }

    private var engagementRow: some View {
        HStack(spacing: 0) {
            engagementItem(
                icon: "heart.fill",
                value: current.hasVideoEngagementData ? current.videoLikes : current.likes,
                label: current.hasVideoEngagementData ? "إعجاب" : "إجمالي الإعجابات",
                tint: Theme.pink,
                exact: current.hasVideoEngagementData || current.profileExact
            )
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            if current.hasVideoEngagementData {
                engagementItem(icon: "bubble.right.fill", value: current.comments, label: "تعليق", tint: Theme.cyan)
                Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
                engagementItem(icon: "arrowshape.turn.up.right.fill", value: current.shares, label: "مشاركة", tint: Theme.violet)
                Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            } else {
                engagementItem(icon: "square.stack.3d.up.fill", value: Int64(current.posts), label: "منشور", tint: Theme.cyan, exact: current.postsCountExact)
                Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            }
            engagementItem(icon: "person.2.fill", value: current.followers, label: "متابع", tint: Theme.gold, exact: current.profileExact)
        }
        .padding(.vertical, 12)
        .card(padding: 0, radius: 18)
    }

    private func engagementItem(icon: String, value: Int64, label: String, tint: Color, exact: Bool = true) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(tint)
            Text(Num.maybeApprox(value, exact: exact))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private var coverageCard: some View {
        Group {
            if current.hasViewData {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("تغطية التحليل")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text(current.isFacebook
                             ? "آخر \(Num.full(Int64(current.fetchedVideos))) منشوراً متاحاً علناً"
                             : "\(Num.full(Int64(current.fetchedVideos))) من \(Num.maybeApprox(Int64(current.posts), exact: current.postsCountExact)) منشوراً")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                    }
                    ProgressBarLine(value: min(current.coverage, 1), gradient: Theme.violetGradient, height: 6)
                    Text(current.allPostsLoaded
                         ? "كل منشورات الحساب المتاحة محمّلة."
                         : "المعروض أحدث \(Num.full(Int64(current.fetchedVideos))) منشوراً متاحاً علناً.")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                    Text(current.isFacebook
                         ? (current.viewsExact
                            ? "مشاهدات الفيديو المحمّلة دقيقة 100%."
                            : "≈ مشاهدات فيسبوك متاحة للفيديو فقط — المنشورات النصية والصور بلا مشاهدات معروضة.")
                         : (current.viewsExact
                            ? "مشاهدات المنشورات المحمّلة دقيقة 100%."
                            : "مشاهدات الفيديو العامة يقرّبها TikTok — تظهر بعلامة ≈."))
                        .font(.system(size: 10))
                        .foregroundColor(current.viewsExact ? Theme.green.opacity(0.9) : Theme.gold.opacity(0.9))
                    Text("آخر مزامنة: \(Dates.relative(current.lastSyncedAt))")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("لا توجد مشاهدات عامة متاحة")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text("قد يكون الحساب بلا منشورات عامة، أو أن الأرقام ستُحدَّث في المزامنة القادمة. عدد المنشورات والمتابعون محدّثون من البيانات العامة.")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.textSecondary)
                            .lineSpacing(3)
                        Text("آخر تحديث: \(Dates.relative(current.lastSyncedAt))")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .card(padding: 15)
    }

    // MARK: - الفيديوهات

    private var videosSection: some View {
        VStack(spacing: 12) {
            SectionHeader(
                title: "أحدث المنشورات",
                subtitle: "أعلى المنشورات مشاهدةً ضمن آخر سحب",
                actionTitle: nil,
                action: nil
            )

            if isLoading {
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 11) {
                            SkeletonBlock(height: 68, width: 50, radius: 10)
                            VStack(alignment: .leading, spacing: 7) {
                                SkeletonBlock(height: 10, width: 180)
                                SkeletonBlock(height: 8, width: 120)
                            }
                            Spacer()
                        }
                    }
                }
            } else if videos.isEmpty {
                EmptyStateView(
                    icon: "video.badge.clock",
                    title: "لا توجد منشورات محفوظة بعد",
                    message: "اضغط تحديث لجلب أحدث المنشورات من \(current.platform.title). تبقى الإحصاءات السابقة محفوظة إذا كان \(current.platform.title) مشغولاً.",
                    actionTitle: "تحديث الآن",
                    action: { Task { await load(forceSync: true) } }
                )
                .card(padding: 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        VideoRow(video: video, index: index)
                            .onTapGesture {
                                guard let raw = video.shareUrl, let url = URL(string: raw) else { return }
                                UIApplication.shared.open(url)
                            }
                    }
                }
            }
        }
    }

    private var colorSpacer: some View {
        Color.clear.frame(height: 1)
    }

    // MARK: - الشريط السفلي

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                if let url = URL(string: current.url) { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            .buttonStyle(GhostButtonStyle(height: 50))
            .frame(width: 56)

            Button {
                Task { await load(forceSync: true) }
            } label: {
                HStack(spacing: 7) {
                    if isLoading || isSyncing {
                        ProgressView().tint(Color(hex: 0x061016)).scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("تحديث الإحصاءات")
                }
            }
            .buttonStyle(GradientButtonStyle(height: 50))
            .disabled(isLoading || isSyncing || store.isDemo)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.bg.opacity(0), location: 0),
                    .init(color: Theme.bg.opacity(0.9), location: 0.3),
                    .init(color: Theme.bg, location: 0.6),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - التحميل

    private func load(forceSync: Bool = false) async {
        if forceSync, !store.isDemo {
            isSyncing = true
            await store.sync(current)
            isSyncing = false
        }
        isLoading = videos.isEmpty
        do {
            let result = try await store.detail(for: current)
            detail = result.0
            videos = result.1
        } catch {
            // نحتفظ بالمنشورات والإحصاءات المحفوظة بدل عرض رسالة خطأ.
        }
        isLoading = false
    }
}

// MARK: - صف الفيديو

struct VideoRow: View {
    let video: VideoItem
    let index: Int

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.chartPalette[index % Theme.chartPalette.count].opacity(0.35), Theme.surfaceRaised],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let raw = video.coverUrl, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
                if video.duration > 0 {
                    Text(Num.minutes(video.duration))
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(width: 52, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(video.title.isEmpty ? "منشور بدون وصف" : video.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Label(Num.maybeApprox(video.views, exact: video.viewsExact), systemImage: "play.fill")
                    if video.likes > 0 {
                        Label(Num.full(video.likes), systemImage: "heart.fill")
                    }
                    Text(Dates.videoDate(video.createTime))
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
    }
}
