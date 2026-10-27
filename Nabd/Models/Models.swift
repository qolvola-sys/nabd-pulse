import Foundation
import SwiftUI

// MARK: - التقييم الأسبوعي

/// تقييم من ١٠٠ يعتمد اعتماداً مباشراً على مجموع مشاهدات المنشورات في آخر ٧ أيام.
/// كل ١٠٬٠٠٠ مشاهدة = نقطة واحدة: ٥٠٠٬٠٠٠ مشاهدة = ٥٠، و١٬٠٠٠٬٠٠٠ مشاهدة = ١٠٠.
/// ما فوق المليون يبقى ١٠٠ (أعلى تقييم).
enum WeeklyScore {
    static let viewsForFullScore: Int64 = 1_000_000
    static let viewsPerPoint: Int64 = viewsForFullScore / 100

    static func value(for views: Int64) -> Int {
        guard views > 0 else { return 0 }
        let points = views / viewsPerPoint
        return Int(min(100, points))
    }

    static func label(for score: Int) -> String {
        switch score {
        case 85...: return "أداء استثنائي"
        case 65...: return "أداء قوي"
        case 40...: return "أداء متوسط"
        case 1...: return "بداية جيدة"
        default: return "لا مشاهدات بعد"
        }
    }
}

// MARK: - فك ترميز مرن (يتحمل غياب الحقول أو اختلاف أنواعها)

extension KeyedDecodingContainer {
    func flexInt64(_ key: Key, default fallback: Int64 = 0) -> Int64 {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int64(value) }
        if let value = try? decode(String.self, forKey: key), let parsed = Int64(value) { return parsed }
        return fallback
    }

    func flexInt(_ key: Key, default fallback: Int = 0) -> Int {
        Int(flexInt64(key, default: Int64(fallback)))
    }

    func flexDouble(_ key: Key, default fallback: Double = 0) -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key), let parsed = Double(value) { return parsed }
        return fallback
    }

    func flexBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return value != 0 }
        return fallback
    }

    func flexString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        return fallback
    }

    func flexStringOrNil(_ key: Key) -> String? {
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        return value.isEmpty ? nil : value
    }
}

// MARK: - الحساب

enum AccountPlatform: String, Codable, CaseIterable, Identifiable, Hashable {
    case tiktok
    case facebook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiktok: return "TikTok"
        case .facebook: return "فيسبوك"
        }
    }

    var icon: String {
        switch self {
        case .tiktok: return "play.rectangle.fill"
        case .facebook: return "globe"
        }
    }

    var defaultProgram: String {
        switch self {
        case .tiktok: return "تيك توك"
        case .facebook: return "فيسبوك"
        }
    }

    var profileURLPrefix: String {
        switch self {
        case .tiktok: return "https://www.tiktok.com/@"
        case .facebook: return "https://www.facebook.com/"
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: String
    var platform: AccountPlatform
    var handle: String
    var url: String
    var displayName: String
    var avatarUrl: String?
    var isVerified: Bool
    var followers: Int64
    var following: Int64
    var likes: Int64
    var posts: Int
    /// هل عدد المنشورات الكلي معلوم؟ فيسبوك لا يعرض إجمالي منشورات الصفحة،
    /// لذلك نعرض عدد المنشورات المحمّلة مع علامة أنه ليس إجمالياً.
    var postsCountExact: Bool
    var views: Int64
    var videoLikes: Int64
    var comments: Int64
    var shares: Int64
    var fetchedVideos: Int
    var posts24h: Int
    var views24h: Int64
    var posts7d: Int
    var weeklyViews: Int64
    var avgViews: Int64
    var coverage: Double
    var connected: Bool
    var publicStats: Bool
    /// هل إحصاءات الملف (المتابعون/الإعجابات/المنشورات) دقيقة ١٠٠٪؟
    /// تأتي دقيقة من statsV2، وقد تكون مقرّبة إذا اعتمدنا على embed فقط.
    var profileExact: Bool
    /// هل مشاهدات المنشورات المحمّلة دقيقة ١٠٠٪؟ TikTok يقرّب المشاهدات العامة
    /// فوق ١٠ آلاف، لذلك نعلّمها بـ ≈ بدل تقديمها كرقم دقيق.
    var viewsExact: Bool
    /// هل كل منشورات آخر ٢٤ ساعة موجودة ضمن المنشورات المحمّلة؟
    var dailyComplete: Bool
    var dailyViewsExact: Bool
    /// هل كل منشورات آخر ٧ أيام موجودة ضمن المنشورات المحمّلة؟
    var weeklyComplete: Bool
    var weeklyViewsExact: Bool
    /// هل تم تحميل كل منشورات الحساب (وليس آخر ١٠ فقط)؟
    var allPostsLoaded: Bool
    var status: String
    var error: String?
    var lastSyncedAt: String?
    var createdAt: String

    var avgViewsPerPost: Int64 {
        avgViews > 0 ? avgViews : (fetchedVideos > 0 ? views / Int64(fetchedVideos) : 0)
    }

    /// مفتاح مستقل لكل منصة حتى لا يتعارض حساب TikTok وFacebook بنفس الاسم.
    var videoCacheKey: String {
        platform == .facebook ? "facebook:\(handle.lowercased())" : handle
    }

    var isFacebook: Bool { platform == .facebook }

    /// مجموع مشاهدات المنشورات المحمّلة دقيق فقط إذا كانت كل المنشورات محمّلة
    /// وكانت مشاهداتها غير مقرّبة من TikTok.
    var totalViewsExact: Bool { allPostsLoaded && viewsExact }

    /// التقييم دقيق فقط إذا اكتملت نافذة الأسبوع وكانت المشاهدات غير مقرّبة.
    var weeklyScoreExact: Bool { weeklyComplete && weeklyViewsExact }

    /// هل توجد أرقام تفاعل على مستوى المنشورات (وليست إجمالي إعجابات الحساب)؟
    var hasVideoEngagementData: Bool {
        videoLikes > 0 || comments > 0 || shares > 0
    }

    /// متوسط مشاهدات المنشور الواحد خلال آخر ٢٤ ساعة.
    var avgViews24h: Int64 {
        posts24h > 0 ? views24h / Int64(posts24h) : 0
    }

    /// تقييم من ١٠٠ حسب مشاهدات المنشورات المنشورة خلال آخر ٧ أيام.
    var weeklyScore: Int {
        WeeklyScore.value(for: weeklyViews)
    }

    /// هل لدينا مشاهدات محمّلة (عامة أو رسمية)؟
    var hasViewData: Bool { views > 0 }

    var avgLikesPerPost: Int64 {
        posts > 0 ? likes / Int64(posts) : 0
    }

    var engagementRate: Double {
        guard views > 0 else { return 0 }
        return Double(videoLikes + comments + shares) / Double(views)
    }

    var isHealthy: Bool { status == "ok" }

    var statusLabel: String {
        switch status {
        case "ok": return "متصل"
        case "public": return "بيانات مباشرة"
        case "needs_reconnect": return "يحتاج إعادة ربط"
        case "cached": return "آخر بيانات محفوظة"
        case "pending": return "بانتظار التحديث"
        case "error": return "آخر بيانات محفوظة"
        default: return connected ? "متصل" : "غير مربوط"
        }
    }

    var initials: String {
        let source = displayName.isEmpty ? handle : displayName
        let words = source.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(handle.prefix(1)).uppercased() : letters
    }

    var paletteIndex: Int {
        let sum = handle.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return abs(sum) % Theme.chartPalette.count
    }

    enum CodingKeys: String, CodingKey {
        case id, platform, handle, url, displayName, avatarUrl, isVerified, followers, following
        case likes, posts, views, videoLikes, comments, shares, fetchedVideos, posts24h, views24h, posts7d, weeklyViews
        case avgViews, coverage, connected, publicStats, status, error, lastSyncedAt, createdAt
        case profileExact, viewsExact, dailyComplete, dailyViewsExact, weeklyComplete, weeklyViewsExact, allPostsLoaded
        case postsCountExact
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id, default: UUID().uuidString)
        platform = AccountPlatform(rawValue: c.flexString(.platform, default: "tiktok")) ?? .tiktok
        handle = c.flexString(.handle)
        let fallbackURL = (platform == .facebook ? "https://www.facebook.com/" : "https://www.tiktok.com/@") + handle
        url = c.flexString(.url, default: fallbackURL)
        displayName = c.flexString(.displayName, default: handle)
        avatarUrl = c.flexStringOrNil(.avatarUrl)
        isVerified = c.flexBool(.isVerified)
        followers = c.flexInt64(.followers)
        following = c.flexInt64(.following)
        likes = c.flexInt64(.likes)
        posts = c.flexInt(.posts)
        postsCountExact = c.flexBool(.postsCountExact, default: platform == .tiktok)
        views = c.flexInt64(.views)
        videoLikes = c.flexInt64(.videoLikes)
        comments = c.flexInt64(.comments)
        shares = c.flexInt64(.shares)
        fetchedVideos = c.flexInt(.fetchedVideos)
        posts24h = c.flexInt(.posts24h)
        views24h = c.flexInt64(.views24h)
        posts7d = c.flexInt(.posts7d)
        weeklyViews = c.flexInt64(.weeklyViews)
        avgViews = c.flexInt64(.avgViews)
        coverage = c.flexDouble(.coverage)
        connected = c.flexBool(.connected)
        publicStats = c.flexBool(.publicStats)
        profileExact = c.flexBool(.profileExact, default: connected)
        viewsExact = c.flexBool(.viewsExact, default: connected)
        dailyComplete = c.flexBool(.dailyComplete, default: connected)
        dailyViewsExact = c.flexBool(.dailyViewsExact, default: connected && dailyComplete)
        weeklyComplete = c.flexBool(.weeklyComplete, default: connected)
        weeklyViewsExact = c.flexBool(.weeklyViewsExact, default: connected && weeklyComplete)
        allPostsLoaded = c.flexBool(
            .allPostsLoaded,
            default: connected && fetchedVideos > 0 && posts > 0 && fetchedVideos >= posts
        )
        status = c.flexString(.status, default: "pending")
        error = c.flexStringOrNil(.error)
        lastSyncedAt = c.flexStringOrNil(.lastSyncedAt)
        createdAt = c.flexString(.createdAt, default: "")
    }

    init(id: String, platform: AccountPlatform = .tiktok, handle: String, displayName: String, url: String = "", avatarUrl: String? = nil,
         isVerified: Bool = false, followers: Int64 = 0, following: Int64 = 0, likes: Int64 = 0,
         posts: Int = 0, postsCountExact: Bool = true, views: Int64 = 0, videoLikes: Int64 = 0, comments: Int64 = 0, shares: Int64 = 0,
         fetchedVideos: Int = 0, posts24h: Int = 0, views24h: Int64 = 0,
         posts7d: Int = 0, weeklyViews: Int64 = 0,
         avgViews: Int64 = 0, coverage: Double = 1, connected: Bool = true,
         publicStats: Bool = false, profileExact: Bool = true,
         viewsExact: Bool = true, dailyComplete: Bool = true, dailyViewsExact: Bool = true,
         weeklyComplete: Bool = true, weeklyViewsExact: Bool = true, allPostsLoaded: Bool = false,
         status: String = "ok", error: String? = nil, lastSyncedAt: String? = nil, createdAt: String = "") {
        self.id = id
        self.platform = platform
        self.handle = handle
        self.url = url.isEmpty
            ? ((platform == .facebook ? "https://www.facebook.com/" : "https://www.tiktok.com/@") + handle)
            : url
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.followers = followers
        self.following = following
        self.likes = likes
        self.posts = posts
        self.postsCountExact = postsCountExact
        self.views = views
        self.videoLikes = videoLikes
        self.comments = comments
        self.shares = shares
        self.fetchedVideos = fetchedVideos
        self.posts24h = posts24h
        self.views24h = views24h
        self.posts7d = posts7d
        self.weeklyViews = weeklyViews
        self.avgViews = avgViews
        self.coverage = coverage
        self.connected = connected
        self.publicStats = publicStats
        self.profileExact = profileExact
        self.viewsExact = viewsExact
        self.dailyComplete = dailyComplete
        self.dailyViewsExact = dailyViewsExact
        self.weeklyComplete = weeklyComplete
        self.weeklyViewsExact = weeklyViewsExact
        self.allPostsLoaded = allPostsLoaded
        self.status = status
        self.error = error
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }
}

// MARK: - الفيديو

struct VideoItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var coverUrl: String?
    var shareUrl: String?
    var duration: Int
    var createTime: Int
    var views: Int64
    var likes: Int64
    var comments: Int64
    var shares: Int64
    /// هل عدد المشاهدات دقيق؟ الأرقام العامة الكبيرة يقرّبها TikTok.
    var viewsExact: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, coverUrl, shareUrl, duration, createTime, views, likes, comments, shares, viewsExact
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id, default: UUID().uuidString)
        title = c.flexString(.title, default: "")
        coverUrl = c.flexStringOrNil(.coverUrl)
        shareUrl = c.flexStringOrNil(.shareUrl)
        duration = c.flexInt(.duration)
        createTime = c.flexInt(.createTime)
        views = c.flexInt64(.views)
        likes = c.flexInt64(.likes)
        comments = c.flexInt64(.comments)
        shares = c.flexInt64(.shares)
        viewsExact = c.flexBool(.viewsExact, default: views < 10_000)
    }

    init(id: String, title: String, coverUrl: String? = nil, shareUrl: String? = nil,
         duration: Int = 0, createTime: Int = 0, views: Int64 = 0, likes: Int64 = 0,
         comments: Int64 = 0, shares: Int64 = 0, viewsExact: Bool = false) {
        self.id = id
        self.title = title
        self.coverUrl = coverUrl
        self.shareUrl = shareUrl
        self.duration = duration
        self.createTime = createTime
        self.views = views
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.viewsExact = viewsExact
    }
}

// MARK: - الملخص

struct Summary: Codable, Hashable {
    var accounts: Int
    var connected: Int
    var posts: Int
    var views: Int64
    /// إجمالي إعجابات الحسابات كما يعرضه TikTok (رقم عام دقيق).
    var totalLikes: Int64
    /// مجموع تفاعل المنشورات المحمّلة (متاح عبر Display API فقط).
    var likes: Int64
    var comments: Int64
    var shares: Int64
    var posts24h: Int
    var views24h: Int64
    var posts7d: Int
    var weeklyViews: Int64
    var avgViews: Int64
    var loadedVideos: Int
    var profileExact: Bool
    var viewsExact: Bool
    var dailyComplete: Bool
    var dailyViewsExact: Bool
    var weeklyComplete: Bool
    var weeklyViewsExact: Bool
    var allPostsLoaded: Bool
    var lastSyncedAt: String?

    var weeklyScore: Int {
        WeeklyScore.value(for: weeklyViews)
    }

    var weeklyScoreExact: Bool { weeklyComplete && weeklyViewsExact }

    var allViewsExact: Bool { allPostsLoaded && viewsExact }

    static let empty = Summary(accounts: 0, connected: 0, posts: 0, views: 0, totalLikes: 0,
                               likes: 0, comments: 0, shares: 0, posts24h: 0, views24h: 0,
                               avgViews: 0, lastSyncedAt: nil)

    enum CodingKeys: String, CodingKey {
        case accounts, connected, posts, views, totalLikes, likes, comments, shares, posts24h, views24h
        case posts7d, weeklyViews, avgViews, loadedVideos, profileExact, viewsExact, dailyComplete, dailyViewsExact
        case weeklyComplete, weeklyViewsExact, allPostsLoaded, lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = c.flexInt(.accounts)
        connected = c.flexInt(.connected)
        posts = c.flexInt(.posts)
        views = c.flexInt64(.views)
        totalLikes = c.flexInt64(.totalLikes)
        likes = c.flexInt64(.likes)
        comments = c.flexInt64(.comments)
        shares = c.flexInt64(.shares)
        posts24h = c.flexInt(.posts24h)
        views24h = c.flexInt64(.views24h)
        posts7d = c.flexInt(.posts7d)
        weeklyViews = c.flexInt64(.weeklyViews)
        avgViews = c.flexInt64(.avgViews)
        loadedVideos = c.flexInt(.loadedVideos)
        profileExact = c.flexBool(.profileExact)
        viewsExact = c.flexBool(.viewsExact)
        dailyComplete = c.flexBool(.dailyComplete)
        dailyViewsExact = c.flexBool(.dailyViewsExact)
        weeklyComplete = c.flexBool(.weeklyComplete)
        weeklyViewsExact = c.flexBool(.weeklyViewsExact)
        allPostsLoaded = c.flexBool(.allPostsLoaded)
        lastSyncedAt = c.flexStringOrNil(.lastSyncedAt)
    }

    init(accounts: Int, connected: Int, posts: Int, views: Int64, totalLikes: Int64 = 0,
         likes: Int64, comments: Int64, shares: Int64, posts24h: Int, views24h: Int64,
         avgViews: Int64, lastSyncedAt: String?, posts7d: Int = 0, weeklyViews: Int64 = 0,
         loadedVideos: Int = 0, profileExact: Bool = true, viewsExact: Bool = false, dailyComplete: Bool = true,
         dailyViewsExact: Bool = false, weeklyComplete: Bool = true,
         weeklyViewsExact: Bool = false, allPostsLoaded: Bool = false) {
        self.accounts = accounts
        self.connected = connected
        self.posts = posts
        self.views = views
        self.totalLikes = totalLikes
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.posts24h = posts24h
        self.views24h = views24h
        self.posts7d = posts7d
        self.weeklyViews = weeklyViews
        self.avgViews = avgViews
        self.loadedVideos = loadedVideos
        self.profileExact = profileExact
        self.viewsExact = viewsExact
        self.dailyComplete = dailyComplete
        self.dailyViewsExact = dailyViewsExact
        self.weeklyComplete = weeklyComplete
        self.weeklyViewsExact = weeklyViewsExact
        self.allPostsLoaded = allPostsLoaded
        self.lastSyncedAt = lastSyncedAt
    }

    static func make(from accounts: [Account]) -> Summary {
        let posts = accounts.reduce(0) { $0 + $1.posts }
        let views = accounts.reduce(Int64(0)) { $0 + $1.views }
        let totalLikes = accounts.reduce(Int64(0)) { $0 + $1.likes }
        let likes = accounts.reduce(Int64(0)) { $0 + $1.videoLikes }
        let comments = accounts.reduce(Int64(0)) { $0 + $1.comments }
        let shares = accounts.reduce(Int64(0)) { $0 + $1.shares }
        let posts24h = accounts.reduce(0) { $0 + $1.posts24h }
        let views24h = accounts.reduce(Int64(0)) { $0 + $1.views24h }
        let posts7d = accounts.reduce(0) { $0 + $1.posts7d }
        let weeklyViews = accounts.reduce(Int64(0)) { $0 + $1.weeklyViews }
        let loadedVideos = accounts.reduce(0) { $0 + $1.fetchedVideos }
        let synced = accounts.compactMap { $0.lastSyncedAt }.sorted().last
        return Summary(
            accounts: accounts.count,
            connected: accounts.filter { $0.connected }.count,
            posts: posts,
            views: views,
            totalLikes: totalLikes,
            likes: likes,
            comments: comments,
            shares: shares,
            posts24h: posts24h,
            views24h: views24h,
            avgViews: loadedVideos > 0 ? views / Int64(loadedVideos) : 0,
            lastSyncedAt: synced,
            posts7d: posts7d,
            weeklyViews: weeklyViews,
            loadedVideos: loadedVideos,
            profileExact: accounts.allSatisfy { $0.profileExact },
            viewsExact: accounts.allSatisfy { $0.viewsExact },
            dailyComplete: accounts.allSatisfy { $0.dailyComplete },
            dailyViewsExact: accounts.allSatisfy { $0.dailyViewsExact },
            weeklyComplete: accounts.allSatisfy { $0.weeklyComplete },
            weeklyViewsExact: accounts.allSatisfy { $0.weeklyViewsExact },
            allPostsLoaded: accounts.allSatisfy { $0.allPostsLoaded }
        )
    }
}

// MARK: - استجابات الخادم

struct AccountsResponse: Codable {
    var accounts: [Account]
    var summary: Summary?
}

struct SummaryResponse: Codable {
    var summary: Summary
    var top: [Account]?
}

struct AccountDetailResponse: Codable {
    var account: Account
    var videos: [VideoItem]
}

struct AccountEnvelope: Codable {
    var account: Account
}

struct SkippedAccount: Codable {
    var handle: String?
    var reason: String?
}

struct AddAccountsResponse: Codable {
    var created: [Account]
    var skipped: [SkippedAccount]?
    var invalid: [String]?
    var accounts: [Account]?
    /// أسباب تعذّر قراءة بعض الصفحات أو الحسابات بعد نجاح الإضافة.
    var errors: [String]?
}

struct SyncResult: Codable {
    var id: String?
    var ok: Bool?
    var cached: Bool?
    var error: String?
}

struct SyncResponse: Codable {
    var syncedAt: String?
    var total: Int?
    var results: [SyncResult]?
    var summary: Summary?
}

struct HealthResponse: Codable {
    var ok: Bool?
    var demo: Bool?
    var tiktokConfigured: Bool?
    var version: String?
}

struct ServerMeta: Codable {
    var demo: Bool?
    var tiktokConfigured: Bool?
    var maxVideosPerAccount: Int?
    var serverTime: String?
}
