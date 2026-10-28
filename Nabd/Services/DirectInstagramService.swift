import Foundation

enum DirectInstagramError: LocalizedError {
    case invalidLink
    case notFound
    case blocked
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "لم نتعرف على رابط الحساب. استخدم instagram.com/username أو @username أو رابط مشاركة الحساب"
        case .notFound:
            return "لم نجد هذا الحساب العلني على إنستغرام"
        case .blocked:
            return "إنستغرام مشغول مؤقتاً — ستُحدَّث الإحصاءات تلقائياً"
        case .badResponse:
            return "إنستغرام لم يُرجع بيانات جديدة — ستُحدَّث تلقائياً"
        }
    }

    var isTemporary: Bool {
        switch self {
        case .blocked, .badResponse:
            return true
        case .invalidLink, .notFound:
            return false
        }
    }
}

struct DirectInstagramResult {
    var account: Account
    var videos: [VideoItem]
}

/// مرجع حساب إنستغرام بعد تطبيع الرابط.
struct InstagramProfileReference {
    var inputURL: URL
    var handle: String
    var canonicalURL: String
    /// روابط المشاركة المختصرة تحتاج متابعة التحويل لمعرفة اسم الحساب.
    var needsResolution: Bool = false
}

/// يحلّل روابط إنستغرام العامة: instagram.com/username، @username،
/// الروابط التي تحمل مساراً إضافياً مثل /reel/ أو /stories/، وروابط المشاركة.
enum InstagramLinkParser {
    private static let reservedPaths: Set<String> = [
        "p", "reel", "reels", "tv", "stories", "explore", "accounts", "direct",
        "about", "legal", "developer", "developers", "api", "help", "press",
        "privacy", "terms", "directory", "challenge", "emails", "session",
        "web", "graphql", "oauth", "share", "s", "static", "cdn", "ar",
    ]

    static func reference(from raw: String) -> InstagramProfileReference? {
        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let lower = input.lowercased()
        if lower.hasPrefix("www.instagram.com") || lower.hasPrefix("instagram.com") ||
            lower.hasPrefix("m.instagram.com") || lower.hasPrefix("instagr.am") ||
            lower.hasPrefix("www.instagr.am") {
            input = "https://" + input
        } else if input.hasPrefix("@") {
            return referenceForHandle(String(input.dropFirst()))
        } else if !input.contains("://"), !input.contains("/") {
            return referenceForHandle(input)
        } else if !input.contains("://") {
            input = "https://www.instagram.com/" + input
        }

        guard let components = URLComponents(string: input),
              let host = components.host?.lowercased(),
              isInstagramHost(host) else {
            return nil
        }

        let path = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = path.first, !first.isEmpty else { return nil }

        // روابط المشاركة الجديدة: instagram.com/share/...
        if first.lowercased() == "share" {
            return unresolvedReference(
                url: components.url?.absoluteString ?? input,
                code: path.dropFirst().joined(separator: "_"),
                prefix: "share"
            )
        }

        // قصص الحساب: instagram.com/stories/username/...
        if first.lowercased() == "stories", path.count >= 2 {
            return referenceForHandle(path[1])
        }

        // منشور أو ريل بلا اسم مستخدم في الرابط:
        // instagram.com/p/CODE أو /reel/CODE — نحتاج فتح الصفحة لمعرفة الحساب.
        if ["p", "reel", "tv"].contains(first.lowercased()) {
            guard path.count >= 2 else { return nil }
            return unresolvedReference(
                url: components.url?.absoluteString ?? input,
                code: path[1],
                prefix: first.lowercased()
            )
        }

        // منشور أو ريل داخل حساب: instagram.com/username/reel/... أو /p/...
        if !reservedPaths.contains(first.lowercased()) {
            return referenceForHandle(first)
        }

        return nil
    }

    private static func isInstagramHost(_ host: String) -> Bool {
        host == "instagram.com" ||
        host.hasSuffix(".instagram.com") ||
        host == "instagr.am" ||
        host == "www.instagr.am"
    }

    private static func unresolvedReference(
        url: String,
        code: String,
        prefix: String
    ) -> InstagramProfileReference? {
        guard !code.isEmpty, let inputURL = URL(string: url) else { return nil }
        var safe = code
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
        if safe.isEmpty { safe = stableCode(for: code) }
        guard !safe.isEmpty else { return nil }
        let handle = String("\(prefix)_\(safe)".prefix(80))
        return InstagramProfileReference(
            inputURL: inputURL,
            handle: handle,
            canonicalURL: url,
            needsResolution: true
        )
    }

    private static func stableCode(for value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    static func referenceForHandle(_ raw: String) -> InstagramProfileReference? {
        var handle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while handle.hasPrefix("@") { handle.removeFirst() }
        while handle.hasSuffix("/") { handle.removeLast() }
        guard isValidHandle(handle) else { return nil }
        let lowered = handle.lowercased()
        guard !reservedPaths.contains(lowered) else { return nil }
        return InstagramProfileReference(
            inputURL: URL(string: "https://www.instagram.com/\(lowered)/")!,
            handle: lowered,
            canonicalURL: "https://www.instagram.com/\(lowered)/",
            needsResolution: false
        )
    }

    static func isValidHandle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.count <= 30 else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9._]+$"#, options: .regularExpression) != nil
    }
}

/// يقرأ حساب إنستغرام العلني مباشرة دون تسجيل دخول.
/// - الملف الشخصي عبر `web_profile_info` (نفس واجهة الويب العامة).
/// - آخر ١٢ منشوراً تقريباً مع المشاهدات والإعجابات والتعليقات.
/// - احتياط: وسوم og في صفحة الحساب عند حجب الواجهة.
final class DirectInstagramService {
    static let shared = DirectInstagramService()

    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private let appID = "936619743392459"
    private let daySeconds = 24 * 60 * 60
    private let weekSeconds = 7 * 24 * 60 * 60
    private let minimumRequestGap: TimeInterval = 0.5

    private let session: URLSession
    private var lastRequestAt = Date.distantPast

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 32
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func fetch(handle rawHandle: String, url: String? = nil, createdAt: String? = nil) async throws -> DirectInstagramResult {
        let rawLink = (url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? url : nil) ?? rawHandle
        guard var reference = InstagramLinkParser.reference(from: rawLink)
            ?? InstagramLinkParser.reference(from: rawHandle) else {
            throw DirectInstagramError.invalidLink
        }

        if reference.needsResolution {
            if let resolved = try? await resolve(reference) {
                reference = resolved
            }
        }

        // ١) واجهة الويب العامة: أدق أرقام وأحدث المنشورات.
        if let apiResult = try? await fetchAPI(reference: reference, createdAt: createdAt) {
            return apiResult
        }

        // ٢) صفحة الحساب ووسوم og: أرقام الملف فقط.
        if let htmlResult = try? await fetchHTML(reference: reference, createdAt: createdAt) {
            return htmlResult
        }

        throw DirectInstagramError.blocked
    }

    // MARK: - حل روابط المشاركة

    private func resolve(_ reference: InstagramProfileReference) async throws -> InstagramProfileReference {
        let page = try await load(reference.inputURL)
        let candidates = [page.finalURL.absoluteString, metaContent(in: page.html, property: "og:url") ?? ""]
        for candidate in candidates where !candidate.isEmpty {
            if let resolved = InstagramLinkParser.reference(from: candidate), !resolved.needsResolution {
                return resolved
            }
        }
        // روابط المنشور والريل لا تحمل اسم الحساب، لكن صفحتها تعرضه في
        // og:title أو في بيانات JSON المدمجة.
        let title = metaContent(in: page.html, property: "og:title") ?? ""
        if let handle = referencedHandle(from: title) ?? jsonUsername(in: page.html),
           let resolved = InstagramLinkParser.referenceForHandle(handle) {
            return resolved
        }
        return reference
    }

    /// يقرأ `"username":"..."` من بيانات الصفحة المدمجة.
    private func jsonUsername(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #""username"\s*:\s*"([A-Za-z0-9._]+)""#,
            options: [.caseInsensitive]
        ) else { return nil }
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    // MARK: - واجهة الويب

    private func fetchAPI(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        guard let url = URL(string:
            "https://www.instagram.com/api/v1/users/web_profile_info/?username=\(reference.handle)"
        ) else { throw DirectInstagramError.invalidLink }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(appID, forHTTPHeaderField: "x-ig-app-id")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://www.instagram.com/\(reference.handle)/", forHTTPHeaderField: "Referer")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw DirectInstagramError.badResponse }
        if http.statusCode == 404 { throw DirectInstagramError.notFound }
        guard (200..<300).contains(http.statusCode), data.count > 80 else {
            throw DirectInstagramError.blocked
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = root["data"] as? [String: Any],
              let user = dataObject["user"] as? [String: Any],
              !(stringValue(user["username"]) ?? "").isEmpty else {
            throw DirectInstagramError.notFound
        }
        return try makeResult(
            user: user,
            reference: reference,
            createdAt: createdAt,
            profileExact: true
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumRequestGap {
            let delay = UInt64((minimumRequestGap - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        lastRequestAt = Date()
        do {
            return try await session.data(for: request)
        } catch {
            throw DirectInstagramError.blocked
        }
    }

    // MARK: - احتياط HTML

    private func fetchHTML(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        let page = try await load(reference.inputURL)
        let html = page.html
        if html.contains("Sorry, this page isn't available") ||
            html.contains("الصفحة غير متوفرة") ||
            html.contains("Page Not Found") {
            throw DirectInstagramError.notFound
        }

        if let user = embeddedUser(in: html) {
            return try makeResult(
                user: user,
                reference: reference,
                createdAt: createdAt,
                profileExact: true
            )
        }

        let description = metaContent(in: html, property: "og:description") ?? ""
        let title = metaContent(in: html, property: "og:title") ?? ""
        let image = metaContent(in: html, property: "og:image") ?? ""
        let profileURL = metaContent(in: html, property: "og:url") ?? reference.canonicalURL

        let handle = referencedHandle(from: title) ?? reference.handle
        guard !description.isEmpty || !title.isEmpty else {
            throw DirectInstagramError.blocked
        }

        let followers = humanCount(in: description, markers: ["followers", "follower", "متابع"])
        let following = humanCount(in: description, markers: ["following", "يتابع"])
        let posts = humanCount(in: description, markers: ["posts", "post", "منشور"])
        let displayName = cleanTitle(title, handle: handle)

        let account = Account(
            id: "direct-instagram-\(handle.lowercased())",
            platform: .instagram,
            handle: handle,
            displayName: displayName,
            url: profileURL.isEmpty ? reference.canonicalURL : profileURL,
            avatarUrl: image.isEmpty ? nil : decodeHTMLEntities(image),
            isVerified: title.contains("Verified"),
            followers: followers,
            following: following,
            likes: 0,
            posts: Int(posts),
            postsCountExact: posts > 0,
            views: 0,
            videoLikes: 0,
            comments: 0,
            shares: 0,
            fetchedVideos: 0,
            posts24h: 0,
            views24h: 0,
            likes24h: 0,
            posts7d: 0,
            weeklyViews: 0,
            likes7d: 0,
            avgViews: 0,
            coverage: 0,
            connected: false,
            publicStats: true,
            profileExact: false,
            viewsExact: false,
            dailyComplete: false,
            dailyViewsExact: false,
            weeklyComplete: false,
            weeklyViewsExact: false,
            allPostsLoaded: false,
            status: "public",
            error: nil,
            lastSyncedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            createdAt: createdAt ?? ISO8601DateFormatter.nabd.string(from: Date())
        )
        return DirectInstagramResult(account: account, videos: [])
    }

    private func load(_ url: URL) async throws -> (html: String, finalURL: URL) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw DirectInstagramError.badResponse }
        let html = String(decoding: data, as: UTF8.self)
        let finalURL = http.url ?? url

        switch http.statusCode {
        case 200..<300:
            guard data.count > 150 else { throw DirectInstagramError.badResponse }
            return (html, finalURL)
        case 404, 410:
            throw DirectInstagramError.notFound
        case 429, 500..<600:
            throw DirectInstagramError.blocked
        default:
            throw DirectInstagramError.badResponse
        }
    }

    // MARK: - بناء النتيجة

    private func makeResult(
        user: [String: Any],
        reference: InstagramProfileReference,
        createdAt: String?,
        profileExact: Bool
    ) throws -> DirectInstagramResult {
        let handle = (stringValue(user["username"]) ?? reference.handle).lowercased()
        guard !handle.isEmpty else { throw DirectInstagramError.notFound }

        let displayName = firstString(
            user["full_name"],
            user["fullName"],
            handle
        ) ?? handle
        let avatar = firstString(
            user["profile_pic_url_hd"],
            user["profile_pic_url"],
            user["profilePicUrl"]
        )
        let verified = firstBool(user["is_verified"], user["isVerified"])
        let followers = firstInt64(
            (user["edge_followed_by"] as? [String: Any])?["count"],
            user["follower_count"]
        ) ?? 0
        let following = firstInt64(
            (user["edge_follow"] as? [String: Any])?["count"],
            user["following_count"]
        ) ?? 0

        let media = user["edge_owner_to_timeline_media"] as? [String: Any] ?? [:]
        let totalPosts = firstInt(media["count"]) ?? 0
        let edges = media["edges"] as? [[String: Any]] ?? []

        var seen = Set<String>()
        var videos: [VideoItem] = []
        for edge in edges {
            guard let node = edge["node"] as? [String: Any] else { continue }
            let shortcode = stringValue(node["shortcode"]) ?? ""
            let id = stringValue(node["id"]) ?? shortcode
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)

            let created = firstInt(node["taken_at_timestamp"]) ?? 0
            let isVideo = firstBool(node["is_video"], node["isVideo"])
            let views = isVideo
                ? (firstInt64(node["video_view_count"], node["video_play_count"], node["play_count"]) ?? 0)
                : 0
            let likes = firstInt64(
                (node["edge_liked_by"] as? [String: Any])?["count"],
                (node["edge_media_preview_like"] as? [String: Any])?["count"],
                node["like_count"]
            ) ?? 0
            let comments = firstInt64(
                (node["edge_media_to_comment"] as? [String: Any])?["count"],
                node["comment_count"]
            ) ?? 0
            let caption = firstString(
                captionText(in: node),
                node["caption"]
            ) ?? ""
            let cover = firstString(
                node["thumbnail_src"],
                node["display_url"],
                (node["thumbnail_resources"] as? [[String: Any]])?.last?["src"]
            )
            let shareURL: String
            if shortcode.isEmpty {
                shareURL = "https://www.instagram.com/\(handle)/"
            } else if isVideo {
                shareURL = "https://www.instagram.com/reel/\(shortcode)/"
            } else {
                shareURL = "https://www.instagram.com/p/\(shortcode)/"
            }

            videos.append(VideoItem(
                id: id,
                title: caption,
                coverUrl: cover,
                shareUrl: shareURL,
                duration: 0,
                createTime: created,
                views: views,
                likes: likes,
                comments: comments,
                shares: 0,
                // إنستغرام ينشر مشاهدات الفيديو فقط؛ الصور لا تكشف مشاهدات.
                viewsExact: isVideo
            ))
        }
        videos.sort { $0.createTime > $1.createTime }

        let now = Int(Date().timeIntervalSince1970)
        let cutoff24h = now - daySeconds
        let cutoff7d = now - weekSeconds
        let recent = videos.filter { $0.createTime >= cutoff24h && $0.createTime <= now + 300 }
        let weekly = videos.filter { $0.createTime >= cutoff7d && $0.createTime <= now + 300 }
        let totalViews = videos.reduce(Int64(0)) { $0 + $1.views }
        let views24h = recent.reduce(Int64(0)) { $0 + $1.views }
        let weeklyViews = weekly.reduce(Int64(0)) { $0 + $1.views }
        let likes24h = recent.reduce(Int64(0)) { $0 + $1.likes }
        let likes7d = weekly.reduce(Int64(0)) { $0 + $1.likes }

        let allPostsLoaded = videos.isEmpty
            ? totalPosts == 0
            : (totalPosts > 0 && videos.count >= totalPosts)
        let dailyComplete = windowComplete(
            videos: videos,
            totalPosts: totalPosts,
            allPostsLoaded: allPostsLoaded,
            cutoff: cutoff24h
        )
        let weeklyComplete = windowComplete(
            videos: videos,
            totalPosts: totalPosts,
            allPostsLoaded: allPostsLoaded,
            cutoff: cutoff7d
        )
        let viewsExact = videos.allSatisfy { $0.viewsExact }
        let dailyViewsExact = dailyComplete && recent.allSatisfy { $0.viewsExact }
        let weeklyViewsExact = weeklyComplete && weekly.allSatisfy { $0.viewsExact }

        let account = Account(
            id: "direct-instagram-\(handle)",
            platform: .instagram,
            handle: handle,
            displayName: displayName,
            url: "https://www.instagram.com/\(handle)/",
            avatarUrl: avatar,
            isVerified: verified,
            followers: followers,
            following: following,
            likes: 0,
            posts: totalPosts > 0 ? totalPosts : videos.count,
            postsCountExact: totalPosts > 0,
            views: totalViews,
            videoLikes: videos.reduce(Int64(0)) { $0 + $1.likes },
            comments: videos.reduce(Int64(0)) { $0 + $1.comments },
            shares: 0,
            fetchedVideos: videos.count,
            posts24h: recent.count,
            views24h: views24h,
            likes24h: likes24h,
            posts7d: weekly.count,
            weeklyViews: weeklyViews,
            likes7d: likes7d,
            avgViews: videos.isEmpty ? 0 : totalViews / Int64(videos.count),
            coverage: totalPosts > 0 ? min(1, Double(videos.count) / Double(totalPosts)) : (videos.isEmpty ? 0 : 1),
            connected: false,
            publicStats: true,
            profileExact: profileExact,
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
        return DirectInstagramResult(account: account, videos: videos)
    }

    /// نافذة ٢٤ ساعة/٧ أيام مكتملة إذا كانت المنشورات المحمّلة تغطيها،
    /// أو إذا كانت الصفحة أعادت كل منشورات الحساب.
    private func windowComplete(
        videos: [VideoItem],
        totalPosts: Int,
        allPostsLoaded: Bool,
        cutoff: Int
    ) -> Bool {
        if videos.isEmpty { return totalPosts == 0 }
        if allPostsLoaded { return true }
        let oldest = videos.map(\.createTime).min() ?? 0
        return oldest > 0 && oldest < cutoff
    }

    // MARK: - استخراج JSON من الصفحة

    private func embeddedUser(in html: String) -> [String: Any]? {
        let patterns = [
            #"window\._sharedData\s*=\s*(\{[\s\S]*?\});</script>"#,
            #"window\.__additionalDataLoaded\([^,]+,\s*(\{[\s\S]*?\})\);</script>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html),
                  let data = String(html[range]).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let user = findUser(in: object) else { continue }
            return user
        }
        return nil
    }

    private func findUser(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if dictionary["username"] != nil,
               dictionary["edge_owner_to_timeline_media"] != nil ||
               dictionary["edge_followed_by"] != nil {
                return dictionary
            }
            for value in dictionary.values {
                if let found = findUser(in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findUser(in: value) { return found }
            }
        }
        return nil
    }

    // MARK: - وسوم og والأرقام

    private func captionText(in node: [String: Any]) -> String? {
        guard let caption = node["edge_media_to_caption"] as? [String: Any],
              let edges = caption["edges"] as? [[String: Any]],
              let first = edges.first as? [String: Any],
              let textNode = first["node"] as? [String: Any] else { return nil }
        return textNode["text"] as? String
    }

    private func referencedHandle(from title: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\(@([A-Za-z0-9._]+)\)"#),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return String(title[range]).lowercased()
    }

    private func cleanTitle(_ raw: String, handle: String) -> String {
        var value = decodeHTMLEntities(raw)
        for suffix in [" • Instagram photos and videos", " • Instagram", " (@\(handle))"] {
            if value.hasSuffix(suffix) { value = String(value.dropLast(suffix.count)) }
        }
        if let range = value.range(of: " (@\(handle))") {
            value = String(value[..<range.lowerBound])
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? handle : trimmed
    }

    /// يقرأ «1,234 Followers» أو «١٢٣٤ متابع» ويعيد الرقم.
    private func humanCount(in text: String, markers: [String]) -> Int64 {
        guard !text.isEmpty else { return 0 }
        let normalized = normalizeDigits(text)
            .replacingOccurrences(of: "\u{200f}", with: "")
            .replacingOccurrences(of: "\u{200e}", with: "")
            .replacingOccurrences(of: "\u{066c}", with: ",")
            .replacingOccurrences(of: "٬", with: ",")
        let lower = normalized.lowercased()
        for marker in markers {
            guard let markerRange = lower.range(of: marker) else { continue }
            let prefix = String(lower[..<markerRange.lowerBound])
            guard let numberRange = prefix.range(of: #"([0-9][0-9,\.]*)\s*$"#, options: .regularExpression) else { continue }
            let rawNumber = String(prefix[numberRange])
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(rawNumber) else { continue }
            return Int64(value.rounded())
        }
        return 0
    }

    private func metaContent(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        guard let regex = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*(?:property|name)=["']\#(escaped)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(match.range, in: html) else { return nil }
        let tag = String(html[tagRange])
        guard let contentRegex = try? NSRegularExpression(
            pattern: #"content=["']([^"']*)["']"#,
            options: [.caseInsensitive]
        ) else { return nil }
        guard let contentMatch = contentRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let contentRange = Range(contentMatch.range(at: 1), in: tag) else { return nil }
        return String(tag[contentRange])
    }

    private func decodeHTMLEntities(_ raw: String) -> String {
        FacebookPageParser.decodeHTMLEntities(raw)
    }

    private func normalizeDigits(_ raw: String) -> String {
        let digits: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
        ]
        return String(raw.map { digits[$0] ?? $0 })
    }

    // MARK: - أدوات

    private func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let text = stringValue(value),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
}
