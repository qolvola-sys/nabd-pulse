import Foundation

enum DirectFacebookError: LocalizedError {
    case invalidLink
    case notFound
    case blocked
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "لم نتعرف على رابط الصفحة. استخدم facebook.com/PageName أو facebook.com/profile.php?id=123… أو رابط مشاركة الصفحة"
        case .notFound:
            return "لم نجد هذه الصفحة العلنية على فيسبوك"
        case .blocked:
            return "فيسبوك مشغول مؤقتاً — ستُحدَّث الإحصاءات تلقائياً"
        case .badResponse:
            return "فيسبوك لم يُرجع بيانات جديدة — ستُحدَّث تلقائياً"
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

struct DirectFacebookResult {
    var account: Account
    var videos: [VideoItem]
}

/// مرجع صفحة فيسبوك بعد تطبيع الرابط. نحفظ `handle` كمعرّف ثابت
/// (اسم الصفحة أو رقمها) حتى لا يتكرر الحساب بأشكال روابط مختلفة.
struct FacebookPageReference {
    var inputURL: URL
    var handle: String
    var canonicalURL: String
    var isNumericID: Bool
    /// روابط المشاركة المختصرة أو الروابط العربية تحتاج متابعة التحويل
    /// لمعرفة الصفحة النهائية قبل تثبيت معرّف الحساب.
    var needsResolution: Bool = false
}

/// يحلّل صفحة فيسبوك العامة كما يعرضها فيسبوك للزائر غير المسجّل.
/// نستخدم User-Agent الخاص بـGooglebot لأن فيسبوك يعيد الصفحة الكاملة له،
/// بينما يعيد متصفحاً عادياً إلى شاشة تسجيل الدخول.
enum FacebookPageParser {
    private static let reservedPaths: Set<String> = [
        "login", "login.php", "checkpoint", "recover", "help", "policies", "privacy",
        "terms", "settings", "messages", "notifications", "friends", "bookmarks",
        "watch", "reels", "videos", "photos", "stories", "share", "sharer", "sharer.php",
        "groups", "events", "gaming", "marketplace", "fundraisers", "ads", "business",
        "pages", "people", "profile.php", "pg", "p", "dialog", "plugins", "hashtag",
        "search", "l.php", "ajax", "composer", "notes", "photo.php", "story.php",
        "permalink.php", "share.php", "story_fbid", "reel",
    ]

    // MARK: - تطبيع الروابط

    static func reference(from raw: String) -> FacebookPageReference? {
        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let lower = input.lowercased()
        if lower.hasPrefix("www.facebook.com") ||
            lower.hasPrefix("facebook.com") ||
            lower.hasPrefix("m.facebook.com") ||
            lower.hasPrefix("web.facebook.com") ||
            lower.hasPrefix("mbasic.facebook.com") ||
            lower.hasPrefix("free.facebook.com") ||
            lower.hasPrefix("fb.com") ||
            lower.hasPrefix("www.fb.com") ||
            lower.hasPrefix("fb.me") ||
            lower.hasPrefix("www.fb.me") ||
            lower.hasPrefix("fb.watch") ||
            lower.hasPrefix("www.fb.watch") ||
            lower.hasPrefix("fbwat.ch") {
            input = "https://" + input
        } else if lower.hasPrefix("profile.php") {
            input = "https://www.facebook.com/" + input
        } else if !input.contains("://"), input.contains("/") {
            input = "https://www.facebook.com/" + input
        }

        if !input.contains("://") {
            return referenceForHandle(input)
        }

        guard let components = URLComponents(string: input),
              let host = components.host?.lowercased(),
              isFacebookHost(host) else {
            return nil
        }

        // روابط Messenger تُغلِّف الرابط الأصلي في l.facebook.com/l.php?u=…
        if host == "l.facebook.com" || host == "lm.facebook.com" {
            guard let target = components.queryItems?.first(where: { $0.name == "u" })?.value else {
                return nil
            }
            return reference(from: target)
        }

        let rawPath = components.percentEncodedPath
        let path = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = path.first, !first.isEmpty else { return nil }

        // روابط fb.me وfb.watch المختصرة تُحل عند الجلب.
        if host == "fb.me" || host == "www.fb.me" ||
            host == "fb.watch" || host == "www.fb.watch" || host == "fbwat.ch" {
            return unresolvedReference(
                url: components.url?.absoluteString ?? input,
                code: first,
                prefix: "fbme"
            )
        }

        // روابط المشاركة الجديدة: facebook.com/share/...
        if first.lowercased() == "share" {
            return unresolvedReference(
                url: components.url?.absoluteString ?? input,
                code: path.dropFirst().joined(separator: "_"),
                prefix: "share"
            )
        }

        // صيغة المشاركة القديمة: facebook.com/share.php?u=…
        if first.lowercased() == "share.php",
           let target = components.queryItems?.first(where: { $0.name == "u" })?.value {
            return reference(from: target)
        }

        if first.lowercased() == "profile.php" {
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value
                ?? components.queryItems?.first(where: { $0.name == "username" })?.value
            guard let id else { return nil }
            if isNumeric(id) { return numericReference(id) }
            return referenceForHandle(id)
        }

        // روابط منشورات قديمة تحمل رقم الصفحة في ?id= بدل اسم الصفحة:
        // story.php وpermalink.php وphoto.php. هذه أكثر الصيغ التي ينسخها
        // المستخدم من تطبيق فيسبوك، وكانت تُرفض سابقاً فلا تُضاف الصفحة.
        if ["story.php", "permalink.php", "photo.php", "photo"].contains(first.lowercased()) {
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
               isNumeric(id) {
                return numericReference(id)
            }
            if let handle = components.queryItems?.first(where: { $0.name == "username" })?.value,
               isValidHandle(handle) {
                return referenceForHandle(handle)
            }
            return nil
        }

        if first.lowercased() == "pages" || first.lowercased() == "people" {
            if let id = numericID(in: path) { return numericReference(id) }
            if path.count >= 2 {
                if isValidHandle(path[1]) { return referenceForHandle(path[1]) }
                return unresolvedReference(
                    url: components.url?.absoluteString ?? input,
                    code: path[1],
                    prefix: "page"
                )
            }
            return nil
        }

        if first.lowercased() == "pg" {
            if let id = numericID(in: path) { return numericReference(id) }
            if path.count >= 2 {
                if isValidHandle(path[1]) { return referenceForHandle(path[1]) }
                return unresolvedReference(
                    url: components.url?.absoluteString ?? input,
                    code: path[1],
                    prefix: "page"
                )
            }
            return nil
        }

        // روابط الصفحات الجديدة: facebook.com/p/PageName-123456
        if first.lowercased() == "p" {
            if let id = numericID(in: path) { return numericReference(id) }
            if path.count >= 2 {
                return unresolvedReference(
                    url: components.url?.absoluteString ?? input,
                    code: path[1],
                    prefix: "p"
                )
            }
            return nil
        }

        let handle = first.hasPrefix("@") ? String(first.dropFirst()) : first
        guard !reservedPaths.contains(handle.lowercased()) else { return nil }
        if isValidHandle(handle) {
            return referenceForHandle(handle)
        }
        if let id = numericID(in: [handle]) {
            return numericReference(id)
        }
        return unresolvedReference(
            url: components.url?.absoluteString ?? input,
            code: handle,
            prefix: "page"
        )
    }

    private static func isFacebookHost(_ host: String) -> Bool {
        host == "facebook.com" ||
        host.hasSuffix(".facebook.com") ||
        host == "fb.com" ||
        host == "www.fb.com" ||
        host == "fb.me" ||
        host == "www.fb.me" ||
        host == "fb.watch" ||
        host == "www.fb.watch" ||
        host == "fbwat.ch"
    }

    /// يستخرج رقم الصفحة من المسار، مثل `PageName-123456` أو
    /// `اسم-الصفحة-123456`، مع تجاهل الأرقام القصيرة مثل السنة.
    private static func numericID(in path: [String]) -> String? {
        for value in path.reversed() {
            if isNumeric(value), value.count >= 5 { return value }
            if let range = value.range(of: #"(\d{5,})$"#, options: .regularExpression) {
                return String(value[range])
            }
        }
        return nil
    }

    /// مرجع مبدئي لرابط لا يحمل اسم صفحة واضحاً (مشاركة أو fb.me أو
    /// رابط عربي). يُحل إلى الصفحة النهائية عند الجلب.
    private static func unresolvedReference(
        url: String,
        code: String,
        prefix: String
    ) -> FacebookPageReference? {
        guard !code.isEmpty else { return nil }
        var safe = code
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
        if safe.isEmpty {
            safe = stableCode(for: code)
        }
        guard !safe.isEmpty, let inputURL = URL(string: url) else { return nil }
        let handle = String("\(prefix)_\(safe)".prefix(80))
        return FacebookPageReference(
            inputURL: inputURL,
            handle: handle,
            canonicalURL: url,
            isNumericID: false,
            needsResolution: true
        )
    }

    /// بصمة ثابتة لا تتغير بين التشغيلات، بخلاف `hashValue`.
    private static func stableCode(for value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func referenceForHandle(_ raw: String) -> FacebookPageReference? {
        var handle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while handle.hasPrefix("@") { handle.removeFirst() }
        guard isValidHandle(handle) else { return nil }
        let lowered = handle.lowercased()
        guard !reservedPaths.contains(lowered) else { return nil }

        if isNumeric(handle) {
            return numericReference(handle)
        }
        return FacebookPageReference(
            inputURL: URL(string: "https://www.facebook.com/\(handle)")!,
            handle: lowered,
            canonicalURL: "https://www.facebook.com/\(handle)",
            isNumericID: false,
            needsResolution: false
        )
    }

    private static func numericReference(_ id: String) -> FacebookPageReference {
        FacebookPageReference(
            inputURL: URL(string: "https://www.facebook.com/profile.php?id=\(id)")!,
            handle: id,
            canonicalURL: "https://www.facebook.com/profile.php?id=\(id)",
            isNumericID: true,
            needsResolution: false
        )
    }

    private static func isValidHandle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 80 else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9._]+$"#, options: .regularExpression) != nil
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    // MARK: - تحليل الصفحة

    static func parse(
        html: String,
        reference: FacebookPageReference,
        createdAt: String?
    ) throws -> DirectFacebookResult {
        let objects = jsonObjects(in: html)
        let isLogin = html.contains("login_form")
            || html.contains("login_page")
            || html.contains("id=\"login_popup_cta_form\"")
        let title = cleanName(metaContent(in: html, property: "og:title") ?? "")
        let pageURL = metaContent(in: html, property: "og:url") ?? ""
        let ogImage = metaContent(in: html, property: "og:image") ?? ""

        let userVanity = firstRegexGroup(#""userVanity"\s*:\s*"([^"]+)""#, in: html)
        let userID = firstRegexGroup(#""userID"\s*:\s*"([0-9]+)""#, in: html)

        // قد يعيد فيسبوك صفحة المشاركة نفسها مع og:url للصفحة المقصودة
        // بدل تحويل HTTP، فنستخرج مرجع الصفحة النهائي من og:url.
        var effectiveReference = reference
        if reference.needsResolution,
           !pageURL.isEmpty,
           let resolved = FacebookPageParser.reference(from: pageURL),
           !resolved.needsResolution {
            effectiveReference = resolved
        }

        var handle = effectiveReference.handle
        if let userVanity, isValidHandle(userVanity), !isNumeric(userVanity) {
            handle = userVanity.lowercased()
        } else if let userID,
                  isNumeric(userID),
                  effectiveReference.isNumericID || reference.needsResolution {
            handle = userID
        }

        // في الروابط التي تحتاج تحويلاً، استخدم الاسم النهائي المقروء من
        // الصفحة بدل كود المشاركة المؤقت حتى يبقى معرّف الحساب مستقلاً.
        let identityHandle = effectiveReference.needsResolution ? handle : effectiveReference.handle

        var canonicalURL = effectiveReference.canonicalURL
        if !effectiveReference.isNumericID,
           !pageURL.isEmpty,
           let url = URL(string: pageURL),
           let host = url.host?.lowercased(),
           host.contains("facebook.com"),
           !url.path.contains("/login") {
            canonicalURL = pageURL
        } else if !effectiveReference.isNumericID, !effectiveReference.needsResolution {
            canonicalURL = "https://www.facebook.com/\(handle)"
        }

        // تمييز صفحة تسجيل الدخول عن الصفحة الحقيقية. سابقاً كانت أي صفحة
        // تعيد «Facebook» تُعد صفحة غير موجودة، وبعض الصفحات العربية كانت
        // تُحفظ باسم «تسجيل الدخول إلى فيسبوك».
        let titleLower = title.lowercased()
        let loginTitle = titleLower == "facebook"
            || titleLower.contains("log in")
            || titleLower.contains("log into")
            || titleLower.contains("login")
            || titleLower.contains("sign up")
            || titleLower.contains("تسجيل الدخول")
            || titleLower.contains("دخول إلى فيسبوك")
            || titleLower.contains("إنشاء حساب")
        if titleLower == "facebook" { throw DirectFacebookError.blocked }
        if loginTitle && (isLogin || pageURL.isEmpty) { throw DirectFacebookError.blocked }

        var displayName = cleanedPageName(title)
        if displayName.isEmpty || loginTitle {
            if let userVanity, isValidHandle(userVanity) {
                displayName = userVanity
            } else if !handle.isEmpty, !isNumeric(handle) {
                displayName = handle
            } else {
                if isLogin { throw DirectFacebookError.blocked }
                throw DirectFacebookError.notFound
            }
        }

        let avatar = profilePicture(in: objects) ?? (ogImage.isEmpty ? nil : decodeHTMLEntities(ogImage))

        let social = socialCounts(in: objects, html: html)
        let followers = social.followers.value
        let following = social.following.value
        let followersExact = social.followers.exact
        let followingExact = social.following.exact
        let posts = parsePosts(in: objects)
        let now = Int(Date().timeIntervalSince1970)
        let daySeconds = 24 * 60 * 60
        let weekSeconds = 7 * daySeconds
        let recent = posts.filter { $0.createTime >= now - daySeconds && $0.createTime <= now + 300 }
        let weekly = posts.filter { $0.createTime >= now - weekSeconds && $0.createTime <= now + 300 }
        let totalViews = posts.reduce(Int64(0)) { $0 + $1.views }
        let recentViews = recent.reduce(Int64(0)) { $0 + $1.views }
        let weeklyViews = weekly.reduce(Int64(0)) { $0 + $1.views }
        let totalLikes = posts.reduce(Int64(0)) { $0 + $1.likes }
        let totalComments = posts.reduce(Int64(0)) { $0 + $1.comments }
        let totalShares = posts.reduce(Int64(0)) { $0 + $1.shares }
        let likes24h = recent.reduce(Int64(0)) { $0 + $1.likes }
        let likes7d = weekly.reduce(Int64(0)) { $0 + $1.likes }
        let videoPosts = posts.filter { $0.viewsExact || $0.views > 0 }

        // خلاصة الصفحة العامة تعرض ٢٠ منشوراً. إن كانت أقل فهي كل المنشورات
        // المتاحة، وإن كانت ٢٠ فقد يكون هناك المزيد لا يعرضه فيسبوك للزائر.
        let feedLimit = 20
        let allPostsLoaded = posts.count < feedLimit
        let oldest = posts.map(\.createTime).min() ?? 0
        let dailyComplete = allPostsLoaded || (oldest > 0 && oldest < now - daySeconds)
        let weeklyComplete = allPostsLoaded || (oldest > 0 && oldest < now - weekSeconds)
        let viewsExact = posts.allSatisfy { $0.viewsExact }
        let dailyViewsExact = dailyComplete && recent.allSatisfy { $0.viewsExact }
        let weeklyViewsExact = weeklyComplete && weekly.allSatisfy { $0.viewsExact }
        let coverage = allPostsLoaded ? 1 : min(1, Double(posts.count) / Double(feedLimit))
        let createdAtValue = createdAt ?? ISO8601DateFormatter.nabd.string(from: Date())

        let account = Account(
            id: "direct-facebook-\(identityHandle.lowercased())",
            platform: .facebook,
            handle: handle,
            displayName: displayName,
            url: canonicalURL,
            avatarUrl: avatar,
            isVerified: false,
            followers: followers,
            following: following,
            likes: 0,
            posts: posts.count,
            postsCountExact: false,
            views: totalViews,
            videoLikes: totalLikes,
            comments: totalComments,
            shares: totalShares,
            fetchedVideos: posts.count,
            posts24h: recent.count,
            views24h: recentViews,
            likes24h: likes24h,
            posts7d: weekly.count,
            weeklyViews: weeklyViews,
            likes7d: likes7d,
            avgViews: videoPosts.isEmpty ? 0 : totalViews / Int64(videoPosts.count),
            coverage: coverage,
            connected: false,
            publicStats: true,
            profileExact: followersExact && followingExact,
            viewsExact: viewsExact,
            dailyComplete: dailyComplete,
            dailyViewsExact: dailyViewsExact,
            weeklyComplete: weeklyComplete,
            weeklyViewsExact: weeklyViewsExact,
            allPostsLoaded: allPostsLoaded,
            status: "public",
            error: nil,
            lastSyncedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            createdAt: createdAtValue
        )

        return DirectFacebookResult(account: account, videos: posts)
    }

    // MARK: - المنشورات

    private static func parsePosts(in objects: [Any]) -> [VideoItem] {
        // نعتمد أولاً على خلاصة الصفحة الرسمية timeline_list_feed_units لأنها
        // منشورات الصفحة نفسها فقط. القراءة العامة من كل JSON احتياط للحالات
        // التي يتغيّر فيها اسم الخلاصة، وقد تجمع منشورات مقترحة، لذا لا
        // نستخدمها إلا عند غياب الخلاصة.
        var nodes: [[String: Any]] = []
        if let feed = firstDictionary(forKey: "timeline_list_feed_units", in: objects),
           let edges = feed["edges"] as? [Any] {
            for edge in edges {
                if let node = (edge as? [String: Any])?["node"] as? [String: Any] {
                    nodes.append(node)
                }
            }
        }
        if nodes.isEmpty {
            for object in objects {
                collectPostNodes(in: object, into: &nodes)
                if nodes.count >= 40 { break }
            }
        }

        var seen = Set<String>()
        var posts: [VideoItem] = []
        for node in nodes.prefix(40) {
            guard let creationTime = int64(from: node["creation_time"]), creationTime > 0 else { continue }

            let postID = firstString(forKey: "post_id", in: node)
                ?? firstString(forKey: "story_fbid", in: node)
                ?? "\(creationTime)-\(posts.count)"
            guard seen.insert(postID).inserted else { continue }

            let permalink = postPermalink(in: node, postID: postID)
            let viewsValue = maxInt64(forKey: "video_view_count", in: node)
            let hasVideo = isVideoPost(in: node, permalink: permalink) || viewsValue != nil
            let message = postMessage(in: node)
            let image = postImage(in: node, hasVideo: hasVideo)

            let title: String
            if !message.isEmpty {
                title = message
            } else if hasVideo {
                title = "فيديو فيسبوك"
            } else {
                title = "منشور فيسبوك"
            }

            posts.append(VideoItem(
                id: postID,
                title: title,
                coverUrl: image,
                shareUrl: permalink,
                duration: 0,
                createTime: creationTime,
                views: viewsValue ?? 0,
                likes: reactionCount(in: node),
                comments: commentCount(in: node),
                shares: shareCount(in: node),
                // فيسبوك ينشر مشاهدات الفيديو فقط. المنشورات النصية والصور
                // لا تكشف مشاهدات عامة، لذا نعلّمها غير دقيقة بدل اعتبارها صفراً.
                viewsExact: hasVideo && viewsValue != nil
            ))
        }

        return posts.sorted { $0.createTime > $1.createTime }
    }

    private static func collectPostNodes(
        in object: Any,
        into posts: inout [[String: Any]],
        depth: Int = 0
    ) {
        guard depth < 40, posts.count < 40 else { return }
        if let dictionary = object as? [String: Any] {
            if isPostNode(dictionary) {
                posts.append(dictionary)
                return
            }
            for value in dictionary.values {
                collectPostNodes(in: value, into: &posts, depth: depth + 1)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectPostNodes(in: value, into: &posts, depth: depth + 1)
            }
        }
    }

    private static func isPostNode(_ dictionary: [String: Any]) -> Bool {
        guard let creation = int64(from: dictionary["creation_time"]),
              creation > 1_000_000_000 else { return false }
        return dictionary["post_id"] != nil
            || dictionary["story_fbid"] != nil
            || dictionary["permalink_url"] != nil
            || dictionary["comet_sections"] != nil
    }

    private static func postPermalink(in node: [String: Any], postID: String) -> String {
        if let url = node["permalink_url"] as? String, !url.isEmpty { return url }
        if let url = firstString(forKey: "wwwURL", in: node), !url.isEmpty { return url }
        if let url = firstString(forKey: "url", in: node), url.contains("facebook.com") { return url }
        return "https://www.facebook.com/\(postID)"
    }

    private static func isVideoPost(in node: [String: Any], permalink: String) -> Bool {
        if permalink.contains("/videos/") || permalink.contains("/reel/") || permalink.contains("/watch/") {
            return true
        }
        if firstString(forKey: "videoId", in: node) != nil { return true }
        return containsVideoMarker(in: node)
    }

    private static func containsVideoMarker(in object: Any, depth: Int = 0) -> Bool {
        guard depth < 25 else { return false }
        if let dictionary = object as? [String: Any] {
            if let type = dictionary["__typename"] as? String, type == "Video" { return true }
            if dictionary["videoId"] != nil || dictionary["video_id"] != nil { return true }
            if let flag = dictionary["is_video"] as? Bool, flag { return true }
            if let flag = dictionary["isVideo"] as? Bool, flag { return true }
            for value in dictionary.values {
                if containsVideoMarker(in: value, depth: depth + 1) { return true }
            }
        } else if let array = object as? [Any] {
            for value in array where !(value is String) {
                if containsVideoMarker(in: value, depth: depth + 1) { return true }
            }
        }
        return false
    }

    private static func postMessage(in node: [String: Any]) -> String {
        let story = (node["comet_sections"] as? [String: Any])?["content"] as? [String: Any]
        let storyNode = story?["story"] as? [String: Any]
        if let text = messageText(in: storyNode?["message"]) { return text }
        if let text = messageText(in: node["story"]) { return text }
        if let text = messageText(in: node["message"]) { return text }
        if let text = firstMessageText(in: node) { return text }
        return ""
    }

    private static func messageText(in object: Any?) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }
        if let text = dictionary["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return trimmedText(text)
        }
        if let story = dictionary["story"] as? [String: Any],
           let message = story["message"] as? [String: Any],
           let text = message["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return trimmedText(text)
        }
        return nil
    }

    private static func firstMessageText(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let message = dictionary["message"] as? [String: Any],
               let text = message["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return trimmedText(text)
            }
            for value in dictionary.values {
                if let found = firstMessageText(in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstMessageText(in: value) { return found }
            }
        }
        return nil
    }

    private static func trimmedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func postImage(in node: [String: Any], hasVideo: Bool) -> String? {
        if let photo = firstDictionary(forKey: "photo_image", in: node),
           let uri = photo["uri"] as? String, !uri.isEmpty {
            return uri
        }
        if hasVideo {
            if let thumbnail = firstDictionary(forKey: "preferred_thumbnail", in: node),
               let image = thumbnail["image"] as? [String: Any],
               let uri = image["uri"] as? String, !uri.isEmpty {
                return uri
            }
            if let thumbnail = firstDictionary(forKey: "thumbnailImage", in: node),
               let uri = thumbnail["uri"] as? String, !uri.isEmpty {
                return uri
            }
        }
        return nil
    }

    // MARK: - إحصاءات التفاعل

    private static func reactionCount(in node: [String: Any]) -> Int64 {
        // نأخذ أكبر قيمة لأن ردود الفعل الجزئية (top_reactions) قد تظهر قبل
        // المجموع في ترتيب غير ثابت، وكان ذلك يعرض رقماً أقل من الحقيقي.
        maxInt64(forKey: "reaction_count", in: node) ?? 0
    }

    private static func commentCount(in node: [String: Any]) -> Int64 {
        var counts: [Int64] = []
        collectCommentTotals(in: node, into: &counts)
        return counts.max() ?? 0
    }

    private static func collectCommentTotals(
        in object: Any,
        into counts: inout [Int64],
        depth: Int = 0
    ) {
        guard depth < 30 else { return }
        if let dictionary = object as? [String: Any] {
            if let renderer = dictionary["comment_rendering_instance"] as? [String: Any],
               let comments = renderer["comments"] as? [String: Any],
               let count = int64(from: comments["total_count"]) {
                counts.append(count)
            }
            if let count = int64(from: dictionary["total_comment_count"]) {
                counts.append(count)
            }
            for value in dictionary.values {
                collectCommentTotals(in: value, into: &counts, depth: depth + 1)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectCommentTotals(in: value, into: &counts, depth: depth + 1)
            }
        }
    }

    private static func shareCount(in node: [String: Any]) -> Int64 {
        maxInt64(forKey: "share_count", in: node) ?? 0
    }

    /// أكبر قيمة رقمية للمفتاح داخل المنشور. تصلح للمجاميع مثل
    /// reaction_count وshare_count وvideo_view_count حتى لو تكررت في
    /// أقسام فرعية متعددة.
    private static func maxInt64(forKey key: String, in object: Any, depth: Int = 0) -> Int64? {
        guard depth < 30 else { return nil }
        if let dictionary = object as? [String: Any] {
            var best: Int64?
            if let raw = dictionary[key], let number = int64(from: raw) {
                best = number
            } else if let nested = dictionary[key] as? [String: Any] {
                best = int64(from: nested["count"] ?? nested["total_count"] ?? nested["value"])
            }
            for (nestedKey, value) in dictionary where nestedKey != key {
                if let found = maxInt64(forKey: key, in: value, depth: depth + 1) {
                    best = max(best ?? found, found)
                }
            }
            return best
        }
        if let array = object as? [Any] {
            var best: Int64?
            for value in array {
                if let found = maxInt64(forKey: key, in: value, depth: depth + 1) {
                    best = max(best ?? found, found)
                }
            }
            return best
        }
        return nil
    }

    // MARK: - الملف الشخصي

    private static func cleanedPageName(_ raw: String) -> String {
        var value = decodeHTMLEntities(raw)
        let suffixes = [" | Facebook", " - Facebook", " | فيسبوك", " - Home", " - الصفحة الرئيسية"]
        for suffix in suffixes where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanName(_ raw: String) -> String {
        decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func profilePicture(in objects: [Any]) -> String? {
        guard let picture = firstDictionary(forKey: "profile_picture", in: objects) else { return nil }
        return picture["uri"] as? String
    }

    private struct SocialCount {
        var value: Int64
        var exact: Bool
    }

    private static func socialCounts(
        in objects: [Any],
        html: String
    ) -> (followers: SocialCount, following: SocialCount) {
        var followers = SocialCount(value: 0, exact: false)
        var following = SocialCount(value: 0, exact: false)

        if let context = firstDictionary(forKey: "profile_social_context", in: objects),
           let content = context["content"] as? [Any] {
            for item in content {
                guard let dictionary = item as? [String: Any] else { continue }
                let uri = (dictionary["uri"] as? String)?.lowercased() ?? ""
                let text = ((dictionary["text"] as? [String: Any])?["text"] as? String) ?? ""
                if uri.contains("/followers") || text.contains("متابع") || text.lowercased().contains("follower") {
                    if let parsed = parseHumanCount(text) {
                        followers = SocialCount(value: parsed.value, exact: parsed.exact)
                    }
                } else if uri.contains("/following") || text.contains("يتابع") || text.lowercased().contains("following") {
                    if let parsed = parseHumanCount(text) {
                        following = SocialCount(value: parsed.value, exact: parsed.exact)
                    }
                }
            }
        }

        // احتياط: بعض الصفحات لا تُرجع profile_social_context للزائر،
        // لكنها تضع العدد الحقيقي في JSON أو في وصف الصفحة.
        if followers.value == 0 {
            if let exact = firstRegexInt(#""follower_count"\s*:\s*([0-9]+)"#, in: html) {
                followers = SocialCount(value: exact, exact: true)
            } else if let exact = firstRegexInt(#""followerCount"\s*:\s*([0-9]+)"#, in: html) {
                followers = SocialCount(value: exact, exact: true)
            } else if let parsed = humanCountNearMarker(in: html, markers: ["followers", "follower", "متابع"]) {
                followers = SocialCount(value: parsed, exact: false)
            }
        }
        if following.value == 0 {
            if let exact = firstRegexInt(#""following_count"\s*:\s*([0-9]+)"#, in: html) {
                following = SocialCount(value: exact, exact: true)
            } else if let parsed = humanCountNearMarker(in: html, markers: ["following", "يتابع"]) {
                following = SocialCount(value: parsed, exact: false)
            }
        }

        return (followers, following)
    }

    /// يقرأ «28M followers» أو «١٢٣٤ متابع» من نص الصفحة.
    private static func humanCountNearMarker(in html: String, markers: [String]) -> Int64? {
        let plain = stripTags(html)
        let lower = normalizeDigits(plain).lowercased()
        for marker in markers {
            guard let markerRange = lower.range(of: marker) else { continue }
            let prefix = String(lower[..<markerRange.lowerBound])
            guard let numberRange = prefix.range(of: #"([0-9][0-9,\.]*\s*(?:k|m|b|ألف|الف|مليون|مليار)?)\s*$"#,
                                              options: .regularExpression) else { continue }
            if let parsed = parseHumanCount(String(prefix[numberRange])) {
                return parsed.value
            }
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: " ")
    }

    /// يقرأ أرقام فيسبوك المعروضة مثل «٢٨ مليون» أو «28M» أو «1,234».
    private static func parseHumanCount(_ raw: String) -> (value: Int64, exact: Bool)? {
        var value = normalizeDigits(raw)
        value = value
            .replacingOccurrences(of: "\u{200f}", with: "")
            .replacingOccurrences(of: "\u{200e}", with: "")
            .replacingOccurrences(of: "\u{061c}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{066c}", with: "")
            .replacingOccurrences(of: "\u{066b}", with: ".")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Double(value[numberRange]) else { return nil }

        let tail = String(value[numberRange.upperBound...]).lowercased()
        let multiplier: Double
        let exact: Bool
        if tail.contains("مليار") || tail.contains("billion") || tail.contains("b") {
            multiplier = 1_000_000_000
            exact = false
        } else if tail.contains("مليون") || tail.contains("million") || tail.contains("m") {
            multiplier = 1_000_000
            exact = false
        } else if tail.contains("ألف") || tail.contains("الف") || tail.contains("thousand") || tail.contains("k") {
            multiplier = 1_000
            exact = false
        } else {
            multiplier = 1
            exact = true
        }

        return (Int64((number * multiplier).rounded()), exact)
    }

    private static func normalizeDigits(_ raw: String) -> String {
        let digits: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
        ]
        return String(raw.map { digits[$0] ?? $0 })
    }

    // MARK: - أدوات JSON وHTML

    private static func jsonObjects(in html: String) -> [Any] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let contentRange = Range(match.range(at: 1), in: html) else { return nil }
            let content = String(html[contentRange])
            guard let data = content.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
    }

    private static func firstDictionary(forKey key: String, in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] as? [String: Any] { return value }
            for value in dictionary.values {
                if let found = firstDictionary(forKey: key, in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstDictionary(forKey: key, in: value) { return found }
            }
        }
        return nil
    }

    private static func firstValue(forKey key: String, in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] { return value }
            for value in dictionary.values {
                if let found = firstValue(forKey: key, in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstValue(forKey: key, in: value) { return found }
            }
        }
        return nil
    }

    private static func firstString(forKey key: String, in object: Any) -> String? {
        guard let value = firstValue(forKey: key, in: object) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func firstInt(forKey key: String, in object: Any) -> Int? {
        guard let value = firstValue(forKey: key, in: object) else { return nil }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func firstInt64(forKey key: String, in object: Any) -> Int64? {
        guard let value = firstValue(forKey: key, in: object) else { return nil }
        return int64(from: value)
    }

    private static func int64(from value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let double = value as? Double { return Int64(double) }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int64(trimmed) { return parsed }
            if let parsed = Double(trimmed) { return Int64(parsed) }
        }
        return nil
    }

    private static func firstRegexInt(_ pattern: String, in string: String) -> Int64? {
        guard let group = firstRegexGroup(pattern, in: string) else { return nil }
        return Int64(group)
    }

    private static func firstRegexGroup(_ pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[range])
    }

    private static func metaContent(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        guard let regex = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*(?:property|name)=["']\#(escaped)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let tagRange = Range(match.range, in: html) else { return nil }
        let tag = String(html[tagRange])
        guard let contentRegex = try? NSRegularExpression(
            pattern: #"content=["']([^"']*)["']"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let tagNSRange = NSRange(tag.startIndex..., in: tag)
        guard let contentMatch = contentRegex.firstMatch(in: tag, range: tagNSRange),
              let contentRange = Range(contentMatch.range(at: 1), in: tag) else { return nil }
        return String(tag[contentRange])
    }

    static func decodeHTMLEntities(_ raw: String) -> String {
        var value = raw
        let named = [
            "&amp;": "&", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">",
            "&nbsp;": " ", "&#39;": "'", "&#x27;": "'", "&mdash;": "—", "&ndash;": "–",
            "&hellip;": "…", "&lsquo;": "‘", "&rsquo;": "’", "&ldquo;": "“", "&rdquo;": "”",
        ]
        for (entity, replacement) in named {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        if let regex = try? NSRegularExpression(pattern: #"&#x([0-9A-Fa-f]+);"#) {
            let range = NSRange(value.startIndex..., in: value)
            for match in regex.matches(in: value, range: range).reversed() {
                guard let full = Range(match.range, in: value),
                      let hexRange = Range(match.range(at: 1), in: value),
                      let scalarValue = UInt32(value[hexRange], radix: 16),
                      let scalar = UnicodeScalar(scalarValue) else { continue }
                value.replaceSubrange(full, with: String(scalar))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"&#([0-9]+);"#) {
            let range = NSRange(value.startIndex..., in: value)
            for match in regex.matches(in: value, range: range).reversed() {
                guard let full = Range(match.range, in: value),
                      let decimalRange = Range(match.range(at: 1), in: value),
                      let scalarValue = UInt32(value[decimalRange]),
                      let scalar = UnicodeScalar(scalarValue) else { continue }
                value.replaceSubrange(full, with: String(scalar))
            }
        }

        return value
    }
}

/// يقرأ صفحة فيسبوك العامة مباشرة. لا تسجيل دخول ولا خادم.
final class DirectFacebookService {
    static let shared = DirectFacebookService()

    /// فيسبوك يعيد الصفحة العامة كاملة لزائر Googlebot، بينما يعيد
    /// المتصفح العادي إلى شاشة تسجيل الدخول.
    private let botUserAgent = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
    private let alternateUserAgent = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
    private let minimumRequestGap: TimeInterval = 0.35
    private let session: URLSession
    private var lastRequestAt = Date.distantPast

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 14
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func fetch(handle: String, url: String? = nil, createdAt: String? = nil) async throws -> DirectFacebookResult {
        let rawLink = (url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? url : nil) ?? handle
        guard let reference = FacebookPageParser.reference(from: rawLink) ?? FacebookPageParser.reference(from: handle) else {
            throw DirectFacebookError.invalidLink
        }

        var attempts: [(url: String, agent: String)] = []
        func add(_ value: String, agent: String = "") {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            attempts.append((trimmed, agent))
        }

        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(url)
        }
        add(reference.inputURL.absoluteString)

        if !reference.needsResolution {
            if reference.isNumericID {
                add("https://www.facebook.com/profile.php?id=\(reference.handle)")
                add("https://mbasic.facebook.com/profile.php?id=\(reference.handle)&v=timeline")
            } else {
                add("https://www.facebook.com/\(reference.handle)")
                add("https://mbasic.facebook.com/\(reference.handle)?v=timeline")
                add("https://m.facebook.com/\(reference.handle)")
            }
        } else if let url = URL(string: reference.inputURL.absoluteString) {
            // روابط المشاركة تُحوَّل تلقائياً؛ نضيف نسخة mbasic لأنها
            // تعيد التحويل إلى الصفحة العامة في حالات كثيرة.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if components?.host?.contains("facebook.com") == true {
                components?.host = "mbasic.facebook.com"
                if let alternate = components?.url?.absoluteString {
                    add(alternate)
                }
            }
        }

        var seen = Set<String>()
        var lastError: DirectFacebookError = .blocked
        var sawBlockedPage = false

        for attempt in attempts {
            guard let target = URL(string: attempt.url),
                  seen.insert(target.absoluteString + "|" + attempt.agent).inserted else { continue }
            let agent = attempt.agent.isEmpty ? botUserAgent : attempt.agent
            do {
                let page = try await load(target, userAgent: agent)
                if page.html.contains("login_form") &&
                    !page.html.contains("timeline_list_feed_units") &&
                    !page.html.contains("og:title") {
                    sawBlockedPage = true
                    throw DirectFacebookError.blocked
                }
                return try parse(page: page, reference: reference, createdAt: createdAt)
            } catch let error as DirectFacebookError {
                lastError = error
                switch error {
                case .blocked, .badResponse: sawBlockedPage = true
                case .invalidLink, .notFound: break
                }
                if !error.isTemporary { throw error }
            } catch {
                lastError = .blocked
            }
        }

        // محاولة أخيرة بوكيل زاحف مختلف على العنوان الأساسي، لأن فيسبوك
        // يغيّر ما يعيده حسب بصمة الطلب.
        if (sawBlockedPage || lastError.isTemporary),
           let fallback = URL(string: reference.inputURL.absoluteString) {
            if let page = try? await load(fallback, userAgent: alternateUserAgent) {
                if let result = try? parse(page: page, reference: reference, createdAt: createdAt) {
                    return result
                }
            }
        }

        throw lastError
    }

    private func parse(
        page: (html: String, finalURL: URL),
        reference: FacebookPageReference,
        createdAt: String?
    ) throws -> DirectFacebookResult {
        // روابط المشاركة وfb.me والروابط العربية تُحوَّل إلى الصفحة
        // النهائية قبل قراءة الأرقام وتثبيت المعرّف.
        var parseReference = reference
        if reference.needsResolution,
           let canonical = FacebookPageParser.reference(from: page.finalURL.absoluteString),
           !canonical.needsResolution {
            parseReference = canonical
        }
        return try FacebookPageParser.parse(
            html: page.html,
            reference: parseReference,
            createdAt: createdAt
        )
    }

    private func load(_ url: URL, userAgent: String) async throws -> (html: String, finalURL: URL) {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumRequestGap {
            let delay = UInt64((minimumRequestGap - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        lastRequestAt = Date()

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 14
        )
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DirectFacebookError.badResponse
            }
            let html = String(decoding: data, as: UTF8.self)
            let finalURL = http.url ?? url

            if finalURL.path.lowercased().contains("/login") {
                throw DirectFacebookError.blocked
            }

            switch http.statusCode {
            case 200..<300:
                if data.count < 200 {
                    throw DirectFacebookError.badResponse
                }
                if html.contains("content isn't available") || html.contains("هذا المحتوى غير متاح") {
                    throw DirectFacebookError.notFound
                }
                return (html, finalURL)
            case 404, 410:
                throw DirectFacebookError.notFound
            case 429, 500..<600:
                throw DirectFacebookError.blocked
            default:
                throw DirectFacebookError.badResponse
            }
        } catch let error as DirectFacebookError {
            throw error
        } catch {
            throw DirectFacebookError.blocked
        }
    }
}
