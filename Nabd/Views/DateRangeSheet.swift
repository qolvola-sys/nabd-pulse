#if MUTABAA
import SwiftUI

/// منتقي فترة مخصصة (من يوم إلى يوم) على شكل تقويم، مثل «مخصص» في
/// تحليلات إنستغرام. يعطينا نطاقاً نمرّره لمولّد التقرير، فيُجمع
/// المنشور والمشاهدات داخل تلك الأيام فقط.
struct DateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let start: Date
    let end: Date
    /// أقدم يوم يمكن اختياره: خارج نافذة الأرشيف لا توجد بيانات أصلاً.
    let earliest: Date
    let onApply: (Date, Date) -> Void

    @State private var startDay: Date?
    @State private var endDay: Date?
    @State private var visibleMonth: Date
    @State private var dayCount: Int = 0

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // الأحد
        return calendar
    }()

    init(start: Date, end: Date, earliest: Date, onApply: @escaping (Date, Date) -> Void) {
        self.start = start
        self.end = end
        self.earliest = earliest
        self.onApply = onApply
        let calendar = Calendar.current
        _startDay = State(initialValue: calendar.startOfDay(for: start))
        _endDay = State(initialValue: calendar.startOfDay(for: end))
        _visibleMonth = State(initialValue: Self.monthStart(for: start))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            scrollContent
            footer
        }
        .background(Theme.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { syncDayCount() }
    }

    // MARK: - الرأس

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            Spacer()
            Text("فترة مخصصة")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(Theme.text)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                presets
                calendarCard

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("التطبيق يحتفظ بمنشورات ٩ أيام؛ اختر يوماً داخلها لتكون الأرقام كاملة. الأيام الأقدم لا يمكن قراءتها بلا تسجيل دخول.")
                        .font(.system(size: 9.5))
                        .lineSpacing(2)
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            presetButton("٧ أيام", days: 7)
            presetButton("٩ أيام", days: 9)
            Spacer(minLength: 0)
        }
    }

    private func presetButton(_ title: String, days: Int) -> some View {
        Button {
            let today = calendar.startOfDay(for: Date())
            let from = max(calendar.startOfDay(for: earliest),
                           calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
            startDay = from
            endDay = today
            visibleMonth = Self.monthStart(for: from)
            syncDayCount()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.surfaceRaised))
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - التقويم

    private var calendarCard: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            grid
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(Self.monthTitle(visibleMonth))
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(Theme.text)

            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"], id: \.self) { name in
                Text(name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let cells = Self.monthCells(for: visibleMonth, calendar: calendar)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }

        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        if let day = cell {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 38)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isStart = startDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isEnd = endDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inRange = isInRange(day)
        let selectable = day >= calendar.startOfDay(for: earliest)
        let isFuture = day > calendar.startOfDay(for: Date())

        return Button {
            tap(day)
        } label: {
            Text(Self.dayNumber(day))
                .font(.system(size: 12.5, weight: isStart || isEnd ? .heavy : .semibold))
                .foregroundColor(dayTextColor(isStart: isStart, isEnd: isEnd, inRange: inRange, selectable: selectable, isFuture: isFuture))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(dayBackground(isStart: isStart, isEnd: isEnd, inRange: inRange, isFuture: isFuture))
        }
        .buttonStyle(.plain)
        .disabled(isFuture || !selectable)
    }

    private func dayTextColor(isStart: Bool, isEnd: Bool, inRange: Bool, selectable: Bool, isFuture: Bool) -> Color {
        if isFuture { return Theme.textTertiary.opacity(0.35) }
        if isStart || isEnd { return .white }
        if inRange { return Theme.pink }
        if !selectable { return Theme.textTertiary.opacity(0.5) }
        return Theme.text
    }

    @ViewBuilder
    private func dayBackground(isStart: Bool, isEnd: Bool, inRange: Bool, isFuture: Bool) -> some View {
        if isStart || isEnd {
            Circle().fill(Theme.pink).padding(3)
        } else if inRange && !isFuture {
            Rectangle().fill(Theme.pink.opacity(0.14))
        } else {
            Color.clear
        }
    }

    // MARK: - التذييل

    private var footer: some View {
        VStack(spacing: 10) {
            Text(summaryText)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textSecondary)

            Button {
                guard let from = startDay else { return }
                let to = endDay ?? from
                let low = min(from, to)
                let high = max(from, to)
                onApply(low, high)
                dismiss()
            } label: {
                Text("تحديث")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(startDay == nil ? Theme.textTertiary : Theme.pink)
                    )
            }
            .buttonStyle(.plain)
            .disabled(startDay == nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(Theme.bgSoft.ignoresSafeArea())
    }

    private var summaryText: String {
        guard let from = startDay else { return "اختر يوم البداية" }
        let to = endDay ?? from
        let low = min(from, to)
        let high = max(from, to)
        return "\(Self.longDate(low)) - \(Self.longDate(high)) (\(dayCount) من الأيام)"
    }

    // MARK: - السلوك

    private func tap(_ day: Date) {
        let normalized = calendar.startOfDay(for: day)
        if startDay == nil || (startDay != nil && endDay != nil) {
            startDay = normalized
            endDay = nil
        } else if let from = startDay, normalized < from {
            startDay = normalized
            endDay = from
        } else {
            endDay = normalized
        }
        syncDayCount()
    }

    private func isInRange(_ day: Date) -> Bool {
        guard let from = startDay else { return false }
        let to = endDay ?? from
        let low = min(from, to)
        let high = max(from, to)
        return day >= low && day <= high
    }

    private func syncDayCount() {
        guard let from = startDay else {
            dayCount = 0
            return
        }
        let to = endDay ?? from
        let days = calendar.dateComponents([.day], from: min(from, to), to: max(from, to)).day ?? 0
        dayCount = days + 1
    }

    private func shiftMonth(_ delta: Int) {
        if let moved = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = Self.monthStart(for: moved)
        }
    }

    // MARK: - أدوات التاريخ

    private static func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    private static func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// خلايا الشهر: فراغات في البداية ثم أيامه.
    private static func monthCells(for month: Date, calendar: Calendar) -> [Date?] {
        let start = monthStart(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
#endif
