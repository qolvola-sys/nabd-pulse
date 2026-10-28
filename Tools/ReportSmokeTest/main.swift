import Foundation

// اختبار بناء ملف Excel دون الحاجة إلى محاكي iOS.
// يشغّله CI عبر swiftc مع ملفات النماذج وكاتب xlsx.

let calendar = ReportDates.calendar
let periodStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1))!
let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 1))!

let exactPosts: [ReportPost] = [
    ReportPost(
        id: "7300000000000000001",
        accountID: "acc-yellow",
        pageName: "الأصفر علي",
        handle: "yellow.plus",
        title: "منشور تجريبي أول",
        url: "https://www.tiktok.com/@yellow.plus/video/7300000000000000001",
        publishedAt: periodStart.addingTimeInterval(3_600),
        views: 1_234_567,
        likes: 45_678,
        comments: 1_234,
        shares: 567,
        viewsExact: true
    ),
    ReportPost(
        id: "7300000000000000002",
        accountID: "acc-yellow",
        pageName: "الأصفر علي",
        handle: "yellow.plus",
        title: "منشور تجريبي ثانٍ",
        url: "https://www.tiktok.com/@yellow.plus/video/7300000000000000002",
        publishedAt: periodStart.addingTimeInterval(9_000),
        views: 2_222_222,
        likes: 80_000,
        comments: 2_000,
        shares: 900,
        viewsExact: true
    ),
]

let approximatePost = ReportPost(
    id: "7300000000000000003",
    accountID: "acc-second",
    pageName: "صفحة أسبوعية",
    handle: "weekly.page",
    title: "منشور بمشاهدات مقرّبة",
    url: "https://www.tiktok.com/@weekly.page/video/7300000000000000003",
    publishedAt: periodStart.addingTimeInterval(15_000),
    views: 120_000,
    likes: 4_500,
    comments: 220,
    shares: 55,
    viewsExact: false
)

// منشور فيسبوك نصي: يدخل عدّ المنشورات بلا مشاهدات فيديو.
let facebookPost = ReportPost(
    id: "fb-1001",
    pageName: "صفحة فيسبوك",
    handle: "yellowplus",
    platform: .facebook,
    title: "منشور نصي على فيسبوك",
    url: "https://www.facebook.com/yellowplus",
    publishedAt: periodStart.addingTimeInterval(21_000),
    views: 0,
    likes: 1_200,
    comments: 30,
    shares: 5,
    viewsExact: true,
    isVideo: false
)

let groups: [ReportGroup] = [
    ReportGroup(
        name: "المجموعة 1",
        rows: [
            ReportRow(
                accountID: "acc-yellow",
                pageName: "الأصفر علي",
                platform: .tiktok,
                program: "تيك توك",
                posts: 2,
                views: 3_456_789,
                url: "https://www.tiktok.com/@yellow.plus",
                quality: .exact
            ),
            ReportRow(
                accountID: "acc-second",
                pageName: "صفحة أسبوعية",
                platform: .tiktok,
                program: "تيك توك",
                posts: 1,
                views: 120_000,
                notes: "مشاهدات مقرّبة من TikTok",
                url: "https://www.tiktok.com/@weekly.page",
                quality: .approximate
            ),
        ]
    ),
    ReportGroup(
        name: "صفحات إضافية (إدخال يدوي)",
        rows: [
            ReportRow(
                pageName: "صفحة فيسبوك",
                platform: .facebook,
                program: "فيسبوك",
                posts: 7,
                views: 98_000,
                notes: "إدخال يدوي",
                url: "https://www.facebook.com/yellowplus",
                quality: .manual,
                isManual: true
            ),
        ]
    ),
]

let document = ReportDocument(
    kind: .daily,
    spaceID: "smoke-space",
    spaceName: "الأصفر",
    title: "منصات الأصفر",
    periodStart: periodStart,
    periodEnd: periodEnd,
    generatedAt: periodStart.addingTimeInterval(86_400),
    groups: groups,
    posts: exactPosts + [approximatePost, facebookPost],
    note: "ملف اختبار آلي للتحقق من بنية Excel.",
    version: 1
)

do {
    let data = try ReportExcelBuilder(document: document).build()
    guard data.count > 1_000 else {
        throw NSError(domain: "ReportSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "الملف أصغر من المتوقع"])
    }
    guard data.prefix(2) == Data([0x50, 0x4B]) else {
        throw NSError(domain: "ReportSmokeTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "الملف ليس ZIP صالحاً"])
    }

    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "report-smoke.xlsx"
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    print("Wrote \(path) (\(data.count) bytes)")
} catch {
    let message = "Report smoke test failed: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
