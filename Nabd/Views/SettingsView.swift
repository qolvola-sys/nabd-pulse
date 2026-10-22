import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var url: String = ""
    @State private var token: String = ""
    @State private var isTesting = false
    @State private var report: ConnectionReport?
    @State private var shareFile: ShareFile?
    @State private var didLoad = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                connectionCard
                if let report { reportBanner(report) }
                modeCard
                syncCard
                dataCard
                aboutCard
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            url = store.serverURL
            token = store.apiToken
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
    }

    // MARK: - الرأس

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("الإعدادات")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.text)
            Text("اربط خادمك وتحكّم في طريقة المزامنة")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - الاتصال

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("الخادم", systemImage: "server.rack")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Chip(
                    text: store.demoMode ? "تجريبي" : (store.hasServer ? "مضبوط" : "غير مضبوط"),
                    color: store.demoMode ? Theme.gold : (store.hasServer ? Theme.green : Theme.red)
                )
            }

            fieldLabel("عنوان الخادم")
            inputField("https://api.example.com", text: $url, keyboard: .URL)

            fieldLabel("مفتاح الوصول API_TOKEN")
            inputField("••••••••", text: $token, isSecure: true)

            HStack(spacing: 9) {
                Button {
                    Task { await test() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().tint(Theme.text).scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.horizontal").font(.system(size: 12, weight: .bold))
                        }
                        Text("اختبار")
                    }
                }
                .buttonStyle(GhostButtonStyle(height: 46))

                Button("حفظ واتصال") {
                    Task { await saveAndConnect() }
                }
                .buttonStyle(GradientButtonStyle(height: 46))
            }
            .padding(.top, 2)

            Text("يُخزَّن المفتاح في Keychain على جهازك. استخدم HTTPS، أو عنوان IP محلي أثناء التجربة.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 16)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputField(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Theme.textTertiary.opacity(0.75))
                    .allowsHitTesting(false)
            }

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Theme.text)
            .tint(Theme.cyan)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.leading)
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bgSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func reportBanner(_ report: ConnectionReport) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: report.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundColor(report.ok ? Theme.green : Theme.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.message)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                if report.ok {
                    Text(report.tiktokConfigured
                         ? "مفاتيح TikTok مضبوطة على الخادم."
                         : "تنبيه: مفاتيح TikTok غير مضبوطة على الخادم بعد.")
                        .font(.system(size: 10))
                        .foregroundColor(report.tiktokConfigured ? Theme.textTertiary : Theme.gold)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill((report.ok ? Theme.green : Theme.red).opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((report.ok ? Theme.green : Theme.red).opacity(0.2), lineWidth: 1))
    }

    // MARK: - الوضع

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.demoMode },
                set: { newValue in
                    if !newValue && !store.hasServer {
                        store.showToast("احفظ عنوان الخادم أولاً", .error)
                        return
                    }
                    store.demoMode = newValue
                    report = nil
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("الوضع التجريبي")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("أرقام تمثيلية لـ \(DemoData.brands.count) حساباً لتجربة الواجهة.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))

            HairlineDivider()

            Toggle(isOn: $store.autoSync) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("تحديث تلقائي عند الفتح")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("مزامنة خفيفة إذا مرّ أكثر من ٩٠ ثانية.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))

            Toggle(isOn: $store.hapticsEnabled) {
                Text("الاهتزاز الخفيف")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.text)
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
        }
        .card(padding: 16)
    }

    // MARK: - المزامنة

    private var syncCard: some View {
        VStack(spacing: 0) {
            Button {
                Task { await store.syncAll() }
            } label: {
                settingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    tint: Theme.cyan,
                    title: store.isSyncing ? "جارٍ المزامنة…" : "مزامنة كل الحسابات",
                    subtitle: "آخر تحديث: \(Dates.relative(store.summary.lastSyncedAt))"
                )
            }
            .buttonStyle(PressableStyle(scale: 0.99))
            .disabled(store.isSyncing)

            HairlineDivider().padding(.vertical, 4)

            Button {
                store.refreshIfStale()
                Task { await store.refresh() }
            } label: {
                settingsRow(
                    icon: "arrow.clockwise",
                    tint: Theme.violet,
                    title: "إعادة تحميل من الخادم",
                    subtitle: "بدون طلب مزامنة جديد"
                )
            }
            .buttonStyle(PressableStyle(scale: 0.99))
        }
        .card(padding: 6)
    }

    // MARK: - البيانات

    private var dataCard: some View {
        VStack(spacing: 0) {
            Button {
                exportCSV()
            } label: {
                settingsRow(
                    icon: "square.and.arrow.up",
                    tint: Theme.green,
                    title: "تصدير CSV",
                    subtitle: "ملف جاهز لـ Excel وGoogle Sheets"
                )
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            HairlineDivider().padding(.vertical, 4)

            Button {
                let links = store.accounts.map { $0.url }.joined(separator: "\n")
                UIPasteboard.general.string = links
                store.showToast("تم نسخ \(store.accounts.count) رابطاً", .success)
            } label: {
                settingsRow(
                    icon: "doc.on.doc",
                    tint: Theme.gold,
                    title: "نسخ كل روابط الحسابات",
                    subtitle: "\(store.accounts.count) رابطاً"
                )
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            HairlineDivider().padding(.vertical, 4)

            Button {
                store.clearCache()
            } label: {
                settingsRow(
                    icon: "trash",
                    tint: Theme.red,
                    title: "مسح النسخة المحفوظة",
                    subtitle: "يبقى الخادم كما هو"
                )
            }
            .buttonStyle(PressableStyle(scale: 0.99))
        }
        .card(padding: 6)
    }

    private func settingsRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - حول

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.brand)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: 0x061016))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("نبض")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text("تحليلات TikTok لعدة حسابات · 1.0.0")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Chip(text: "iOS 16+", color: Theme.textSecondary)
            }

            HairlineDivider()

            Text("يعمل نبض عبر TikTok Display API الرسمي: كل حساب يُربط بموافقتك مرة واحدة، ولا نطلب كلمة المرور أبداً. تُخزَّن التوكنات مشفّرة على خادمك الخاص.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(4)

            Link(destination: URL(string: "https://developers.tiktok.com/")!) {
                HStack(spacing: 5) {
                    Image(systemName: "safari")
                    Text("TikTok for Developers")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.cyan)
            }

            Text("هذا التطبيق غير تابع لـ TikTok ولا تدعمه شركة ByteDance.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary.opacity(0.8))
        }
        .card(padding: 16)
    }

    // MARK: - إجراءات

    private func test() async {
        isTesting = true
        report = nil
        let outcome = await store.testConnection(url: url, token: token)
        isTesting = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            report = outcome
        }
    }

    private func saveAndConnect() async {
        guard APIClient.normalize(url) != nil else {
            store.showToast("عنوان الخادم غير صالح", .error)
            return
        }
        store.serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        store.apiToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        store.demoMode = false
        hideKeyboard()
        await store.refresh()
        if store.source == .live {
            store.showToast("تم الاتصال بالخادم", .success)
        } else if let error = store.errorMessage {
            store.showToast(error, .error)
        }
        Task { await test() }
    }

    private func exportCSV() {
        guard !store.accounts.isEmpty else {
            store.showToast("لا توجد حسابات للتصدير", .info)
            return
        }
        let header = ["المنصة", "الحساب", "الاسم", "الرابط", "المنشورات", "المشاهدات", "متوسط المشاهدات", "الإعجابات", "التعليقات", "المشاركات", "المتابعون", "آخر مزامنة"]
        let quote: (String) -> String = { value in
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = [header.map(quote).joined(separator: ",")]
        for account in store.accounts {
            let row = [
                "TikTok",
                "@" + account.handle,
                account.displayName,
                account.url,
                String(account.posts),
                String(account.views),
                String(account.avgViewsPerPost),
                String(account.videoLikes),
                String(account.comments),
                String(account.shares),
                String(account.followers),
                account.lastSyncedAt ?? "",
            ]
            lines.append(row.map(quote).joined(separator: ","))
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\r\n")
        let name = "nabd-accounts-\(Self.dateStamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            shareFile = ShareFile(url: url)
            store.haptic(.success)
        } catch {
            store.showToast("تعذّر إنشاء الملف", .error)
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
