#if MUTABAA
import SwiftUI
import UIKit

/// إعدادات التقارير: الجدولة اليومية والأسبوعية، والصفحات الإضافية
/// (فيسبوك وغيرها) التي تُحفظ كقوالب لكل مساحة وتُضاف تلقائياً.
struct ReportSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var reports: ReportsManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingTemplate: ReportManualTemplate?
    @State private var pendingDelete: ReportManualTemplate?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    scheduleCard
                    manualPagesCard
                    limitsCard

                    Color.clear.frame(height: 18)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
        }
        .sheet(item: $editingTemplate) { template in
            ManualReportPageEditor(template: template) { saved in
                upsert(saved)
            }
        }
        .confirmationDialog(
            "حذف الصفحة الإضافية؟",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف", role: .destructive) {
                guard let template = pendingDelete else { return }
                delete(template)
                pendingDelete = nil
                store.showToast("تم حذف الصفحة من قوالب المساحة", .info)
                store.haptic(.success)
            }
            Button("إلغاء", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("تُحذف من التقارير الجديدة فقط، ولا يؤثر ذلك على تقرير سبق إنشاؤه.")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - الرأس

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Button {
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
                Text("إعدادات التقارير")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("الجدولة والصفحات الإضافية لمساحة «\(store.activeSpaceName)»")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Chip(text: "تلقائي", color: Theme.green, icon: "bolt.fill")
        }
    }

    // MARK: - الجدولة

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "الجدولة",
                subtitle: "يُنشأ التقرير عند أول فتح بعد الموعد، أو أثناء بقاء التطبيق مفتوحاً."
            )

            scheduleToggle(
                title: "تقرير يومي",
                subtitle: "نافذة ٢٤ ساعة من ١:٠٠ ص إلى ١:٠٠ ص",
                icon: "sunrise.fill",
                tint: Theme.cyan,
                isOn: Binding(
                    get: { reports.settings.dailyEnabled },
                    set: { value in reports.updateSettings { $0.dailyEnabled = value } }
                )
            )

            scheduleToggle(
                title: "تقرير أسبوعي",
                subtitle: "نافذة ٧ أيام كاملة تنتهي عند الموعد المحدد",
                icon: "calendar.badge.clock",
                tint: Theme.violet,
                isOn: Binding(
                    get: { reports.settings.weeklyEnabled },
                    set: { value in reports.updateSettings { $0.weeklyEnabled = value } }
                )
            )

            if reports.settings.weeklyEnabled {
                VStack(spacing: 0) {
                    settingPickerRow(
                        title: "يوم التقرير الأسبوعي",
                        icon: "calendar",
                        tint: Theme.violet
                    ) {
                        Picker("", selection: Binding(
                            get: { reports.settings.weeklyWeekday },
                            set: { value in reports.updateSettings { $0.weeklyWeekday = value } }
                        )) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(ReportDates.weekdayName(weekday)).tag(weekday)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.cyan)
                    }

                    HairlineDivider().opacity(0.5)

                    settingPickerRow(
                        title: "ساعة التقرير",
                        icon: "clock",
                        tint: Theme.cyan
                    ) {
                        Picker("", selection: Binding(
                            get: { reports.settings.weeklyHour },
                            set: { value in reports.updateSettings { $0.weeklyHour = value } }
                        )) {
                            ForEach(0...23, id: \.self) { hour in
                                Text(ReportDates.hourText(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.cyan)
                    }
                }
                .padding(.horizontal, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }

            HStack(spacing: 7) {
                Image(systemName: "iphone.gen2")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                Text("iOS لا يسمح بقراءة الصفحات في الخلفية. إن كان التطبيق مغلقاً عند الموعد، يُنشأ التقرير عند أول فتح بعده.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cyan.opacity(0.05)))
        }
        .card(padding: 16)
    }

    private func scheduleToggle(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 31, height: 31)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func settingPickerRow<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            content()
        }
        .frame(height: 45)
    }

    // MARK: - الصفحات الإضافية

    private var activeSpaceID: String? {
        store.activeSpace?.id
    }

    private var templates: [ReportManualTemplate] {
        guard let activeSpaceID else { return [] }
        return reports.settings.manualRowsBySpace[activeSpaceID] ?? []
    }

    private var manualPagesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "صفحات إضافية",
                subtitle: "فيسبوك أو أي منصة أخرى — تُضاف كقالب إلى كل تقرير جديد"
            )

            if activeSpaceID == nil {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "لا توجد مساحة نشطة",
                    message: "فعّل مصدر «TikTok مباشرة» واختر مساحة من الأعلى لإدارة صفحاتها."
                )
            } else if templates.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                    Text("لا توجد صفحات يدوية بعد. أضف صفحات فيسبوك أو أي منصة أخرى، وستظهر تلقائياً في كل تقرير جديد لهذه المساحة.")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.bgSoft))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                        templateRow(template)
                        if index < templates.count - 1 {
                            HairlineDivider().opacity(0.5)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }

            Button {
                guard activeSpaceID != nil else { return }
                editingTemplate = ReportManualTemplate(
                    pageName: "",
                    platform: .facebook
                )
                store.haptic(.selection)
            } label: {
                Label("إضافة صفحة يدوية", systemImage: "plus.circle.fill")
            }
            .buttonStyle(GhostButtonStyle(height: 44))
            .disabled(activeSpaceID == nil)
            .opacity(activeSpaceID == nil ? 0.45 : 1)

            Text("تُحفظ هذه الصفحات لكل مساحة على حدة. عند تعديلها أو حذفها يتغير القالب في التقارير الجديدة، ولا تتغير تقاريرك السابقة.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 16)
    }

    private func templateRow(_ template: ReportManualTemplate) -> some View {
        HStack(spacing: 9) {
            Image(systemName: template.platform.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.cyan)
                .frame(width: 27, height: 27)
                .background(Circle().fill(Theme.cyan.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                Text(template.pageName.isEmpty ? "صفحة بدون اسم" : template.pageName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(template.platform.title)
                    if !template.program.isEmpty {
                        Text("·")
                        Text(template.program)
                    }
                    if !template.url.isEmpty {
                        Text("·")
                        Image(systemName: "link")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                }
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button {
                    editingTemplate = template
                } label: {
                    Label("تعديل", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = template
                } label: {
                    Label("حذف", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 27, height: 31)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - الحدود

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.gold)
                Text("ملاحظات مهمة")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Theme.text)
            }

            bullet("التقرير اليومي يغطي نافذة ٢٤ ساعة كاملة تنتهي عند ١:٠٠ ص. الحد الأخير غير شامل.")
            bullet("التقرير الأسبوعي يغطي ٧ أيام كاملة تنتهي عند اليوم والساعة المحددين.")
            bullet("الأرقام تُقرأ من TikTok وفيسبوك وقت التوليد. أي نقص أو تقريب يظهر بعلامة واضحة بدل تقديمه كرقم دقيق.")
            bullet("الصفحات اليدوية لا تُقرأ آلياً؛ تُضاف فارغة ليتم إدخال أرقامها وتعديلها قبل التصدير.")
        }
        .card(padding: 15)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 3, height: 3)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - العمليات

    private func upsert(_ template: ReportManualTemplate) {
        guard let activeSpaceID else { return }
        reports.updateSettings { settings in
            var list = settings.manualRowsBySpace[activeSpaceID] ?? []
            if let index = list.firstIndex(where: { $0.id == template.id }) {
                list[index] = template
            } else {
                list.append(template)
            }
            settings.manualRowsBySpace[activeSpaceID] = list
        }
        store.showToast("تم حفظ الصفحة في قوالب المساحة", .success)
        store.haptic(.success)
    }

    private func delete(_ template: ReportManualTemplate) {
        guard let activeSpaceID else { return }
        reports.updateSettings { settings in
            var list = settings.manualRowsBySpace[activeSpaceID] ?? []
            list.removeAll { $0.id == template.id }
            if list.isEmpty {
                settings.manualRowsBySpace.removeValue(forKey: activeSpaceID)
            } else {
                settings.manualRowsBySpace[activeSpaceID] = list
            }
        }
    }
}

// MARK: - محرّر الصفحة الإضافية

private struct ManualReportPageEditor: View {
    @Environment(\.dismiss) private var dismiss

    let template: ReportManualTemplate
    let onSave: (ReportManualTemplate) -> Void

    @State private var pageName: String
    @State private var platform: ReportPlatform
    @State private var program: String
    @State private var notes: String
    @State private var url: String
    @State private var validationMessage: String?

    init(template: ReportManualTemplate, onSave: @escaping (ReportManualTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _pageName = State(initialValue: template.pageName)
        _platform = State(initialValue: template.platform)
        _program = State(initialValue: template.program)
        _notes = State(initialValue: template.notes)
        _url = State(initialValue: template.url)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel("اسم الصفحة")
                        input("مثال: صفحة الأصفر", text: $pageName)

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
                        input("مثال: فيسبوك", text: $program)

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
                        input("https://www.facebook.com/...", text: $url, keyboard: .URL, ltr: true)

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(Theme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("تُضاف هذه الصفحة إلى كل تقرير جديد فارغة. أدخل عدد النشر والمشاهدات من محرّر التقرير ثم صدّر الملف.")
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.textTertiary)
                            .lineSpacing(3)
                    }
                    .card(padding: 15)

                    Button(action: save) {
                        Label("حفظ الصفحة", systemImage: "checkmark")
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
            let isDefaultText = ReportPlatform.allCases.contains { $0.defaultProgram == program }
            if program.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDefaultText {
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
                Text("صفحة إضافية")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("تُحفظ كقالب لكل تقارير هذه المساحة")
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

        var updated = template
        updated.pageName = trimmedName
        updated.platform = platform
        updated.program = program.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? platform.defaultProgram
            : program.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(updated)
        dismiss()
    }
}
#endif
