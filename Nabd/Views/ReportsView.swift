#if MUTABAA
import SwiftUI
import UIKit

/// شاشة «التقارير» داخل المتابعة: توليد يومي/أسبوعي، سجل المسودات،
/// تعديل التقرير قبل التصدير، ومشاركة ملفات Excel مع بقاء نسخة في Files.
struct ReportsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var reports: ReportsManager

    @State private var selectedKind: ReportKind = .daily
    @State private var filter: ReportFilter = .all
    @State private var editingDocument: ReportDocument?
    @State private var shareFile: ShareFile?
    @State private var showSettings = false
    @State private var pendingDelete: ReportDocument?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header

                if let message = reports.lastError {
                    errorBanner(message)
                }

                generationCard

                if let progress = reports.progress {
                    progressCard(progress)
                }

                scheduleCard
                reportsSection
                filesSection
                footerNote

                Color.clear.frame(height: 108)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .onAppear {
            reports.refreshExportedFiles()
        }
        .sheet(item: $editingDocument) { document in
            ReportEditorView(document: document)
                .environmentObject(store)
                .environmentObject(reports)
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
        }
        .sheet(isPresented: $showSettings) {
            ReportSettingsView()
                .environmentObject(store)
                .environmentObject(reports)
        }
        .confirmationDialog(
            "حذف التقرير؟",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف التقرير", role: .destructive) {
                guard let document = pendingDelete else { return }
                reports.delete(document)
                pendingDelete = nil
                store.showToast("تم حذف التقرير من السجل", .info)
                store.haptic(.success)
            }
            Button("إلغاء", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("يُحذف من سجل التقارير فقط، ولا يحذف ملفات Excel المصدّرة.")
        }
    }

    // MARK: - الرأس

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("التقارير")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.text)
                    Chip(text: "Excel", color: Theme.green, icon: "tablecells.fill")
                }
                Text("تقرير يومي وأسبوعي جاهز للإرسال أو التعديل قبل التصدير")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                showSettings = true
                store.haptic(.selection)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.cyan)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("إعدادات التقارير")
        }
    }

    // MARK: - التنبيهات

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.red)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.red.opacity(0.12)))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                reports.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.red.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.red.opacity(0.2), lineWidth: 1))
    }

    private func sourceWarning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.gold)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.gold.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.gold.opacity(0.18), lineWidth: 1))
    }

    // MARK: - التوليد

    private var window: (start: Date, end: Date) {
        reports.window(for: selectedKind)
    }

    private var manualPagesCount: Int {
        guard let spaceID = store.activeSpace?.id else { return 0 }
        return reports.settings.manualRowsBySpace[spaceID]?.count ?? 0
    }

    private var canGenerate: Bool {
        store.isDirect && !store.accounts.isEmpty && !reports.isGenerating
    }

    private var generationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "إنشاء تقرير",
                subtitle: "الأرقام تُقرأ من صفحة كل حساب مباشرة، ويُعلَّم أي نقص بدل تقديمه كرقم نهائي."
            )

            HStack(spacing: 8) {
                ForEach(ReportKind.allCases) { kind in
                    kindChip(kind)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: selectedKind == .daily ? "sunrise.fill" : "calendar.badge.clock")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.cyan)
                    Text(selectedKind == .daily ? "نافذة اليوم" : "نافذة الأسبوع")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(ReportDates.displayRange(from: window.start, to: window.end))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                Text(ReportDates.windowText(start: window.start, end: window.end))
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)

                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("الحد الأخير غير شامل؛ المنشور عند ١:٠٠ ص بالضبط يتبع التقرير التالي.")
                        .font(.system(size: 9.5))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.textTertiary)

                HStack(spacing: 7) {
                    metaPill(icon: "person.2.fill", text: "\(Num.full(Int64(store.accounts.count))) حساب")
                    metaPill(icon: "square.stack.3d.up.fill", text: "\(Num.full(Int64(store.activeSpace?.groups.count ?? 0))) مجموعة")
                    if manualPagesCount > 0 {
                        metaPill(icon: "rectangle.and.pencil.and.ellipsis", text: "\(Num.full(Int64(manualPagesCount))) صفحة يدوية")
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))

            if !store.isDirect {
                sourceWarning("توليد التقارير يعمل مع مصدر «TikTok مباشرة». أوقف الوضع التجريبي أو الخادم من الإعدادات أولاً.")
            } else if store.accounts.isEmpty {
                sourceWarning("لا توجد حسابات في المساحة النشطة. أضف حساباً واحداً على الأقل ثم أعد المحاولة.")
            }

            Button {
                Task { await generate(selectedKind) }
            } label: {
                HStack(spacing: 8) {
                    if reports.isGenerating {
                        ProgressView().tint(Color(hex: 0x061016)).scaleEffect(0.85)
                    } else {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Text(reports.isGenerating ? "جارٍ قراءة الحسابات…" : "توليد \(selectedKind.title)")
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(!canGenerate)
            .opacity(canGenerate ? 1 : 0.45)
        }
        .card(padding: 16)
    }

    private func kindChip(_ kind: ReportKind) -> some View {
        Button {
            guard !reports.isGenerating else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selectedKind = kind
            }
            store.haptic(.selection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind == .daily ? "sunrise.fill" : "calendar")
                    .font(.system(size: 10, weight: .bold))
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                if kind == .weekly {
                    Text("افتراضياً السبت")
                        .font(.system(size: 8.5, weight: .medium))
                        .opacity(0.7)
                }
            }
            .foregroundColor(selectedKind == kind ? Color(hex: 0x061016) : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule().fill(selectedKind == kind ? Theme.cyan : Theme.surface)
            )
            .overlay(
                Capsule().strokeBorder(selectedKind == kind ? .clear : Theme.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .bold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundColor(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.surfaceRaised))
    }

    private func progressCard(_ progress: ReportProgress) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.cyan)
                    .scaleEffect(0.8)
                Text(progress.phase)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(Num.full(Int64(progress.current))) / \(Num.full(Int64(progress.total)))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }

            ProgressView(value: progress.fraction)
                .tint(Theme.cyan)

            if !progress.handle.isEmpty {
                Text(progress.handle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Text("يبقى TikTok مفتوحاً في الخلفية أثناء القراءة. لا تُغلق التطبيق حتى ينتهي التوليد.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
        }
        .card(padding: 14, radius: 18)
    }

    // MARK: - الجدولة

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "الجدولة",
                subtitle: "التوليد التلقائي عند أول فتح بعد الموعد، أو أثناء بقاء التطبيق مفتوحاً",
                actionTitle: "تعديل",
                action: { showSettings = true }
            )

            HStack(spacing: 9) {
                schedulePill(
                    icon: "sunrise.fill",
                    title: "يومي",
                    value: reports.settings.dailyEnabled ? "١:٠٠ ص" : "متوقف",
                    tint: reports.settings.dailyEnabled ? Theme.cyan : Theme.textTertiary
                )
                schedulePill(
                    icon: "calendar",
                    title: "أسبوعي",
                    value: reports.settings.weeklyEnabled
                        ? "\(ReportDates.weekdayName(reports.settings.weeklyWeekday)) · \(ReportDates.hourText(reports.settings.weeklyHour))"
                        : "متوقف",
                    tint: reports.settings.weeklyEnabled ? Theme.violet : Theme.textTertiary
                )
            }

            if let last = reports.lastGeneratedAt {
                Text("آخر تقرير: \(ReportDates.displayDateTime(last))")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }

            Text("iOS لا يسمح بقراءة TikTok في الخلفية. إذا كان التطبيق مغلقاً عند ١:٠٠ ص، يُنشأ التقرير عند أول فتح بعده.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .card(padding: 16)
    }

    private func schedulePill(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 27, height: 27)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bgSoft))
    }

    // MARK: - سجل التقارير

    private var filteredReports: [ReportDocument] {
        reports.documents.filter { document in
            switch filter {
            case .all: return true
            case .daily: return document.kind == .daily
            case .weekly: return document.kind == .weekly
            }
        }
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "سجل التقارير",
                subtitle: "\(Num.full(Int64(reports.documents.count))) تقرير محفوظ · اضغط أي تقرير للتعديل"
            )

            HStack(spacing: 7) {
                ForEach(ReportFilter.allCases) { item in
                    filterChip(item)
                }
            }

            if filteredReports.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "لا توجد تقارير بعد",
                    message: "أنشئ تقريراً يومياً أو أسبوعياً ليظهر هنا، ثم عدّله أو أرسله."
                )
                .card(padding: 4)
            } else {
                ForEach(filteredReports) { document in
                    reportCard(document)
                }
            }
        }
    }

    private func filterChip(_ item: ReportFilter) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { filter = item }
            store.haptic(.selection)
        } label: {
            Text(item.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(filter == item ? Color(hex: 0x061016) : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(filter == item ? Theme.cyan : Theme.surface)
                )
                .overlay(
                    Capsule().strokeBorder(filter == item ? .clear : Theme.borderSoft, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }

    private func reportCard(_ document: ReportDocument) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                store.haptic(.impact)
                editingDocument = document
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: document.kind == .daily ? "sunrise.fill" : "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(document.kind == .daily ? Theme.cyan : Theme.violet)
                            .frame(width: 25, height: 25)
                            .background(Circle().fill((document.kind == .daily ? Theme.cyan : Theme.violet).opacity(0.12)))

                        Text(document.kind.title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Theme.text)

                        Text(document.spaceName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.surfaceRaised))

                        Spacer(minLength: 4)

                        Chip(text: shortQuality(document), color: reportTint(document))
                    }

                    Text("\(document.displayDate) · \(document.periodText)")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 7) {
                        Text(document.groupSummary)
                        Text("·")
                        Text("\(Num.full(Int64(document.totalPosts))) منشور")
                        Text("·")
                        Text("\(Num.full(document.totalViews)) مشاهدة")
                    }
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 8.5))
                        Text("وُلّد \(ReportDates.displayDateTime(document.generatedAt))")
                        if document.isEdited {
                            Text("· عُدّل")
                                .foregroundColor(Theme.gold)
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 1))

            Menu {
                Button {
                    editingDocument = document
                } label: {
                    Label("تعديل التقرير", systemImage: "pencil")
                }
                Button {
                    share(document)
                } label: {
                    Label("تصدير ومشاركة", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    pendingDelete = document
                } label: {
                    Label("حذف من السجل", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 31, height: 31)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .padding(.top, 2)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface.opacity(0.94)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }

    private func shortQuality(_ document: ReportDocument) -> String {
        if !document.incompleteRows.isEmpty { return "يحتاج مراجعة" }
        if !document.approximateRows.isEmpty { return "مقرّب" }
        if !document.manualRows.isEmpty {
            return document.isFullyExact ? "دقيق + يدوي" : "يدوي"
        }
        if document.isFullyExact { return "دقيق ١٠٠٪" }
        return "—"
    }

    private func reportTint(_ document: ReportDocument) -> Color {
        if !document.incompleteRows.isEmpty { return Theme.red }
        if !document.approximateRows.isEmpty { return Theme.gold }
        if !document.manualRows.isEmpty { return Theme.violet }
        if document.isFullyExact { return Theme.green }
        return Theme.textSecondary
    }

    // MARK: - ملفات Excel

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "ملفات Excel",
                subtitle: "نسخة محفوظة في مجلد التطبيق، ويمكن إرسالها في أي وقت",
                actionTitle: reports.exportedFiles.isEmpty ? nil : "تحديث",
                action: { reports.refreshExportedFiles() }
            )

            if reports.exportedFiles.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                    Text("لم تُصدَّر ملفات بعد. افتح تقريراً واضغط «تصدير ومشاركة».")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
            } else {
                ForEach(reports.exportedFiles) { file in
                    fileRow(file)
                }
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                Text("تجد الملفات في تطبيق «الملفات» ← عندي ← المتابعة ← MutabaaReports ← Exports. مشاركة الملف تتيح إرساله عبر واتساب أو البريد أو أي تطبيق.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.cyan.opacity(0.05)))
        }
        .card(padding: 16)
    }

    private func fileRow(_ file: ReportFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tablecells.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.green)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.green.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.displayTitle) · \(file.sizeText)")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                shareFile = ShareFile(url: file.url)
                store.haptic(.selection)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.cyan)
                    .frame(width: 31, height: 31)
                    .background(Circle().fill(Theme.cyan.opacity(0.10)))
            }
            .buttonStyle(PressableStyle())

            Menu {
                Button {
                    shareFile = ShareFile(url: file.url)
                } label: {
                    Label("مشاركة", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    reports.deleteExportedFile(file)
                    store.showToast("تم حذف الملف", .info)
                } label: {
                    Label("حذف الملف", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 27, height: 31)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bgSoft))
    }

    // MARK: - التذييل

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.green)
                Text("كل مشاهدات TikTok تُقرأ من statsV2 وقت التوليد. أي قراءة ناقصة أو مقرّبة تظهر بعلامة واضحة ولا تُقدَّم كرقم دقيق.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
            }

            Text("التقرير اليومي: من ١:٠٠ ص إلى ١:٠٠ ص من اليوم التالي. التقرير الأسبوعي: سبعة أيام كاملة تنتهي عند الموعد المحدد. يمكنك تعديل العنوان والمجموعات وكل صف قبل التصدير.")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - الإجراءات

    private func generate(_ kind: ReportKind) async {
        guard canGenerate else { return }
        store.haptic(.impact)
        let document = await reports.generate(kind: kind, store: store)
        if let document {
            store.haptic(.success)
            editingDocument = document
        } else if let message = reports.lastError {
            store.showToast(message, .error)
            store.haptic(.error)
        }
    }

    private func share(_ document: ReportDocument) {
        do {
            let url = try reports.export(document)
            shareFile = ShareFile(url: url)
            store.haptic(.success)
            store.showToast("تم تجهيز ملف Excel", .success)
        } catch {
            store.showToast(error.localizedDescription, .error)
            store.haptic(.error)
        }
    }
}

private enum ReportFilter: String, CaseIterable, Identifiable {
    case all
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "الكل"
        case .daily: return "يومي"
        case .weekly: return "أسبوعي"
        }
    }
}
#endif
