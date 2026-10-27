import Foundation

// MARK: - أنواع التقارير

enum ReportKind: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "تقرير يومي"
        case .weekly: return "تقرير أسبوعي"
        }
    }

    var longTitle: String {
        switch self {
        case .daily: return "تقرير المتابعة اليومي"
        case .weekly: return "تقرير المتابعة الأسبوعي"
        }
    }

    var fileNameComponent: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    var periodLabel: String {
        switch self {
        case .daily: return "٢٤ ساعة"
        case .weekly: return "٧ أيام"
        }
    }

    var windowExplanation: String {
        switch self {
        case .daily:
            return "كل منشور نُشر من الساعة ١:٠٠ صباحاً حتى ١:٠٠ صباحاً من اليوم التالي."
        case .weekly:
            return "كل منشور نُشر خلال سبعة أيام كاملة تنتهي عند الساعة ١:٠٠ صباحاً."
        }
    }
}

enum ReportPlatform: String, Codable, CaseIterable, Identifiable {
    case tiktok
    case facebook
    case instagram
    case youtube
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: return "TikTok"
        case .facebook: return "Facebook"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .other: return "أخرى"
        }
    }

    var defaultProgram: String {
        switch self {
        case .tiktok: return "تيك توك"
        case .facebook: return "فيسبوك"
        case .instagram: return "إنستغرام"
        case .youtube: return "يوتيوب"
        case .other: return "أخرى"
        }
    }

    var icon: String {
        switch self {
        case .tiktok: return "play.rectangle.fill"
        case .facebook: return "f.circle.fill"
        case .instagram: return "camera.circle.fill"
        case .youtube: return "play.circle.fill"
        case .other: return "globe"
        }
    }
}

// MARK: - جودة الأرقام

enum ReportQuality: String, Codable, CaseIterable, Hashable {
    case exact
    case approximate
    case partial
    case unavailable
    case manual

    var label: String {
        switch self {
        case .exact: return "دقيق ١٠٠٪"
        case .approximate: return "مقرّب"
        case .partial: return "قراءة جزئية"
        case .unavailable: return "غير متاح"
        case .manual: return "إدخال يدوي"
        }
    }

    var shortLabel: String {
        switch self {
        case .exact: return "دقيق"
        case .approximate: return "مقرّب"
        case .partial: return "جزئي"
        case .unavailable: return "غير متاح"
        case .manual: return "يدوي"
        }
    }

    var symbol: String {
        switch self {
        case .exact: return "checkmark.seal.fill"
        case .approximate: return "approx"
        case .partial: return "exclamationmark.triangle.fill"
        case .unavailable: return "xmark.octagon.fill"
        case .manual: return "pencil"
        }
    }

    var style: XLSXStyle {
        switch self {
        case .exact: return .good
        case .approximate: return .warning
        case .partial, .unavailable: return .bad
        case .manual: return .note
        }
    }
}

// MARK: - صفوف التقرير

struct ReportRow: Identifiable, Codable, Hashable {
    var id: String
    var accountID: String?
    var pageName: String
    var platform: ReportPlatform
    /// نص حر مثل «تيك توك» أو «فيسبوك ت» كما في نموذج Excel.
    var program: String
    var posts: Int?
    var views: Int64?
    var notes: String
    var url: String
    var quality: ReportQuality
    var isManual: Bool

    init(
        id: String = UUID().uuidString,
        accountID: String? = nil,
        pageName: String,
        platform: ReportPlatform = .tiktok,
        program: String? = nil,
        posts: Int? = nil,
        views: Int64? = nil,
        notes: String = "",
        url: String = "",
        quality: ReportQuality = .exact,
        isManual: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.pageName = pageName
        self.platform = platform
        self.program = program ?? platform.defaultProgram
        self.posts = posts
        self.views = views
        self.notes = notes
        self.url = url
        self.quality = quality
        self.isManual = isManual
    }

    var postsText: String {
        guard let posts else { return "—" }
        return ReportNumber.full(Int64(posts))
    }

    var viewsText: String {
        guard let views else { return "—" }
        return ReportNumber.full(views)
    }

    var hasNumbers: Bool {
        posts != nil || views != nil
    }
}

struct ReportGroup: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var rows: [ReportRow]

    init(id: String = UUID().uuidString, name: String, rows: [ReportRow] = []) {
        self.id = id
        self.name = name
        self.rows = rows
    }

    var totalPosts: Int {
        rows.compactMap(\.posts).reduce(0, +)
    }

    var totalViews: Int64 {
        rows.compactMap(\.views).reduce(Int64(0), +)
    }

    var exactCount: Int {
        rows.filter { $0.quality == .exact }.count
    }

    var partialCount: Int {
        rows.filter { $0.quality == .partial || $0.quality == .unavailable || $0.quality == .approximate }.count
    }
}

// MARK: - تفاصيل المنشورات

struct ReportPost: Identifiable, Codable, Hashable {
    var id: String
    var accountID: String?
    var pageName: String
    var handle: String
    var platform: ReportPlatform
    var title: String
    var url: String
    var publishedAt: Date
    var views: Int64
    var likes: Int64
    var comments: Int64
    var shares: Int64
    var viewsExact: Bool

    init(
        id: String,
        accountID: String? = nil,
        pageName: String,
        handle: String,
        platform: ReportPlatform = .tiktok,
        title: String = "",
        url: String = "",
        publishedAt: Date,
        views: Int64 = 0,
        likes: Int64 = 0,
        comments: Int64 = 0,
        shares: Int64 = 0,
        viewsExact: Bool = true
    ) {
        self.id = id
        self.accountID = accountID
        self.pageName = pageName
        self.handle = handle
        self.platform = platform
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.views = views
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.viewsExact = viewsExact
    }
}

// MARK: - التقرير المحفوظ

struct ReportDocument: Identifiable, Codable, Hashable {
    var id: String
    var kind: ReportKind
    var spaceID: String
    var spaceName: String
    var title: String
    var periodStart: Date
    var periodEnd: Date
    var generatedAt: Date
    var lastEditedAt: Date?
    var groups: [ReportGroup]
    var posts: [ReportPost]
    var note: String
    var version: Int

    init(
        id: String = UUID().uuidString,
        kind: ReportKind,
        spaceID: String,
        spaceName: String,
        title: String = "منصات الأصفر",
        periodStart: Date,
        periodEnd: Date,
        generatedAt: Date = Date(),
        lastEditedAt: Date? = nil,
        groups: [ReportGroup] = [],
        posts: [ReportPost] = [],
        note: String = "",
        version: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.title = title
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.generatedAt = generatedAt
        self.lastEditedAt = lastEditedAt
        self.groups = groups
        self.posts = posts
        self.note = note
        self.version = version
    }

    var rows: [ReportRow] {
        groups.flatMap(\.rows)
    }

    var totalPosts: Int {
        rows.compactMap(\.posts).reduce(0, +)
    }

    var totalViews: Int64 {
        rows.compactMap(\.views).reduce(Int64(0), +)
    }

    /// الصفوف التي قُرئت آلياً (TikTok أو فيسبوك) ولا تشمل الصفحات اليدوية.
    var trackedRows: [ReportRow] {
        rows.filter { !$0.isManual && $0.quality != .manual }
    }

    var exactRows: [ReportRow] {
        rows.filter { $0.quality == .exact }
    }

    var approximateRows: [ReportRow] {
        rows.filter { $0.quality == .approximate }
    }

    var incompleteRows: [ReportRow] {
        rows.filter { $0.quality == .partial || $0.quality == .unavailable }
    }

    var manualRows: [ReportRow] {
        rows.filter { $0.isManual || $0.quality == .manual }
    }

    var isFullyExact: Bool {
        !trackedRows.isEmpty && trackedRows.allSatisfy { $0.quality == .exact }
    }

    var qualitySummary: String {
        if trackedRows.isEmpty {
            if manualRows.isEmpty { return "لا توجد صفحات في التقرير" }
            return "\(ReportNumber.full(Int64(manualRows.count))) صفحة إدخال يدوي"
        }
        if isFullyExact {
            if manualRows.isEmpty {
                return "كل الأرقام المحمّلة دقيقة ١٠٠٪"
            }
            return "كل الأرقام المحمّلة دقيقة ١٠٠٪ · \(ReportNumber.full(Int64(manualRows.count))) صفحة إدخال يدوي"
        }
        if !incompleteRows.isEmpty {
            return "\(ReportNumber.full(Int64(incompleteRows.count))) صفحة تحتاج إعادة قراءة"
        }
        if !approximateRows.isEmpty {
            return "\(ReportNumber.full(Int64(approximateRows.count))) صفحة بمشاهدات عامة غير مكتملة"
        }
        return "لا توجد صفحات محمّلة"
    }

    var periodText: String {
        ReportDates.windowText(start: periodStart, end: periodEnd)
    }

    var displayDate: String {
        ReportDates.displayDate(periodStart)
    }

    var displayTitle: String {
        "\(kind.title) · \(displayDate)"
    }

    var dayKey: String {
        ReportDates.dayKey(periodStart)
    }

    var fileBaseName: String {
        "Mutabaa-\(kind.fileNameComponent)-\(dayKey)"
    }

    var isEdited: Bool {
        lastEditedAt != nil
    }

    var groupSummary: String {
        "\(ReportNumber.full(Int64(groups.count))) مجموعات · \(ReportNumber.full(Int64(rows.count))) صفحة"
    }
}

// MARK: - إعدادات التقارير

struct ReportManualTemplate: Identifiable, Codable, Hashable {
    var id: String
    var pageName: String
    var platform: ReportPlatform
    var program: String
    var notes: String
    var url: String

    init(
        id: String = UUID().uuidString,
        pageName: String = "صفحة جديدة",
        platform: ReportPlatform = .facebook,
        program: String? = nil,
        notes: String = "",
        url: String = ""
    ) {
        self.id = id
        self.pageName = pageName
        self.platform = platform
        self.program = program ?? platform.defaultProgram
        self.notes = notes
        self.url = url
    }
}

struct ReportSettings: Codable, Equatable {
    var dailyEnabled: Bool
    var weeklyEnabled: Bool
    /// ١ = الأحد … ٧ = السبت (نفس ترتيب Calendar).
    var weeklyWeekday: Int
    var weeklyHour: Int
    var manualRowsBySpace: [String: [ReportManualTemplate]]

    init(
        dailyEnabled: Bool = true,
        weeklyEnabled: Bool = true,
        weeklyWeekday: Int = 7,
        weeklyHour: Int = 1,
        manualRowsBySpace: [String: [ReportManualTemplate]] = [:]
    ) {
        self.dailyEnabled = dailyEnabled
        self.weeklyEnabled = weeklyEnabled
        self.weeklyWeekday = weeklyWeekday
        self.weeklyHour = weeklyHour
        self.manualRowsBySpace = manualRowsBySpace
    }

    private enum CodingKeys: String, CodingKey {
        case dailyEnabled, weeklyEnabled, weeklyWeekday, weeklyHour, manualRowsBySpace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyEnabled) ?? true
        weeklyEnabled = try c.decodeIfPresent(Bool.self, forKey: .weeklyEnabled) ?? true
        weeklyWeekday = min(max(try c.decodeIfPresent(Int.self, forKey: .weeklyWeekday) ?? 7, 1), 7)
        weeklyHour = min(max(try c.decodeIfPresent(Int.self, forKey: .weeklyHour) ?? 1, 0), 23)
        manualRowsBySpace = try c.decodeIfPresent([String: [ReportManualTemplate]].self, forKey: .manualRowsBySpace) ?? [:]
    }

    static let `default` = ReportSettings()
}

// MARK: - الملفات

struct ReportFile: Identifiable, Hashable {
    let url: URL
    let kind: ReportKind
    let createdAt: Date
    let size: Int64
    let dayKey: String

    var id: String { url.path }

    var displayTitle: String {
        "\(kind.title) · \(ReportDates.displayDate(fromDayKey: dayKey) ?? dayKey)"
    }

    var displayDate: String {
        ReportDates.displayDate(fromDayKey: dayKey) ?? dayKey
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct ReportProgress: Equatable {
    var kind: ReportKind
    var current: Int
    var total: Int
    var handle: String
    var phase: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(current) / Double(total), 0), 1)
    }
}

// MARK: - أدوات التاريخ

enum ReportDates {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let monthNames = [
        "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
        "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"
    ]

    static let weekdayNames = [
        "الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"
    ]

    static func dayKey(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func startOfDay(_ date: Date = Date()) -> Date {
        calendar.startOfDay(for: date)
    }

    static func date(fromDayKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    static func displayDate(fromDayKey key: String) -> String? {
        guard let date = date(fromDayKey: key) else { return nil }
        return displayDate(date)
    }

    static func displayDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = components.day ?? 1
        let month = max(1, min(12, components.month ?? 1))
        let year = components.year ?? 2026
        return "\(day) \(monthNames[month - 1]) \(year)"
    }

    static func displayDateTime(_ date: Date) -> String {
        "\(displayDate(date)) · \(timeFormatter.string(from: date))"
    }

    static func displayRange(from start: Date, to end: Date) -> String {
        let startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: end)
        let startMonth = max(1, min(12, startComponents.month ?? 1))
        let endMonth = max(1, min(12, endComponents.month ?? 1))
        let startDay = startComponents.day ?? 1
        let endDay = endComponents.day ?? 1
        let startYear = startComponents.year ?? 2026
        let endYear = endComponents.year ?? 2026

        if startYear == endYear && startMonth == endMonth {
            return "\(startDay)–\(endDay) \(monthNames[endMonth - 1]) \(endYear)"
        }
        if startYear == endYear {
            return "\(startDay) \(monthNames[startMonth - 1]) – \(endDay) \(monthNames[endMonth - 1]) \(endYear)"
        }
        return "\(startDay) \(monthNames[startMonth - 1]) \(startYear) – \(endDay) \(monthNames[endMonth - 1]) \(endYear)"
    }

    static func windowText(start: Date, end: Date) -> String {
        "من \(displayDateTime(start)) إلى \(displayDateTime(end))"
    }

    static func weekdayName(_ weekday: Int) -> String {
        let index = min(max(weekday, 1), 7) - 1
        return weekdayNames[index]
    }

    static func hourText(_ hour: Int) -> String {
        let safe = min(max(hour, 0), 23)
        if safe == 0 { return "١٢:٠٠ منتصف الليل" }
        if safe < 12 { return "\(ReportNumber.full(Int64(safe))):٠٠ صباحاً" }
        if safe == 12 { return "١٢:٠٠ ظهراً" }
        return "\(ReportNumber.full(Int64(safe - 12))):٠٠ مساءً"
    }

    static func addingDays(_ days: Int, to date: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: days, to: startOfDay(date)) ?? date
    }

    // MARK: نوافذ التقرير

    /// نافذة اليوم المنتهية عند أحدث الساعة ١ صباحاً مرّت.
    /// مثلاً عند الفتح ١:٠٥ صباحاً يوم ٢٦ أكتوبر: ٢٥ أكتوبر ١:٠٠ ص → ٢٦ أكتوبر ١:٠٠ ص.
    static func dailyWindow(now: Date = Date(), hour: Int = 1) -> (start: Date, end: Date) {
        let safeHour = min(max(hour, 0), 23)
        let todayCutoff = calendar.date(bySettingHour: safeHour, minute: 0, second: 0, of: now)
            ?? calendar.startOfDay(for: now)
        let end: Date
        if now >= todayCutoff {
            end = todayCutoff
        } else {
            end = calendar.date(byAdding: .day, value: -1, to: todayCutoff) ?? todayCutoff
        }
        let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86_400)
        return (start, end)
    }

    /// نافذة الأسبوع المنتهية عند أحدث يوم مجدول مرّ (افتراضياً السبت ١:٠٠ ص).
    static func weeklyWindow(now: Date = Date(), weekday: Int = 7, hour: Int = 1) -> (start: Date, end: Date) {
        let targetWeekday = min(max(weekday, 1), 7)
        let safeHour = min(max(hour, 0), 23)
        var chosen: Date?

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now),
                  let cutoff = calendar.date(bySettingHour: safeHour, minute: 0, second: 0, of: day),
                  cutoff <= now,
                  calendar.component(.weekday, from: cutoff) == targetWeekday else { continue }
            chosen = cutoff
            break
        }

        let end = chosen
            ?? calendar.date(byAdding: .day, value: -7, to: now)
            ?? now.addingTimeInterval(-604_800)
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-604_800)
        return (start, end)
    }
}

// MARK: - أرقام عربية مختصرة

enum ReportNumber {
    static func full(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func compact(_ value: Int64) -> String {
        let absolute = abs(Double(value))
        let sign = value < 0 ? "-" : ""
        if absolute >= 1_000_000_000 {
            return sign + trimmed(absolute / 1_000_000_000) + " مليار"
        }
        if absolute >= 1_000_000 {
            return sign + trimmed(absolute / 1_000_000) + " مليون"
        }
        if absolute >= 1_000 {
            return sign + trimmed(absolute / 1_000) + " ألف"
        }
        return full(value)
    }

    private static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
