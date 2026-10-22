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
            return "الحساب غير موجود أو خاص على TikTok"
        case .blocked:
            return "تعذّر جلب البيانات العامة من TikTok الآن. أعد المحاولة بعد قليل"
        case .badResponse:
            return "رد غير متوقع من TikTok"
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
final class DirectTikTokService {
    static let shared = DirectTikTokService()

    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private let daySeconds = 24 * 60 * 60
    private var warmedCookies = false
    private var lastRequestAt = Date.distantPast

    private init() {}

    func fetch(handle rawHandle: String, knownPosts: Int = 0, createdAt: String? = nil) async throws -> DirectTikTokResult {
        let handle = rawHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !handle.isEmpty else { throw DirectTikTokError.invalidHandle }

        do {
            return try await fetchOnce(handle: handle, knownPosts: knownPosts, createdAt: createdAt)
        } catch DirectTikTokError.blocked {
            // محاولة أخيرة بعد تحديث الكوكيز
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            warmedCookies = false
            return try await fetchOnce(handle: handle, knownPosts: knownPosts, createdAt: createdAt)
        }
    }

    private func fetchOnce(handle: String, knownPosts: Int, createdAt: String?) async throws -> DirectTikTokResult {
        await warmCookiesIfNeeded()

        var profileInfo: [String: Any]?
        var profileBlocked = false
        do {
            let html = try await loadHTML("https://www.tiktok.com/@\(handle)?lang=en")
            profileInfo = try parseProfile(html)
        } catch DirectTikTokError.notFound {
            throw DirectTikTokError.notFound
        } catch {
            profileBlocked = true
        }

        guard let embedHTML = try? await loadHTML("https://www.tiktok.com/embed/@\(handle)"),
              let embedData = parseEmbed(embedHTML) else {
            if profileBlocked { throw DirectTikTokError.blocked }
            throw DirectTikTokError.badResponse
        }

        let embedUser = embedData["userInfo"] as? [String: Any] ?? [:]
        if profileInfo == nil && (embedUser["uniqueId"] as? String ?? "").isEmpty {
            throw DirectTikTokError.notFound
        }

        let profileUser = profileInfo?["user"] as? [String: Any] ?? [:]
        let profileStats = profileInfo?["stats"] as? [String: Any] ?? [:]

        let displayName = firstString(
            profileUser["nickname"], embedUser["nickname"], handle
        )
        let avatar = firstString(
            profileUser["avatarLarger"], profileUser["avatarMedium"], profileUser["avatarThumb"],
            embedUser["avatarThumbUrl"]
        )
        let verified = firstBool(profileUser["verified"], embedUser["verified"])
        let followers = firstInt64(profileStats["followerCount"], embedUser["followerCount"]) ?? 0
        let following = firstInt64(profileStats["followingCount"], embedUser["followingCount"]) ?? 0
        let heartCount = firstInt64(profileStats["heartCount"], embedUser["heartCount"]) ?? 0
        let totalPosts = firstInt(profileStats["videoCount"]) ?? (knownPosts > 0 ? knownPosts : 0)

        let rawVideos = embedData["videoList"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        var videos: [VideoItem] = []
        for raw in rawVideos {
            guard let id = stringValue(raw["id"]), !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            videos.append(VideoItem(
                id: id,
                title: stringValue(raw["desc"]) ?? "",
                coverUrl: firstString(raw["coverUrl"], raw["originCoverUrl"], raw["dynamicCoverUrl"]),
                shareUrl: "https://www.tiktok.com/@\(handle)/video/\(id)",
                duration: 0,
                createTime: Self.createTime(from: id),
                views: firstInt64(raw["playCount"]) ?? 0,
                likes: 0,
                comments: 0,
                shares: 0
            ))
        }
        videos.sort { $0.createTime > $1.createTime }

        let cutoff = Int(Date().timeIntervalSince1970) - daySeconds
        let recent = videos.filter { $0.createTime >= cutoff }
        let views24h = recent.reduce(Int64(0)) { $0 + $1.views }
        let totalViews = videos.reduce(Int64(0)) { $0 + $1.views }

        let account = Account(
            id: "direct-\(handle)",
            handle: handle,
            displayName: displayName ?? handle,
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
            avgViews: videos.isEmpty ? 0 : totalViews / Int64(videos.count),
            coverage: totalPosts > 0 ? min(1, Double(videos.count) / Double(totalPosts)) : (videos.isEmpty ? 0 : 1),
            connected: false,
            publicStats: true,
            status: "public",
            error: nil,
            lastSyncedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            createdAt: createdAt ?? ISO8601DateFormatter.nabd.string(from: Date())
        )

        return DirectTikTokResult(account: account, videos: videos)
    }

    // MARK: - الشبكة

    private func warmCookiesIfNeeded() async {
        guard !warmedCookies else { return }
        warmedCookies = true
        _ = try? await loadHTML("https://www.tiktok.com/", allowFailure: true)
    }

    private func loadHTML(_ urlString: String, allowFailure: Bool = false) async throws -> String {
        guard let url = URL(string: urlString) else { throw DirectTikTokError.invalidHandle }
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < 0.65 {
            try? await Task.sleep(nanoseconds: UInt64((0.65 - elapsed) * 1_000_000_000))
        }
        lastRequestAt = Date()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 400 || status == 404 { throw DirectTikTokError.notFound }
            if status >= 400 {
                if allowFailure { return "" }
                throw DirectTikTokError.blocked
            }
            return String(decoding: data, as: UTF8.self)
        } catch let error as DirectTikTokError {
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
        guard let info = detail["userInfo"] as? [String: Any] else {
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
        guard let start = html.range(of: marker),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else {
            return nil
        }
        let raw = String(html[start.upperBound..<end.lowerBound])
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
            if let text = value as? String, let parsed = Int64(text) { return parsed }
        }
        return nil
    }

    private func firstInt(_ values: Any?...) -> Int? {
        for value in values {
            if let number = value as? NSNumber { return number.intValue }
            if let text = value as? String, let parsed = Int(text) { return parsed }
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
