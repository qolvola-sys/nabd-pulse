import Foundation
import SwiftUI

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

struct Account: Identifiable, Codable, Hashable {
    var id: String
    var platform: String
    var handle: String
    var url: String
    var displayName: String
    var avatarUrl: String?
    var isVerified: Bool
    var followers: Int64
    var following: Int64
    var likes: Int64
    var posts: Int
    var views: Int64
    var videoLikes: Int64
    var comments: Int64
    var shares: Int64
    var fetchedVideos: Int
    var posts24h: Int
    var views24h: Int64
    var avgViews: Int64
    var coverage: Double
    var connected: Bool
    var publicStats: Bool
    var status: String
    var error: String?
    var lastSyncedAt: String?
    var createdAt: String

    var avgViewsPerPost: Int64 {
        avgViews > 0 ? avgViews : (posts > 0 ? views / Int64(posts) : 0)
    }

    /// متوسط مشاهدات المنشور الواحد خلال آخر ٢٤ ساعة.
    var avgViews24h: Int64 {
        posts24h > 0 ? views24h / Int64(posts24h) : 0
    }

    /// هل لدينا مشاهدات حقيقية؟ (تأتي فقط من الحسابات المربوطة عبر Display API)
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
        case "public": return "بيانات عامة"
        case "needs_reconnect": return "يحتاج إعادة ربط"
        case "error": return "تعذّر التحديث"
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
        case likes, posts, views, videoLikes, comments, shares, fetchedVideos, posts24h, views24h
        case avgViews, coverage, connected, publicStats, status, error, lastSyncedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexString(.id, default: UUID().uuidString)
        platform = c.flexString(.platform, default: "tiktok")
        handle = c.flexString(.handle)
        url = c.flexString(.url, default: "https://www.tiktok.com/@\(handle)")
        displayName = c.flexString(.displayName, default: handle)
        avatarUrl = c.flexStringOrNil(.avatarUrl)
        isVerified = c.flexBool(.isVerified)
        followers = c.flexInt64(.followers)
        following = c.flexInt64(.following)
        likes = c.flexInt64(.likes)
        posts = c.flexInt(.posts)
        views = c.flexInt64(.views)
        videoLikes = c.flexInt64(.videoLikes)
        comments = c.flexInt64(.comments)
        shares = c.flexInt64(.shares)
        fetchedVideos = c.flexInt(.fetchedVideos)
        posts24h = c.flexInt(.posts24h)
        views24h = c.flexInt64(.views24h)
        avgViews = c.flexInt64(.avgViews)
        coverage = c.flexDouble(.coverage)
        connected = c.flexBool(.connected)
        publicStats = c.flexBool(.publicStats)
        status = c.flexString(.status, default: "pending")
        error = c.flexStringOrNil(.error)
        lastSyncedAt = c.flexStringOrNil(.lastSyncedAt)
        createdAt = c.flexString(.createdAt, default: "")
    }

    init(id: String, handle: String, displayName: String, url: String = "", avatarUrl: String? = nil,
         isVerified: Bool = false, followers: Int64 = 0, following: Int64 = 0, likes: Int64 = 0,
         posts: Int = 0, views: Int64 = 0, videoLikes: Int64 = 0, comments: Int64 = 0, shares: Int64 = 0,
         fetchedVideos: Int = 0, posts24h: Int = 0, views24h: Int64 = 0,
         avgViews: Int64 = 0, coverage: Double = 1, connected: Bool = true,
         publicStats: Bool = false,
         status: String = "ok", error: String? = nil, lastSyncedAt: String? = nil, createdAt: String = "") {
        self.id = id
        self.platform = "tiktok"
        self.handle = handle
        self.url = url.isEmpty ? "https://www.tiktok.com/@\(handle)" : url
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.followers = followers
        self.following = following
        self.likes = likes
        self.posts = posts
        self.views = views
        self.videoLikes = videoLikes
        self.comments = comments
        self.shares = shares
        self.fetchedVideos = fetchedVideos
        self.posts24h = posts24h
        self.views24h = views24h
        self.avgViews = avgViews
        self.coverage = coverage
        self.connected = connected
        self.publicStats = publicStats
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

    enum CodingKeys: String, CodingKey {
        case id, title, coverUrl, shareUrl, duration, createTime, views, likes, comments, shares
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
    }

    init(id: String, title: String, coverUrl: String? = nil, shareUrl: String? = nil,
         duration: Int = 0, createTime: Int = 0, views: Int64 = 0, likes: Int64 = 0,
         comments: Int64 = 0, shares: Int64 = 0) {
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
    }
}

// MARK: - الملخص

struct Summary: Codable, Hashable {
    var accounts: Int
    var connected: Int
    var posts: Int
    var views: Int64
    var likes: Int64
    var comments: Int64
    var shares: Int64
    var posts24h: Int
    var views24h: Int64
    var avgViews: Int64
    var lastSyncedAt: String?

    static let empty = Summary(accounts: 0, connected: 0, posts: 0, views: 0, likes: 0,
                               comments: 0, shares: 0, posts24h: 0, views24h: 0,
                               avgViews: 0, lastSyncedAt: nil)

    enum CodingKeys: String, CodingKey {
        case accounts, connected, posts, views, likes, comments, shares, posts24h, views24h, avgViews, lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = c.flexInt(.accounts)
        connected = c.flexInt(.connected)
        posts = c.flexInt(.posts)
        views = c.flexInt64(.views)
        likes = c.flexInt64(.likes)
        comments = c.flexInt64(.comments)
        shares = c.flexInt64(.shares)
        posts24h = c.flexInt(.posts24h)
        views24h = c.flexInt64(.views24h)
        avgViews = c.flexInt64(.avgViews)
        lastSyncedAt = c.flexStringOrNil(.lastSyncedAt)
    }

    init(accounts: Int, connected: Int, posts: Int, views: Int64, likes: Int64,
         comments: Int64, shares: Int64, posts24h: Int, views24h: Int64,
         avgViews: Int64, lastSyncedAt: String?) {
        self.accounts = accounts
        self.connected = connected
        self.posts = posts
        self.views = views
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.posts24h = posts24h
        self.views24h = views24h
        self.avgViews = avgViews
        self.lastSyncedAt = lastSyncedAt
    }

    static func make(from accounts: [Account]) -> Summary {
        let posts = accounts.reduce(0) { $0 + $1.posts }
        let views = accounts.reduce(Int64(0)) { $0 + $1.views }
        let likes = accounts.reduce(Int64(0)) { $0 + $1.videoLikes }
        let comments = accounts.reduce(Int64(0)) { $0 + $1.comments }
        let shares = accounts.reduce(Int64(0)) { $0 + $1.shares }
        let posts24h = accounts.reduce(0) { $0 + $1.posts24h }
        let views24h = accounts.reduce(Int64(0)) { $0 + $1.views24h }
        let synced = accounts.compactMap { $0.lastSyncedAt }.sorted().last
        return Summary(
            accounts: accounts.count,
            connected: accounts.filter { $0.connected }.count,
            posts: posts,
            views: views,
            likes: likes,
            comments: comments,
            shares: shares,
            posts24h: posts24h,
            views24h: views24h,
            avgViews: posts > 0 ? views / Int64(posts) : 0,
            lastSyncedAt: synced
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
