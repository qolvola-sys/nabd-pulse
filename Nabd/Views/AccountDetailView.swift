import SwiftUI
import UIKit

struct AccountDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var detail: Account?
    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var isSyncing = false

    private var current: Account { detail ?? account }

    private var palette: Color {
        Theme.chartPalette[current.paletteIndex % Theme.chartPalette.count]
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeader
                    if !current.connected {
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
        .confirmationDialog("إزالة @\(current.handle)؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("إزالة من نبض", role: .destructive) {
                Task {
                    await store.delete(current)
                    dismiss()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لن يتأثر حساب TikTok نفسه.")
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
                } label: { Label("فتح في TikTok", systemImage: "arrow.up.right.square") }
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
                Text("@" + current.handle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: 7) {
                Chip(text: "TikTok", color: Theme.pink, icon: "play.rectangle.fill")
                Chip(
                    text: current.statusLabel,
                    color: current.connected ? (current.isHealthy ? Theme.green : Theme.gold) : Theme.gold,
                    icon: current.connected ? "checkmark.circle.fill" : "link.badge.plus"
                )
                if current.isVerified {
                    Chip(text: "موثّق", color: Theme.cyan, icon: "checkmark.seal.fill")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.cyan)
                Text("اربط الحساب لعرض إحصاءاته")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
            }
            Text("يُطلب منك تسجيل الدخول إلى TikTok مرة واحدة. تُحفظ الصلاحية على خادمك الخاص ويمكنك فصلها في أي وقت.")
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
                    Text(store.connectingAccountID == current.id ? "جارٍ الربط…" : "ربط الحساب")
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
            StatCard(title: "المنشورات", value: Num.compact(Int64(current.posts)), icon: "square.stack.3d.up.fill", tint: Theme.cyan)
            StatCard(title: "المشاهدات", value: Num.compact(current.views), icon: "play.fill", tint: Theme.violet)
            StatCard(title: "متوسط المشاهدات", value: Num.compact(current.avgViewsPerPost), icon: "chart.bar.fill", tint: Theme.pink)
            StatCard(title: "المتابعون", value: Num.compact(current.followers), icon: "person.3.fill", tint: Theme.gold)
        }
    }

    private var engagementRow: some View {
        HStack(spacing: 0) {
            engagementItem(icon: "heart.fill", value: current.videoLikes, label: "إعجاب", tint: Theme.pink)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            engagementItem(icon: "bubble.right.fill", value: current.comments, label: "تعليق", tint: Theme.cyan)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            engagementItem(icon: "arrowshape.turn.up.right.fill", value: current.shares, label: "مشاركة", tint: Theme.violet)
            Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 26)
            engagementItem(icon: "person.2.fill", value: current.followers, label: "متابع", tint: Theme.gold)
        }
        .padding(.vertical, 12)
        .card(padding: 0, radius: 18)
    }

    private func engagementItem(icon: String, value: Int64, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(tint)
            Text(Num.compact(value))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("تغطية التحليل")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(Num.full(Int64(current.fetchedVideos))) من \(Num.full(Int64(current.posts))) منشوراً")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            ProgressBarLine(value: min(current.coverage, 1), gradient: Theme.violetGradient, height: 6)
            Text("آخر مزامنة: \(Dates.relative(current.lastSyncedAt))")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
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
            } else if let error {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "تعذّر تحميل المنشورات",
                    message: error,
                    actionTitle: "إعادة المحاولة",
                    action: { Task { await load() } }
                )
                .card(padding: 4)
            } else if videos.isEmpty {
                EmptyStateView(
                    icon: "video.slash",
                    title: "لا توجد منشورات",
                    message: current.connected ? "لم يُرجع TikTok أي منشور عام لهذا الحساب." : "اربط الحساب لجلب المنشورات."
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
        error = nil
        do {
            let result = try await store.detail(for: current)
            detail = result.0
            videos = result.1
        } catch {
            self.error = error.localizedDescription
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
                    Label(Num.compact(video.views), systemImage: "play.fill")
                    Label(Num.compact(video.likes), systemImage: "heart.fill")
                    Text(Dates.videoDate(video.createTime))
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textTertiary)
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
