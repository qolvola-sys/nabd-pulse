import Foundation

/// بيانات تمثيلية واقعية تُستخدم قبل ربط الخادم أو عند تشغيل الوضع التجريبي.
/// كل الأرقام مولّدة ببذرة ثابتة حتى تبقى مستقرة بين التشغيلات.
enum DemoData {

    struct Rng {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
        mutating func int(_ range: Range<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.count))
        }
        mutating func chance(_ p: Double) -> Bool { next() < p }
    }

    static let brands: [(String, String)] = [
        ("مطبخ سارة", "matbakh_sara"), ("لمسة ديكور", "lamsat_decor"), ("قهوة الصباح", "qahwa_sabah"),
        ("رياضة كل يوم", "riyada_daily"), ("عالم التقنية", "tech_world_ar"), ("أزياء ليان", "fashion_layan"),
        ("سفرة الشام", "sufrat_sham"), ("نباتات البيت", "beet_plants"), ("مكياج نورة", "makeup_noura"),
        ("وصفات سريعة", "fast_recipes"), ("سيارات 360", "cars_360"), ("سفر بلا حدود", "travel_no_limits"),
        ("كورة اليوم", "koora_today"), ("أب وابنه", "dad_and_son"), ("حرف يدوية", "hand_made_art"),
        ("صحة ورشاقة", "fit_health_ar"), ("بيبي وليد", "baby_walid"), ("ديكور مودرن", "modern_decor"),
        ("معلومة في دقيقة", "info_minute"), ("خط عربي", "arabic_calligraphy"), ("طبيعة ساحرة", "magic_nature"),
        ("فك وتركيب", "fix_and_build"), ("أفكار تصوير", "photo_ideas"), ("حلويات أم راشد", "sweets_om_rashid"),
        ("عطور فاخرة", "luxury_scents"), ("قصص نجاح", "success_stories"), ("حيوانات لطيفة", "cute_pets_ar"),
        ("مغامرات صحراء", "desert_rides"), ("تعلم إنجليزي", "learn_english_ar"), ("تزيين كيك", "cake_decor"),
        ("موسيقى هادئة", "calm_music"), ("شعر وخواطر", "poetry_lines"), ("ألعاب جيمنج", "gaming_zone_ar"),
        ("مشاريع صغيرة", "small_business_ar"), ("عناية بالبشرة", "skin_care_ar"), ("حديقة المنزل", "home_garden"),
        ("أخبار التقنية", "tech_news_ar"), ("طبخ بحري", "sea_food_kitchen"), ("تصوير جوال", "mobile_shots"),
        ("نجارة إبداعية", "creative_wood"), ("قهوة مختصة", "specialty_coffee"), ("أمومة وعمل", "mom_and_work"),
        ("رياضة منزلية", "home_workout"), ("ديكور رمضان", "ramadan_decor"), ("سياحة عربية", "arab_tourism"),
        ("كتب ومكتبات", "books_library"), ("حيل ذكية", "smart_hacks_ar"), ("عالم الدرون", "drone_world"),
        ("مطبخ إيطالي", "italian_kitchen"), ("ستايل رجالي", "men_style_ar"),
    ]

    static let titles: [String] = [
        "جربتها وأولادي أحبوها", "طريقة أسرع من اللي تعرفها", "النتيجة صدمتني",
        "خطوة واحدة تفرق كثير", "أفضل ٣ أفكار لهذا الأسبوع", "لا تسويها قبل ما تشوف الفيديو",
        "سر صغير يغيّر كل شيء", "خلّها في بالك", "مقارنة سريعة", "من الكاميرا مباشرة",
        "تسجيل كامل بدون تعديل", "اللي طلبتوه بالكومنتات", "الجزء الثاني", "سؤال وجواب",
    ]

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func accounts() -> [Account] {
        brands.enumerated().map { index, brand in
            var rng = Rng(seed: UInt64(index + 1) &* 0x9E3779B1)
            let posts = rng.int(18..<280)
            let followers = Int64(3_000 + pow(rng.next(), 2) * 1_900_000)
            let avg = 4_000 + pow(rng.next(), 2.4) * 420_000
            let videosCount = min(posts, 40)
            let views = Int64(Double(videosCount) * avg * (0.55 + rng.next() * 0.9))
            let likes = Int64(Double(views) * (0.035 + rng.next() * 0.09))
            let comments = Int64(Double(views) * (0.001 + rng.next() * 0.006))
            let shares = Int64(Double(views) * (0.002 + rng.next() * 0.01))
            let posts24h = rng.int(0..<5)
            let views24h = Int64(Double(posts24h) * avg * (0.45 + rng.next() * 1.4))
            let posts7d = max(posts24h, rng.int(3..<12))
            let weeklyViews = max(views24h, Int64(Double(avg) * Double(posts7d) * (0.8 + rng.next() * 1.5)))
            let minutesAgo = rng.int(0..<220)
            let synced = iso.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))

            return Account(
                id: "demo-\(brand.1)",
                handle: brand.1,
                displayName: brand.0,
                url: "https://www.tiktok.com/@\(brand.1)",
                avatarUrl: nil,
                isVerified: rng.chance(0.16),
                followers: followers,
                following: Int64(rng.int(30..<950)),
                likes: likes,
                posts: posts,
                views: views,
                videoLikes: likes,
                comments: comments,
                shares: shares,
                fetchedVideos: videosCount,
                posts24h: posts24h,
                views24h: views24h,
                posts7d: posts7d,
                weeklyViews: weeklyViews,
                avgViews: views / Int64(max(videosCount, 1)),
                coverage: Double(videosCount) / Double(posts),
                connected: true,
                status: "ok",
                error: nil,
                lastSyncedAt: synced,
                createdAt: synced
            )
        }
    }

    static func videos(for account: Account, limit: Int = 30) -> [VideoItem] {
        var rng = Rng(seed: UInt64(account.handle.unicodeScalars.reduce(0) { $0 &+ UInt64($1.value) }) &* 0x2545F491)
        let average = max(Double(account.avgViews), 500)
        return (0..<limit).map { index in
            let factor = 0.2 + rng.next() * 2.8
            let views = Int64(max(120, average * factor))
            let createdAt = Int(Date().timeIntervalSince1970) - index * 86_400 - rng.int(0..<7_200)
            return VideoItem(
                id: "\(account.id)-v\(index)",
                title: titles[rng.int(0..<titles.count)],
                coverUrl: nil,
                shareUrl: "https://www.tiktok.com/@\(account.handle)/video/\(7_100_000_000_000_000_000 + Int64(index))",
                duration: rng.int(12..<102),
                createTime: createdAt,
                views: views,
                likes: Int64(Double(views) * (0.03 + rng.next() * 0.09)),
                comments: Int64(Double(views) * (0.001 + rng.next() * 0.006)),
                shares: Int64(Double(views) * (0.002 + rng.next() * 0.01)),
                viewsExact: true
            )
        }
    }

    static func summary(for accounts: [Account]) -> Summary {
        Summary.make(from: accounts)
    }
}
