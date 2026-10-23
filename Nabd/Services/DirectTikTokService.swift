import Foundation

enum DirectTikTokError: LocalizedError {
    case invalidHandle
    case notFound
    case blocked
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidHandle:
            return "رابط الحساب غير صالح"
        case .notFound:
            return "لم نجد هذا الحساب العلني على TikTok"
        case .blocked:
            return "TikTok مشغول مؤقتاً — ستُحدَّث الإحصاءات تلقائياً"
        case .badResponse:
            return "TikTok لم يُرجع إحصاءات جديدة — ستُحدَّث تلقائياً"
        }
    }

    var isTemporary: Bool {
        switch self {
        case .blocked, .badResponse:
            return true
        case .invalidHandle, .notFound:
            return false
        }
    }
}

struct DirectTikTokResult {
    var account: Account
    var videos: [VideoItem]
}

/// يقرأ إحصاءات TikTok العامة مباشرة من الموقع بدون خادم وبدون تسجيل دخول.
/// - الملف الشخصي: المتابعون، الإعجابات، عدد المنشورات.
/// - صفحة embed: آخر المنشورات مع عدد مشاهدات كل منشور.
/// - وقت النشر يُستخرج من معرّف الفيديو (Snowflake ID).
///
/// TikTok يفضل أن يبدأ الطلب بزيارة الصفحة الرئيسية حتى يحصل التطبيق على
/// كوكيز ttwid. نستخدم مخزن كوكيز URLSession نفسه، ونعيد تسخينه عند الحاجة،
/// ثم نجرّب دومينات بديلة إذا رفض أحد الدومينات الطلب.
final class DirectTikTokService {
    static let shared = DirectTikTokService()

    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private let daySeconds = 24 * 60 * 60
    private let weekSeconds = 7 * 24 * 60 * 60
    private let cookieTTL: TimeInterval = 45 * 60
    private let minimumRequestGap: TimeInterval = 0.55

    private let session: URLSession
    private var cookiesAt = Date.distantPast
    private var lastRequestAt = Date.distantPast

    private let homeURL = "https://www.tiktok.com/?lang=en"
    private let profileHosts = ["www.tiktok.com", "us.tiktok.com"]

    private enum PageKind: Equatable {
        case home
        case profile
        case embed

        var accept: String {
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }

        var fetchDestination: String {
            switch self {
            case .embed: return "iframe"
            default: return "document"
            }
        }

        var fetchSite: String {
            switch self {
            case .home: return "none"
            default: return "same-origin"
            }
        }
    }

    private init() {
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 32
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func fetch(handle rawHandle: String, knownPosts: Int = 0, createdAt: String? = nil) async throws -> DirectTikTokResult {
        let handle = rawHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !handle.isEmpty else { throw DirectTikTokError.invalidHandle }

        var lastError: DirectTikTokError = .blocked
        var partial: DirectTikTokResult?
        for attempt in 0..<2 {
            do {
                let result = try await fetchOnce(
                    handle: handle,
                    knownPosts: knownPosts,
                    createdAt: createdAt,
                    refreshedCookies: attempt > 0
                )
                if !result.videos.isEmpty || attempt == 1 {
                    return result
                }
                // وصلنا لبيانات البروفايل فقط. نعيد المحاولة بكوكيز جديدة قبل الاعتماد عليها.
                partial = result
                lastError = .blocked
            } catch let error as DirectTikTokError {
                if !error.isTemporary {
                    if let partial { return partial }
                    throw error
                }
                lastError = error
            } catch {
                lastError = .blocked
            }

            if attempt == 0 {
                // مهلة قصيرة ثم نعيد المحاولة بكوكيز جديدة.
                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
        }
        if let partial { return partial }
        throw lastError
    }

    private func fetchOnce(
        handle: String,
        knownPosts: Int,
        createdAt: String?,
        refreshedCookies: Bool
    ) async throws -> DirectTikTokResult {
        await warmCookiesIfNeeded(force: refreshedCookies)

        var profileInfo: [String: Any]?
        var profileNotFound = false
        var profileBlocked = false
        let profiles = refreshedCookies ? profileHosts : [profileHosts[0]]

        for host in profiles {
            do {
                let html = try await loadHTML(
                    "https://\(host)/@\(handle)?lang=en",
                    kind: .profile
                )
                profileInfo = try parseProfile(html)
                break
            } catch let error as DirectTikTokError {
                if case .notFound = error {
                    profileNotFound = true
                    break
                }
                profileBlocked = true
            } catch {
                profileBlocked = true
            }
        }

        var embedData: [String: Any]?
        var embedNotFound = false
        var embedBlocked = false
        let hosts = refreshedCookies
            ? ["us.tiktok.com", "www.tiktokv.com", "www.tiktok.com"]
            : ["www.tiktok.com", "t.tiktok.com"]

        for host in hosts {
            do {
                let html = try await loadHTML(
                    "https://\(host)/embed/@\(handle)",
                    kind: .embed
                )
                if let parsed = parseEmbed(html) {
                    embedData = parsed
                    break
                }
                embedBlocked = true
            } catch let error as DirectTikTokError {
                if case .notFound = error {
                    embedNotFound = true
                } else {
                    embedBlocked = true
                }
            } catch {
                embedBlocked = true
            }
        }

        if embedData == nil && profileInfo == nil {
            if profileNotFound && embedNotFound && !profileBlocked && !embedBlocked {
                throw DirectTikTokError.notFound
            }
            throw DirectTikTokError.blocked
        }

        return try makeResult(
            handle: handle,
            knownPosts: knownPosts,
            createdAt: createdAt,
            profileInfo: profileInfo,
            embedData: embedData
        )
    }

    private func makeResult(
        handle: String,
        knownPosts: Int,
        createdAt: String?,
        profileInfo: [String: Any]?,
        embedData: [String: Any]?
    ) throws -> DirectTikTokResult {
        let embedUser = embedData?["userInfo"] as? [String: Any] ?? [:]
        let profileUser = profileInfo?["user"] as? [String: Any] ?? [:]
        let profileStats = profileInfo?["stats"] as? [String: Any] ?? [:]
        // statsV2 يحمل الأرقام الكاملة كنصوص (مثال: 96,411,082 بدل 96,400,000).
        let profileStatsV2 = profileInfo?["statsV2"] as? [String: Any] ?? [:]

        let embedHandle = firstString(embedUser["uniqueId"]) ?? ""
        let profileHandle = firstString(profileUser["uniqueId"]) ?? ""
        if embedHandle.isEmpty && profileHandle.isEmpty {
            throw DirectTikTokError.notFound
        }

        let displayName = firstString(
            profileUser["nickname"], embedUser["nickname"], handle
        ) ?? handle
        let avatar = firstString(
            profileUser["avatarLarger"], profileUser["avatarMedium"], profileUser["avatarThumb"],
            embedUser["avatarThumbUrl"]
        )
        let verified = firstBool(profileUser["verified"], embedUser["verified"])
        let followers = firstInt64(
            profileStatsV2["followerCount"], profileStats["followerCount"], embedUser["followerCount"]
        ) ?? 0
        let following = firstInt64(
            profileStatsV2["followingCount"], profileStats["followingCount"], embedUser["followingCount"]
        ) ?? 0
        let heartCount = firstInt64(
            profileStatsV2["heartCount"], profileStatsV2["heart"],
            profileStats["heartCount"], profileStats["heart"], embedUser["heartCount"]
        ) ?? 0
        let totalPosts = firstInt(
            profileStatsV2["videoCount"], profileStats["videoCount"]
        ) ?? (knownPosts > 0 ? knownPosts : 0)

        let rawVideos = embedData?["videoList"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        var videos: [VideoItem] = []
        for raw in rawVideos {
            guard let id = stringValue(raw["id"]), !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            let viewCount = firstInt64(raw["playCount"]) ?? 0
            videos.append(VideoItem(
                id: id,
                title: stringValue(raw["desc"]) ?? "",
                coverUrl: firstString(raw["coverUrl"], raw["originCoverUrl"], raw["dynamicCoverUrl"]),
                shareUrl: "https://www.tiktok.com/@\(handle)/video/\(id)",
                duration: 0,
                createTime: Self.createTime(from: id),
                views: viewCount,
                likes: 0,
                comments: 0,
                shares: 0,
                // TikTok يعرض مشاهدات الفيديو العامة مقرّبة فوق ١٠ آلاف.
                viewsExact: viewCount < 10_000
            ))
        }
        videos.sort { $0.createTime > $1.createTime }

        let now = Int(Date().timeIntervalSince1970)
        let cutoff24h = now - daySeconds
        let cutoff7d = now - weekSeconds
        let recent = videos.filter { $0.createTime >= cutoff24h }
        let weekly = videos.filter { $0.createTime >= cutoff7d }
        let views24h = recent.reduce(Int64(0)) { $0 + $1.views }
        let weeklyViews = weekly.reduce(Int64(0)) { $0 + $1.views }
        let totalViews = videos.reduce(Int64(0)) { $0 + $1.views }

        let allPostsLoaded = videos.isEmpty
            ? totalPosts == 0
            : (totalPosts > 0 && videos.count >= totalPosts)
        let hasValidTimes = videos.allSatisfy { $0.createTime > 0 }
        let oldestFetched = videos.last?.createTime ?? 0
        let dailyComplete = windowComplete(
            videos: videos,
            totalPosts: totalPosts,
            allPostsLoaded: allPostsLoaded,
            hasValidTimes: hasValidTimes,
            oldestFetched: oldestFetched,
            cutoff: cutoff24h
        )
        let weeklyComplete = windowComplete(
            videos: videos,
            totalPosts: totalPosts,
            allPostsLoaded: allPostsLoaded,
            hasValidTimes: hasValidTimes,
            oldestFetched: oldestFetched,
            cutoff: cutoff7d
        )
        let viewsExact = videos.isEmpty ? totalPosts == 0 : videos.allSatisfy { $0.viewsExact }
        let dailyViewsExact = dailyComplete && recent.allSatisfy { $0.viewsExact }
        let weeklyViewsExact = weeklyComplete && weekly.allSatisfy { $0.viewsExact }

        let account = Account(
            id: "direct-\(handle)",
            handle: handle,
            displayName: displayName,
            url: "https://www.tiktok.com/@\(handle)",
            avatarUrl: avatar,
            isVerified: verified,
            followers: followers,
            following: following,
            likes: abs(heartCount),
            posts: totalPosts > 0 ? totalPosts : videos.count,
            views: totalViews,
            videoLikes: 0,
            comments: 0,
            shares: 0,
            fetchedVideos: videos.count,
            posts24h: recent.count,
            views24h: views24h,
            posts7d: weekly.count,
            weeklyViews: weeklyViews,
            avgViews: videos.isEmpty ? 0 : totalViews / Int64(videos.count),
            coverage: totalPosts > 0 ? min(1, Double(videos.count) / Double(totalPosts)) : (videos.isEmpty ? 0 : 1),
            connected: false,
            publicStats: true,
            viewsExact: viewsExact,
            dailyComplete: dailyComplete,
            dailyViewsExact: dailyViewsExact,
            weeklyComplete: weeklyComplete,
            weeklyViewsExact: weeklyViewsExact,
            allPostsLoaded: allPostsLoaded,
            status: "public",
            error: nil,
            lastSyncedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            createdAt: createdAt ?? ISO8601DateFormatter.nabd.string(from: Date())
        )

        return DirectTikTokResult(account: account, videos: videos)
    }

    /// نافذة ٢٤ ساعة/٧ أيام مكتملة إذا كانت آخر ١٠ منشورات تغطيها بالكامل.
    /// إن كان عدد المنشورات المحمّلة أقل من ١٠، فهي كل المنشورات العامة.
    private func windowComplete(
        videos: [VideoItem],
        totalPosts: Int,
        allPostsLoaded: Bool,
        hasValidTimes: Bool,
        oldestFetched: Int,
        cutoff: Int
    ) -> Bool {
        if videos.isEmpty { return totalPosts == 0 }
        if allPostsLoaded { return true }
        // إذا كانت أقدم منشورات محمّلة أقدم من بداية النافذة، فالنافذة مغطاة بالكامل
        // حتى لو لم نحمّل كل منشورات الحساب.
        if hasValidTimes && oldestFetched < cutoff { return true }
        // عدد المنشورات الكلي غير معروف، لكن كل ما ظهر علناً محمّل.
        if totalPosts == 0 && videos.count < 10 { return true }
        return false
    }

    // MARK: - الشبكة والكوكيز

    private func warmCookiesIfNeeded(force: Bool = false) async {
        if !force, Date().timeIntervalSince(cookiesAt) < cookieTTL {
            return
        }

        if force {
            clearTikTokCookies()
        }

        // زيارة الصفحة الرئيسية تمنح ttwid وغيره من كوكيز الحماية.
        _ = try? await loadHTML(homeURL, kind: .home, allowFailure: true)
        cookiesAt = Date()
    }

    private func clearTikTokCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains("tiktok") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    @discardableResult
    private func loadHTML(
        _ urlString: String,
        kind: PageKind,
        allowFailure: Bool = false
    ) async throws -> String {
        guard let url = URL(string: urlString) else { throw DirectTikTokError.invalidHandle }

        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumRequestGap {
            let delay = UInt64((minimumRequestGap - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        lastRequestAt = Date()

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 25
        )
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(kind.accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue(kind.fetchDestination, forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue(kind.fetchSite, forHTTPHeaderField: "Sec-Fetch-Site")
        if kind != .home {
            request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DirectTikTokError.badResponse
            }

            switch http.statusCode {
            case 200..<300:
                let html = String(decoding: data, as: UTF8.self)
                if data.count < 80 || html.contains("overload-protect triggered") {
                    if allowFailure { return "" }
                    throw DirectTikTokError.blocked
                }
                return html
            case 404:
                if allowFailure { return "" }
                throw DirectTikTokError.notFound
            default:
                if allowFailure { return "" }
                throw DirectTikTokError.blocked
            }
        } catch let error as DirectTikTokError {
            if allowFailure { return "" }
            throw error
        } catch {
            if allowFailure { return "" }
            throw DirectTikTokError.blocked
        }
    }

    // MARK: - التحليل

    private func parseProfile(_ html: String) throws -> [String: Any] {
        guard let json = scriptJSON(in: html, id: "__UNIVERSAL_DATA_FOR_REHYDRATION__"),
              let scope = json["__DEFAULT_SCOPE__"] as? [String: Any],
              let detail = scope["webapp.user-detail"] as? [String: Any] else {
            throw DirectTikTokError.blocked
        }
        let statusCode = firstInt(detail["statusCode"]) ?? 0
        if statusCode != 0 { throw DirectTikTokError.notFound }
        guard let info = detail["userInfo"] as? [String: Any],
              let user = info["user"] as? [String: Any],
              !(firstString(user["uniqueId"]) ?? "").isEmpty else {
            throw DirectTikTokError.notFound
        }
        return info
    }

    private func parseEmbed(_ html: String) -> [String: Any]? {
        guard let state = frontityState(in: html),
              let source = state["source"] as? [String: Any],
              let data = source["data"] as? [String: Any] else { return nil }
        return data.values
            .compactMap { $0 as? [String: Any] }
            .first { $0["userInfo"] != nil }
    }

    private func scriptJSON(in html: String, id: String) -> [String: Any]? {
        let marker = "<script id=\"\(id)\" type=\"application/json\">"
        if let start = html.range(of: marker),
           let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) {
            let raw = String(html[start.upperBound..<end.lowerBound])
            if let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] {
                return object
            }
        }

        // بعض النسخ تغيّر ترتيب خصائص وسم script.
        let escaped = NSRegularExpression.escapedPattern(for: id)
        let pattern = #"<script[^>]*id="\#(escaped)"[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let text = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: text.length)),
              match.numberOfRanges > 1 else { return nil }
        let raw = text.substring(with: match.range(at: 1))
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    private func frontityState(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type="application/json"[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let text = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let raw = text.substring(with: match.range(at: 1))
            guard raw.contains("\"frontity\"") else { continue }
            if let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    // MARK: - أدوات

    private func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let text = stringValue(value), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    private func firstInt64(_ values: Any?...) -> Int64? {
        for value in values {
            if let number = value as? NSNumber { return number.int64Value }
            if let text = value as? String {
                let normalized = text
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int64(normalized) { return parsed }
            }
        }
        return nil
    }

    private func firstInt(_ values: Any?...) -> Int? {
        for value in values {
            if let number = value as? NSNumber { return number.intValue }
            if let text = value as? String {
                let normalized = text
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int(normalized) { return parsed }
            }
        }
        return nil
    }

    private func firstBool(_ values: Any?...) -> Bool {
        for value in values {
            if let flag = value as? Bool { return flag }
            if let number = value as? NSNumber { return number.boolValue }
        }
        return false
    }

    /// TikTok video ids are snowflakes: the high 32 bits are the Unix timestamp.
    static func createTime(from id: String) -> Int {
        guard let value = UInt64(id) else { return 0 }
        return Int(value >> 32)
    }
}
