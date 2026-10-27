#if MUTABAA
import SwiftUI
import UIKit

/// تعديل مسودة التقرير قبل تصديرها: العنوان، الملاحظات، أسماء المجموعات،
/// وكل حقول كل صف. التعديل يُحفظ تلقائياً عند الإغلاق، ويمكن تصديره فوراً.
struct ReportEditorView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var reports: ReportsManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReportDocument
    @State private var editingRow: ReportRow?
    @State private var editingGroupID: String?
    @State private var shareFile: ShareFile?
    @State private var isDirty = false
    @State private var lastSavedAt: Date?

    init(document: ReportDocument) {
        _draft = State(initialValue: document)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    metaCard
                    qualityCard
                    groupsSection
                    postsCard
                    footerNote

                    Color.clear.frame(height: 18)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .sheet(item: $editingRow) { row in
            ReportRowEditorSheet(row: row) { updated in
                update(updated, groupID: editingGroupID)
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: draft) { _ in
            isDirty = true
        }
        .onDisappear {
            if isDirty {
                reports.save(draft)
            }
        }
    }

    // MARK: - الرأس

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Button {
                saveDraft(showToast: false)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 3) {
                Text("تعديل التقرير")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                HStack(spacing: 5) {
                    Text(draft.kind.longTitle)
                    Text("·")
                    Text(draft.displayDate)
                    if draft.isEdited {
                        Text("· معدّل")
                            .foregroundColor(Theme.gold)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            if isDirty {
                Chip(text: "غير محفوظ", color: Theme.gold, icon: "circle.fill")
            } else if let lastSavedAt {
                Text("حُفظ \(ReportDates.timeFormatter.string(from: lastSavedAt))")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Theme.green)
            } else {
                Chip(text: "مسودة", color: Theme.cyan)
            }
        }
    }

    // MARK: - البيانات الأساسية

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            fieldLabel("عنوان التقرير")
            editorField("عنوان التقرير", text: $draft.title)

            HStack(spacing: 8) {
                infoLine(icon: "calendar", text: draft.kind.longTitle)
                infoLine(icon: "clock", text: ReportDates.displayRange(from: draft.periodStart, to: draft.periodEnd))
            }

            fieldLabel("ملاحظة التقرير")
            TextEditor(text: $draft.note)
                .font(.system(size: 12))
                .foregroundColor(Theme.text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 84)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.bgSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Theme.borderSoft, lineWidth: 1)
                )

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                Text("النافذة الزمنية ثابتة: \(ReportDates.windowText(start: draft.periodStart, end: draft.periodEnd)). الحد الأخير غير شامل.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card(padding: 16)
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(qualityTint)
                Text(draft.qualitySummary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                Chip(
                    text: qualityChipText,
                    color: qualityTint
                )
            }

            HStack(spacing: 8) {
                metric(value: Num.full(Int64(draft.totalPosts)), label: "منشور", tint: Theme.cyan)
                metric(value: Num.full(draft.totalViews), label: "مشاهدة", tint: Theme.violet)
                metric(value: Num.full(Int64(draft.rows.count)), label: "صفحة", tint: Theme.gold)
            }

            Text("تعديل رقم في أي صف يحوّله إلى «إدخال يدوي» حتى لا يُقدَّم كرقم TikTok دقيق. تعديل الاسم أو الملاحظات فقط لا يغيّر دقة الرقم.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 15)
    }

    private var qualityTint: Color {
        if !draft.incompleteRows.isEmpty { return Theme.red }
        if !draft.approximateRows.isEmpty { return Theme.gold }
        if !draft.manualRows.isEmpty { return Theme.violet }
        if draft.isFullyExact { return Theme.green }
        return Theme.textSecondary
    }

    private var qualityChipText: String {
        if !draft.incompleteRows.isEmpty || !draft.approximateRows.isEmpty {
            return "راجع الأرقام"
        }
        if !draft.manualRows.isEmpty {
            return draft.isFullyExact ? "دقيق + يدوي" : "يدوي"
        }
        if draft.isFullyExact { return "دقيق ١٠٠٪" }
        return "لا توجد أرقام"
    }

    private func metric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.08)))
    }

    // MARK: - المجموعات

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "محتوى التقرير",
                subtitle: "\(Num.full(Int64(draft.groups.count))) مجموعات · \(Num.full(Int64(draft.rows.count))) صفحة"
            )

            if draft.groups.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "لا توجد مجموعات",
                    message: "أضف مجموعة ثم أضف صفحاتها، أو أعد توليد التقرير."
                )
                .card(padding: 2)
            } else {
                ForEach(draft.groups) { group in
                    groupCard(group)
                }
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    draft.groups.append(ReportGroup(name: "مجموعة جديدة"))
                }
                store.haptic(.selection)
            } label: {
                Label("إضافة مجموعة", systemImage: "plus.circle.fill")
            }
            .buttonStyle(GhostButtonStyle(height: 44))
        }
    }

    private func groupCard(_ group: ReportGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.cyan)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.cyan.opacity(0.12)))

                TextField("اسم المجموعة", text: groupNameBinding(group.id))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)

                Text("\(Num.full(Int64(group.rows.count)))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surfaceRaised))

                if draft.groups.count > 1 {
                    Menu {
                        Button(role: .destructive) {
                            deleteGroup(group.id)
                        } label: {
                            Label("حذف المجموعة", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.textTertiary)
                            .frame(width: 27, height: 27)
                    }
                }
            }
            .padding(.bottom, 5)

            HairlineDivider().padding(.vertical, 4)

            if group.rows.isEmpty {
                Text("لا توجد صفحات في هذه المجموعة")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(group.rows) { row in
                    rowView(row, groupID: group.id)
                    if row.id != group.rows.last?.id {
                        HairlineDivider().opacity(0.45)
                    }
                }
            }

            Button {
                addRow(to: group.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("إضافة صفحة")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.cyan)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            HStack(spacing: 8) {
                Text("\(Num.full(Int64(group.totalPosts))) منشور")
                Text("·")
                Text("\(Num.full(group.totalViews)) مشاهدة")
                Spacer()
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(Theme.textTertiary)
            .padding(.top, 2)
        }
        .card(padding: 14, radius: 19)
    }

    private func rowView(_ row: ReportRow, groupID: String) -> some View {
        HStack(spacing: 6) {
            Button {
                editingGroupID = groupID
                editingRow = row
                store.haptic(.selection)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: row.platform.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(row.platform == .tiktok ? Theme.pink : Theme.cyan)
                        .frame(width: 27, height: 27)
                        .background(Circle().fill((row.platform == .tiktok ? Theme.pink : Theme.cyan).opacity(0.10)))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(row.pageName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            if !row.url.isEmpty {
                                Image(systemName: "link")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundColor(Theme.cyan.opacity(0.8))
                            }
                        }

                        HStack(spacing: 5) {
                            Text(row.program)
                            Text("·")
                            Text(row.required)
                            if !row.notes.isEmpty {
                                Text("·")
                                Text(row.notes)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.viewsText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(row.postsText) منشور")
                            .font(.system(size: 8.5))
                            .foregroundColor(Theme.textTertiary)
                    }

                    Chip(text: row.quality.shortLabel, color: rowTint(row.quality))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.995))

            Menu {
                Button {
                    editingGroupID = groupID
                    editingRow = row
                } label: {
                    Label("تعديل الصف", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteRow(row.id, groupID: groupID)
                } label: {
                    Label("حذف الصف", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 23, height: 30)
            }
        }
        .padding(.vertical, 5)
    }

    private func rowTint(_ quality: ReportQuality) -> Color {
        switch quality {
        case .exact: return Theme.green
        case .approximate: return Theme.gold
        case .partial, .unavailable: return Theme.red
        case .manual: return Theme.violet
        }
    }

    // MARK: - تفاصيل المنشورات

    private var postsCard: some View {
        let sorted = draft.posts.sorted { $0.publishedAt > $1.publishedAt }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "تفاصيل المنشورات",
                subtitle: "\(Num.full(Int64(sorted.count))) منشوراً · تُصدَّر في ورقة مستقلة داخل Excel"
            )

            if sorted.isEmpty {
                Text("لا توجد منشورات مسجلة في هذه النافذة.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(sorted.prefix(4))) { post in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(post.viewsExact ? Theme.green : Theme.gold)
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.pageName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                            Text(ReportDates.displayDateTime(post.publishedAt))
                                .font(.system(size: 8.5))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        Text(Num.maybeApprox(post.views, exact: post.viewsExact))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.text)
                        Text("مشاهدة")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 3)
                }

                if sorted.count > 4 {
                    Text("و\(Num.full(Int64(sorted.count - 4))) منشوراً آخر في ملف Excel")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                }
            }

            Text("تفاصيل المنشورات هي أرقام القراءة الأصلية من TikTok. إذا عدّلت أرقام صف يدوياً، يبقى الصف المعدّل في ورقة الملخص وتظهر التفاصيل الأصلية هنا.")
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 15)
    }

    private var footerNote: some View {
        Text("عند التصدير تُنشأ ثلاث أوراق: «ورقه1» بنمط نموذج منصات الأصفر، و«الملخص»، و«تفاصيل المنشورات». الملف يُحفظ في مجلد التطبيق ويمكن إرساله مباشرة.")
            .font(.system(size: 9))
            .foregroundColor(Theme.textTertiary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
    }

    // MARK: - الشريط السفلي

    private var bottomBar: some View {
        HStack(spacing: 9) {
            Button {
                saveDraft(showToast: true)
            } label: {
                Label("حفظ", systemImage: "checkmark")
            }
            .buttonStyle(GhostButtonStyle(height: 48))

            Button {
                exportAndShare()
            } label: {
                Label("تصدير ومشاركة", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(GradientButtonStyle(height: 48))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Theme.bg.opacity(0), Theme.bg.opacity(0.96), Theme.bg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - الربط والتحرير

    private func groupNameBinding(_ groupID: String) -> Binding<String> {
        Binding(
            get: {
                draft.groups.first(where: { $0.id == groupID })?.name ?? ""
            },
            set: { newValue in
                guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
                draft.groups[index].name = newValue
            }
        )
    }

    private func addRow(to groupID: String) {
        guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
        let row = ReportRow(
            pageName: "صفحة جديدة",
            platform: .facebook,
            required: "حسب التبليغ",
            quality: .manual,
            isManual: true
        )
        draft.groups[index].rows.append(row)
        store.haptic(.selection)
    }

    private func deleteRow(_ rowID: String, groupID: String) {
        guard let index = draft.groups.firstIndex(where: { $0.id == groupID }) else { return }
        draft.groups[index].rows.removeAll { $0.id == rowID }
        store.haptic(.impact)
    }

    private func deleteGroup(_ groupID: String) {
        guard draft.groups.count > 1 else { return }
        draft.groups.removeAll { $0.id == groupID }
        store.haptic(.impact)
    }

    private func update(_ row: ReportRow, groupID: String?) {
        guard let groupID,
              let groupIndex = draft.groups.firstIndex(where: { $0.id == groupID }),
              let rowIndex = draft.groups[groupIndex].rows.firstIndex(where: { $0.id == row.id }) else { return }
        draft.groups[groupIndex].rows[rowIndex] = row
        isDirty = true
    }

    private func saveDraft(showToast: Bool) {
        reports.save(draft)
        lastSavedAt = Date()
        isDirty = false
        if showToast {
            store.showToast("تم حفظ تعديلات التقرير", .success)
            store.haptic(.success)
        }
    }

    private func exportAndShare() {
        saveDraft(showToast: false)
        do {
            let url = try reports.export(draft)
            shareFile = ShareFile(url: url)
            store.haptic(.success)
            store.showToast("تم تجهيز ملف Excel", .success)
        } catch {
            store.showToast(error.localizedDescription, .error)
            store.haptic(.error)
        }
    }

    // MARK: - عناصر الحقول

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func infoLine(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bgSoft))
    }
}

// MARK: - محرّر الصف

private struct ReportRowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: ReportRow
    let onSave: (ReportRow) -> Void

    @State private var pageName: String
    @State private var platform: ReportPlatform
    @State private var program: String
    @State private var required: String
    @State private var postsText: String
    @State private var viewsText: String
    @State private var notes: String
    @State private var url: String
    @State private var validationMessage: String?

    init(row: ReportRow, onSave: @escaping (ReportRow) -> Void) {
        self.row = row
        self.onSave = onSave
        _pageName = State(initialValue: row.pageName)
        _platform = State(initialValue: row.platform)
        _program = State(initialValue: row.program)
        _required = State(initialValue: row.required)
        _postsText = State(initialValue: row.posts.map { String($0) } ?? "")
        _viewsText = State(initialValue: row.views.map { String($0) } ?? "")
        _notes = State(initialValue: row.notes)
        _url = State(initialValue: row.url)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel("اسم الصفحة")
                        input("اسم الصفحة", text: $pageName)

                        fieldLabel("المنصة")
                        Picker("المنصة", selection: $platform) {
                            ForEach(ReportPlatform.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.cyan)
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.bgSoft))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))

                        fieldLabel("البرنامج")
                        input("مثال: فيسبوك أو تيك توك", text: $program)

                        fieldLabel("العدد المطلوب")
                        input("مثال: 8 أو حسب التبليغ", text: $required)

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("عدد النشر")
                                input("اتركه فارغاً", text: $postsText, keyboard: .numberPad, ltr: true)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("عدد المشاهدات")
                                input("اتركه فارغاً", text: $viewsText, keyboard: .numberPad, ltr: true)
                            }
                        }

                        fieldLabel("الملاحظات")
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 70)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.bgSoft))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))

                        fieldLabel("الرابط")
                        input("https://www.tiktok.com/@...", text: $url, keyboard: .URL, ltr: true)

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(Theme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text(qualityHint)
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.textTertiary)
                            .lineSpacing(3)
                    }
                    .card(padding: 15)

                    Button(action: save) {
                        Label("حفظ الصف", systemImage: "checkmark")
                    }
                    .buttonStyle(GradientButtonStyle(height: 48))
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: platform) { newValue in
            if program.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                program == row.platform.defaultProgram {
                program = newValue.defaultProgram
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.cyan)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.cyan.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text("تعديل الصف")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(row.isManual ? "إدخال يدوي" : "بيانات TikTok")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var qualityHint: String {
        if row.isManual || row.quality == .manual {
            return "هذا الصف إدخال يدوي. يبقى كذلك حتى لو أدخلت أرقاماً، ولا يُحتسب ضمن أرقام TikTok الدقيقة."
        }
        return "إذا غيّرت عدد النشر أو المشاهدات، سيتحول الصف تلقائياً إلى إدخال يدوي حتى تبقى الأرقام الدقيقة من TikTok واضحة."
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func input(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        ltr: Bool = false
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .foregroundColor(Theme.text)
            .tint(Theme.cyan)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
            .multilineTextAlignment(ltr ? .leading : .trailing)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func save() {
        let trimmedName = pageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "اكتب اسم الصفحة أولاً."
            return
        }

        let posts = parseCount(postsText)
        if !postsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, posts == nil {
            validationMessage = "عدد النشر يجب أن يكون رقماً صحيحاً أو فارغاً."
            return
        }

        let views = parseCount(viewsText)
        if !viewsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, views == nil {
            validationMessage = "عدد المشاهدات يجب أن يكون رقماً صحيحاً أو فارغاً."
            return
        }

        validationMessage = nil

        var updated = row
        updated.pageName = trimmedName
        updated.platform = platform
        updated.program = program.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? platform.defaultProgram
            : program.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.required = required.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.posts = posts.map { Int($0) }
        updated.views = views
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url.trimmingCharacters(in: .whitespacesAndNewlines)

        let numbersChanged = updated.posts != row.posts || updated.views != row.views
        let platformChanged = updated.platform != row.platform
        if row.isManual || row.quality == .manual || numbersChanged || (platformChanged && updated.platform != .tiktok) {
            updated.quality = .manual
            updated.isManual = true
        }
        if updated.platform != .tiktok {
            updated.accountID = nil
        }

        onSave(updated)
        dismiss()
    }

    private func parseCount(_ raw: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let digits: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
        ]
        var normalized = String(trimmed.map { digits[$0] ?? $0 })
        normalized = normalized
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: " ", with: "")

        if let value = Int64(normalized) { return value }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.number(from: normalized)?.int64Value
    }
}
#endif
