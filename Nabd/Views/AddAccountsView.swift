import SwiftUI
import UIKit

struct AddAccountsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var isSubmitting = false
    @State private var result: AddAccountsResponse?
    @State private var errorText: String?
    @FocusState private var editorFocused: Bool

    private var entries: [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: "\n,;،"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var parsed: [(raw: String, handle: String?)] {
        entries.map { ($0, AddAccountsView.handle(from: $0)) }
    }

    private var validHandles: [String] {
        var seen = Set<String>()
        return parsed.compactMap { $0.handle }.filter { seen.insert($0).inserted }
    }

    private var invalidCount: Int {
        parsed.filter { $0.handle == nil }.count
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    if store.isDemo { demoNotice }
                    inputCard
                    if !validHandles.isEmpty { previewCard }
                    if let result { resultCard(result) }
                    if let errorText { errorBanner(errorText) }
                    submitButton
                    helpCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("إضافة حسابات")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("الصق روابط TikTok — رابط في كل سطر")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
        }
        .padding(.top, 10)
    }

    private var demoNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.gold)
            Text("أنت في الوضع التجريبي. الإضافة الحقيقية تحتاج خادماً مربوطاً بـ TikTok API — أوقف الوضع التجريبي من الإعدادات.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.gold.opacity(0.2), lineWidth: 1))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("روابط الحسابات", systemImage: "link")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                if !text.isEmpty {
                    Button("مسح") { text = "" }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.cyan)
                }
                Button("لصق") {
                    if let pasted = UIPasteboard.general.string {
                        text = pasted
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.cyan)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("https://www.tiktok.com/@username\n@username2\nhttps://vm.tiktok.com/ZMxxxxx/")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 8)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .focused($editorFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.bgSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(editorFocused ? Theme.cyan.opacity(0.4) : Theme.borderSoft, lineWidth: 1)
            )

            HStack(spacing: 12) {
                Label("\(validHandles.count) صالح", systemImage: "checkmark.circle")
                    .foregroundColor(Theme.green)
                if invalidCount > 0 {
                    Label("\(invalidCount) غير مفهوم", systemImage: "exclamationmark.circle")
                        .foregroundColor(Theme.gold)
                }
                Spacer()
                Text("الحد ١٠٠")
                    .foregroundColor(Theme.textTertiary)
            }
            .font(.system(size: 10.5, weight: .medium))
        }
        .card(padding: 15)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("سيُضاف")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(validHandles.count) حساب")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cyan)
            }
            FlowLayout(spacing: 6) {
                ForEach(validHandles.prefix(24), id: \.self) { handle in
                    Text("@" + handle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.surfaceRaised))
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                if validHandles.count > 24 {
                    Text("+\(validHandles.count - 24)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Theme.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
            }
        }
        .card(padding: 15)
    }

    private func resultCard(_ result: AddAccountsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.green)
                Text("تمت الإضافة")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(result.created.count) جديد")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(Theme.green)
            }

            if !result.created.isEmpty {
                Text("الخطوة التالية: اربط كل حساب بتسجيل الدخول إلى TikTok مرة واحدة.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(3)

                VStack(spacing: 8) {
                    ForEach(result.created) { account in
                        HStack(spacing: 9) {
                            AvatarView(account: account, size: 30, showVerified: false)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.displayName)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                Text("@" + account.handle)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.textTertiary)
                            }
                            Spacer()
                            Button {
                                Task { await store.connect(account) }
                            } label: {
                                Text(store.connectingAccountID == account.id ? "…" : "ربط")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color(hex: 0x061016))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.cyan))
                            }
                            .disabled(store.connectingAccountID != nil)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.bgSoft))
                    }
                }
            }

            if let skipped = result.skipped, !skipped.isEmpty {
                Label("\(skipped.count) حساب مضاف مسبقاً", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
            }
            if let invalid = result.invalid, !invalid.isEmpty {
                Label("\(invalid.count) رابط لم يُفهم", systemImage: "questionmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.gold)
            }
        }
        .card(padding: 15)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.red.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.red.opacity(0.2), lineWidth: 1))
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(Color(hex: 0x061016)).scaleEffect(0.85)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(validHandles.isEmpty ? "أضف رابطاً واحداً على الأقل" : "إضافة \(validHandles.count) حساب")
            }
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(validHandles.isEmpty || isSubmitting || store.isDemo)
        .opacity(store.isDemo ? 0.45 : 1)
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("كيف يعمل الربط؟", systemImage: "questionmark.circle")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(Theme.textSecondary)
            Text("TikTok لا يسمح بقراءة إحصاءات حساب دون إذن صاحبه. لذلك نسجّل دخول كل حساب مرة واحدة عبر TikTok API الرسمي، ثم يبقى مربوطاً ويُحدّث نفسه تلقائياً.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 15)
    }

    private func submit() async {
        guard !validHandles.isEmpty else { return }
        editorFocused = false
        isSubmitting = true
        errorText = nil
        let response = await store.add(links: parsed.filter { $0.handle != nil }.map { $0.raw })
        isSubmitting = false
        if let response {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                result = response
                text = ""
            }
        } else {
            errorText = "لم نستطع إضافة الحسابات. تأكد من اتصال الخادم ثم أعد المحاولة."
        }
    }

    static func handle(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        value = value.replacingOccurrences(of: "www.", with: "")
        if value.lowercased().hasPrefix("tiktok.com/") {
            value = String(value.dropFirst("tiktok.com/".count))
        }
        value = value.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? value
        while value.hasSuffix("/") { value.removeLast() }
        value = value.replacingOccurrences(of: "@", with: "")

        if value.range(of: #"^[A-Za-z0-9._]{2,24}$"#, options: .regularExpression) != nil,
           !value.lowercased().hasSuffix(".com") {
            return value.lowercased()
        }
        if let range = raw.range(of: #"@([A-Za-z0-9._]{2,24})"#, options: .regularExpression) {
            return String(raw[range]).replacingOccurrences(of: "@", with: "").lowercased()
        }
        return nil
    }
}

// MARK: - تخطيط مرن للشارات

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width - 60
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
