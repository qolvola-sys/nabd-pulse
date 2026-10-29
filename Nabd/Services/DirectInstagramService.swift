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
    /// واجهة الويب العامة تتعامل أفضل مع متصفح سطح مكتب حديث.
    private let desktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    private let appID = "936619743392459"
    private let daySeconds = 24 * 60 * 60
    private let weekSeconds = 7 * 24 * 60 * 60
    private let minimumRequestGap: TimeInterval = 0.5

    private let session: URLSession
    /// جلسة نظيفة خاصة بصفحة التضمين: بلا كوكيز، حتى لا يفرض إنستغرام
    /// تسجيل الدخول بسبب كوكيز رُفضت بها واجهة web_profile_info.
    private let embedSession: URLSession
    private let cookieStorage = HTTPCookieStorage()
    private var lastRequestAt = Date.distantPast
    private var didWarmUp = false
    private var csrfToken: String?
    /// بعد تكرار 429 نتوقف عن محاولة واجهة الويب مؤقتاً ونستخدم صفحة
    /// التضمين مباشرة، بدل إهدار ثوانٍ لكل حساب في نفس المزامنة.
    private var apiBlockedUntil = Date.distantPast
    /// نتيجة آخر محاولة لكل حساب: أي مصدر نجح وأيها فشل. تُعرض في شاشة
    /// الحساب عند تعذّر القراءة، حتى نعرف سبب الصفر بدل التخمين.
    private var diagnostics: [String: String] = [:]
    /// تفصيل محاولات المرحّل: اسم الخدمة ورمز استجابتها. يظهر في شاشة
    /// الحساب فقط، ويحدد هل الخدمة محجوبة أم ردّت بلا منشورات.
    private var relayDetails: [String: String] = [:]
    /// رمز استجابة آخر طلب لصفحة التضمين المباشرة.
    private var embedStatusCode: Int?
    /// آخر صفحة تضمين وصلت بحالة نجاح، نحتفظ بها لاستخراج بديل إن فشل
    /// تحليل contextJSON.
    private var lastEmbedHTML = ""
    /// سبب فشل تحليل contextJSON في آخر محاولة.
    private var lastContextFailure = ""
    /// مشاهدات الريلز الحقيقية لكل shortcode. صفحة التضمين المفردة تعرض
    /// `video_view_count` للزوار، بخلاف صفحة الحساب. نخزّنها لتجنب تكرار
    /// الطلب في نفس المزامنة.
    private var viewCountCache: [String: Int64] = [:]
    /// ملخص آخر قراءة للمشاهدات، يظهر في تقرير التشخيص.
    private var lastViewEnrichment = ""

    func diagnostic(for handle: String) -> String {
        diagnostics[handle.lowercased()] ?? "لم تُجرَّب بعد"
    }

    func relayDiagnostic(for handle: String) -> String {
        relayDetails[handle.lowercased()] ?? ""
    }

    /// عيّنات مختصرة من آخر الاستجابات (أول سطر من كل واحدة). تُستخدم
    /// لمعرفة ما إذا كانت الصفحة الواصلة هي صفحة إنستغرام فعلاً أم
    /// صفحة حجب/تسجيل دخول تعيد رمز 200 أيضاً.
    private var samples: [String: [String]] = [:]

    private func recordSample(_ line: String, for handle: String) {
        var list = samples[handle.lowercased()] ?? []
        list.append(line)
        if list.count > 8 { list.removeFirst(list.count - 8) }
        samples[handle.lowercased()] = list
    }

    private func sample(name: String, status: Int, body: String) -> String {
        let head = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(150)
        let hasJSON = body.contains("contextJSON")
        let hasLogin = body.contains("loginForm") || body.contains("Log in to Instagram")
        let hasConsent = body.contains("consent.google") || body.contains("Before you continue")
        return "\(name) \(status) \(body.count)B ctx=\(hasJSON ? 1 : 0) login=\(hasLogin ? 1 : 0) consent=\(hasConsent ? 1 : 0) head=\(head)"
    }

    private var reportSnapshots: [String: String] = [:]

    /// تقرير كامل قابل للنسخ، يرسله المستخدم عند تعذّر القراءة. يُفضّل
    /// آخر لقطة مكتملة، فإن لم توجد يعرض الحالة الجارية.
    func report(for handle: String) -> String {
        reportSnapshots[handle.lowercased()] ?? makeReport(for: handle)
    }

    private func makeReport(for handle: String) -> String {
        let key = handle.lowercased()
        var lines: [String] = []
        lines.append("app=\(AppVariant.version)")
        lines.append("handle=@\(handle)")
        lines.append("trail=\(diagnostics[key] ?? "-")")
        lines.append("relay=\(relayDetails[key] ?? "-")")
        lines.append(contentsOf: samples[key] ?? ["no samples"])
        return lines.joined(separator: "\n")
    }

    private func note(_ text: String, for handle: String) {
        let key = handle.lowercased()
        diagnostics[key] = text
        // نحتفظ بلقطة مكتملة بعد انتهاء المحاولة، حتى لا ينسخ المستخدم
        // تقريراً نصف مكتمل أثناء مزامنة جارية.
        reportSnapshots[key] = makeReport(for: handle)
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 28
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // كوكيز الجلسة (csrftoken وmid) ترفع فرصة قبول واجهة الويب
        // بدل إرجاع 429 فوراً.
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        let embedConfiguration = URLSessionConfiguration.ephemeral
        embedConfiguration.timeoutIntervalForRequest = 20
        embedConfiguration.timeoutIntervalForResource = 28
        embedConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        embedConfiguration.httpShouldSetCookies = false
        embedConfiguration.httpCookieAcceptPolicy = .never
        embedConfiguration.httpCookieStorage = nil
        embedConfiguration.waitsForConnectivity = false
        embedSession = URLSession(configuration: embedConfiguration)
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

        // ٠) صفحة التضمين العامة أولاً: لا تحتاج كوكيز ولا تسجيل دخول،
        // وتعرض الملف وآخر منشوراته مع الإعجابات الحقيقية. البدء بها يمنع
        // طلبات الواجهة من استنفاد حصة الشبكة وحجب القراءة كلها.
        let key = reference.handle.lowercased()
        samples[key] = []
        var trail: [String] = []
        var best: DirectInstagramResult?
        do {
            let embedResult = try await fetchEmbed(reference: reference, createdAt: createdAt)
            trail.append("embed ✓\(embedResult.videos.count)")
            if !lastViewEnrichment.isEmpty {
                trail.append(lastViewEnrichment)
            }
            // المنشورات وصلت، ومعها مشاهدات كل فيديو من صفحة تضمينه
            // المفردة. لا حاجة لإهدار طلبات أخرى قد تُرفض بـ429.
            if !embedResult.videos.isEmpty {
                note(trail.joined(separator: " · "), for: key)
                return embedResult
            }
            best = embedResult
        } catch DirectInstagramError.notFound {
            // الحساب غير موجود فعلاً: لا فائدة من تجربة بقية المصادر.
            throw DirectInstagramError.notFound
        } catch {
            trail.append("embed ✗\(embedStatusCode.map { String($0) } ?? "t")")
        }

        // ١) مرحّل خارجي يقرأ صفحة التضمين من شبكته هو. هذا هو المسار الذي
        // يعمل عندما تعطي الشبكة المحلية نسخة محدودة بلا منشورات. يوضع
        // مبكراً لأن الاستجابة تأتي في ثانية أو ثانيتين.
        if let relayResult = try? await fetchRelay(reference: reference, createdAt: createdAt) {
            trail.append("relay ✓\(relayResult.videos.count)")
            if !relayResult.videos.isEmpty {
                note(trail.joined(separator: " · "), for: key)
                return relayResult
            }
            if best == nil || (best?.videos.isEmpty ?? true) { best = relayResult }
        } else {
            trail.append("relay ✗")
        }

        // ٢) واجهة الويب العامة: أدق أرقام ومشاهدات الفيديو عندما تسمح.
        await warmUpIfNeeded()
        if let apiResult = try? await fetchAPI(reference: reference, createdAt: createdAt) {
            if !apiResult.videos.isEmpty {
                trail.append("api ✓\(apiResult.videos.count)")
                note(trail.joined(separator: " · "), for: key)
                return apiResult
            }
            trail.append("api ✓0")
            // الملف قُرئ لكن المنشورات لم تُرجع: نجرّب صفحة الحساب قبل الاكتفاء به.
            if best == nil || (best?.videos.isEmpty ?? true) { best = apiResult }
        } else {
            trail.append("api ✗")
        }

        // ٣) صفحة الحساب وبياناتها المدمجة، ثم وسوم og كحد أدنى.
        if let htmlResult = try? await fetchHTML(reference: reference, createdAt: createdAt) {
            if !htmlResult.videos.isEmpty {
                trail.append("html ✓\(htmlResult.videos.count)")
                note(trail.joined(separator: " · "), for: key)
                return htmlResult
            }
            trail.append("html ✓0")
            if best == nil || (best?.videos.isEmpty ?? true) { best = htmlResult }
        } else {
            trail.append("html ✗")
        }

        // ٤) محرك Safari داخل التطبيق: يتجاوز فحص بصمة الاتصال الذي يحجب
        // URLSession عند بعض الشبكات. آخر محاولة لأنها الأبطأ، وتُجرَّب
        // دائماً لأن المصادر السابقة قد تعيد ملفاً بلا منشورات.
        if let webResult = try? await fetchWeb(reference: reference, createdAt: createdAt) {
            if !webResult.videos.isEmpty || webResult.account.followers > 0 {
                trail.append("web ✓\(webResult.videos.count)")
                note(trail.joined(separator: " · "), for: key)
                return webResult
            }
            trail.append("web ✓0")
            if best == nil { best = webResult }
        } else {
            trail.append("web ✗")
        }

        note(trail.joined(separator: " · "), for: key)

        // لا منشورات من أي مصدر: نعيد أفضل ما قُرئ بدل إسقاطه.
        if let best { return best }

        throw DirectInstagramError.blocked
    }

    // MARK: - تهيئة الجلسة

    private func warmUpIfNeeded() async {
        guard !didWarmUp else { return }
        didWarmUp = true
        guard let url = URL(string: "https://www.instagram.com/") else { return }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")

        if let (data, _) = try? await send(request), data.count > 500 {
            csrfToken = cookieStorage.cookies?.first(where: { $0.name == "csrftoken" })?.value
        }
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
        guard Date() >= apiBlockedUntil else { throw DirectInstagramError.blocked }
        let hosts = ["https://www.instagram.com", "https://i.instagram.com"]
        var lastError: DirectInstagramError = .blocked
        var sawRateLimit = false

        for (index, host) in hosts.enumerated() {
            guard let url = URL(string:
                "\(host)/api/v1/users/web_profile_info/?username=\(reference.handle)"
            ) else { throw DirectInstagramError.invalidLink }

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue(index == 0 ? desktopUserAgent : userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(appID, forHTTPHeaderField: "x-ig-app-id")
            request.setValue("129477", forHTTPHeaderField: "x-asbd-id")
            request.setValue("0", forHTTPHeaderField: "x-ig-www-claim")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("https://www.instagram.com/\(reference.handle)/", forHTTPHeaderField: "Referer")
            request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")
            request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
            if let csrfToken, !csrfToken.isEmpty {
                request.setValue(csrfToken, forHTTPHeaderField: "x-csrftoken")
            }

            do {
                let (data, response) = try await send(request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = .badResponse
                    continue
                }
                if http.statusCode == 404 { throw DirectInstagramError.notFound }
                if http.statusCode == 429 {
                    lastError = .blocked
                    sawRateLimit = true
                    // انتظار قصير ثم إعادة المحاولة على المضيف التالي.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    continue
                }
                guard (200..<300).contains(http.statusCode), data.count > 80 else {
                    lastError = .blocked
                    continue
                }
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObject = root["data"] as? [String: Any],
                      let user = dataObject["user"] as? [String: Any],
                      !(stringValue(user["username"]) ?? "").isEmpty else {
                    lastError = .notFound
                    continue
                }
                return try makeResult(
                    user: user,
                    reference: reference,
                    createdAt: createdAt,
                    profileExact: true
                )
            } catch let error as DirectInstagramError {
                lastError = error
                if !error.isTemporary { throw error }
            } catch {
                lastError = .blocked
            }
        }

        if sawRateLimit {
            apiBlockedUntil = Date().addingTimeInterval(10 * 60)
        }
        throw lastError
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

    // MARK: - صفحة التضمين العامة

    /// صفحة `/embed/` العامة تعيد كائن `contextJSON` يتضمن بيانات الملف
    /// وآخر ٦ منشورات مع أرقام الإعجابات الحقيقية، وهي متاحة حتى عندما
    /// ترفض واجهة `web_profile_info` الطلبات. لا تعرض مشاهدات الفيديو،
    /// لذلك تبقى المشاهدات غير متاحة إن لم نقرأها من الواجهة.
    private func fetchEmbed(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        let handle = reference.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { throw DirectInstagramError.invalidLink }

        var urls: [URL] = []
        for suffix in ["embed/", "embed", "embed/captioned/"] {
            if let url = URL(string: "https://www.instagram.com/\(handle)/\(suffix)") {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { throw DirectInstagramError.invalidLink }
        embedStatusCode = nil

        // واجهة الهاتف هي التي تعيد contextJSON فعلاً. نجرّبها أولاً بجلسة
        // نظيفة، ثم بجلسة التطبيق (بكوكيز) لأن بعض الشبكات ترفض الجلسة
        // النظيفة وحدها. سطح المكتب لا يعيد contextJSON حاليًا.
        let attempts: [(session: URLSession, agent: String)] = [
            (embedSession, userAgent),
            (session, userAgent),
        ]

        var lastError: DirectInstagramError = .blocked
        var sawSuccessPage = false
        for url in urls {
            for attempt in attempts {
                do {
                    let context = try await loadEmbedContext(
                        url: url,
                        userAgent: attempt.agent,
                        handle: handle,
                        session: attempt.session
                    )
                    sawSuccessPage = true
                    return try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
                } catch let error as DirectInstagramError {
                    let code = embedStatusCode ?? 0
                    if (200..<300).contains(code) { sawSuccessPage = true }
                    // لا ندع 404 من رابط بديل يلغي نتيجة صفحة نجحت.
                    if case .notFound = error {
                        if !sawSuccessPage { lastError = .notFound }
                    } else {
                        lastError = error
                    }
                } catch {
                    lastError = .blocked
                }
                // فرصة قصيرة بين المحاولات بدل إغراق إنستغرام بالطلبات.
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        // وصلت صفحة ناجحة لكن تحليل contextJSON فشل: نستخرج منها بأي
        // طريقة أخرى قبل الاستسلام، لأن البيانات موجودة فيها فعلاً.
        if sawSuccessPage, !lastEmbedHTML.isEmpty,
           let fallback = try? await parseProfileHTML(lastEmbedHTML, reference: reference, createdAt: createdAt),
           !fallback.videos.isEmpty || fallback.account.followers > 0 {
            return fallback
        }

        // صفحة وصلت فعلاً ولم تُفهم: السبب تحليل لا «حساب غير موجود».
        throw sawSuccessPage ? DirectInstagramError.blocked : lastError
    }

    private func loadEmbedContext(
        url: URL,
        userAgent agent: String,
        handle: String,
        session: URLSession
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,ar;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.instagram.com/\(handle)/", forHTTPHeaderField: "Referer")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        // لا نرسل ترويسات Sec-Fetch* لأن Safari لا يرسلها أبداً؛ إرسالها مع
        // معرّف Safari يجعل الطلب يبدو آلياً فيُرد بصفحة محدودة.

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectInstagramError.badResponse }
        // نحفظ الرمز كي يظهر في سطر التشخيص (429 مقابل حجب مقابل مهلة).
        embedStatusCode = http.statusCode
        recordSample(
            sample(name: "embed", status: http.statusCode, body: String(data: data, encoding: .utf8) ?? ""),
            for: handle
        )
        if http.statusCode == 404 { throw DirectInstagramError.notFound }
        guard (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw DirectInstagramError.blocked
        }
        lastEmbedHTML = html
        if let context = embedContext(in: html) { return context }
        // نسجّل سبب الفشل ومقتطفاً من موضع البيانات، لنعرف هل وصلت
        // الصفحة بشكل مختلف أم أن التحليل هو المشكلة.
        recordSample("parsefail \(lastContextFailure) around=\(contextSnippet(in: html))", for: handle)
        throw DirectInstagramError.blocked
    }

    private func contextSnippet(in html: String) -> String {
        guard let range = html.range(of: "contextJSON") else { return "no-marker" }
        let tail = html[range.lowerBound...].prefix(70)
        return tail
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func makeEmbedResult(
        context: [String: Any],
        reference: InstagramProfileReference,
        createdAt: String?
    ) async throws -> DirectInstagramResult {
        let handle = (stringValue(context["username"]) ?? reference.handle).lowercased()
        guard InstagramLinkParser.isValidHandle(handle) else { throw DirectInstagramError.notFound }

        let nodes = embedMediaNodes(in: context)
        // صفحة الحساب لا تنشر مشاهدات الريلز، لكن صفحة كل ريل منفردة
        // تنشرها للزوار. نقرأها لكل فيديو، فتصبح المشاهدات والتقييم
        // أرقاماً حقيقية بلا تسجيل دخول.
        let posts = await enrichViewCounts(buildVideos(from: nodes, handle: handle), handle: handle)
        let followers = firstInt64(context["followers_count"], context["follower_count"]) ?? 0
        let following = firstInt64(context["following_count"], context["following"]) ?? 0
        let postsCount = firstInt(context["posts_count"]) ?? 0

        let user: [String: Any] = [
            "username": handle,
            "full_name": (context["full_name"] as? String) ?? handle,
            "profile_pic_url": (context["profile_pic_url"] as? String) ?? "",
            "is_verified": firstBool(context["is_verified"], context["verified"]),
            "edge_followed_by": ["count": followers],
            "edge_follow": ["count": following],
            "edge_owner_to_timeline_media": ["count": postsCount],
        ]

        // صفحة التضمين لا تعرض منشورات الحساب الخاص أو المقيّد، فنوضّح
        // السبب بدل الرسالة العامة.
        let hiddenPosts = posts.isEmpty && postsCount > 0
        return try makeResult(
            user: user,
            reference: reference,
            createdAt: createdAt,
            profileExact: true,
            postsOverride: posts.isEmpty ? nil : posts,
            postsCountOverride: postsCount > 0 ? postsCount : nil,
            errorOverride: hiddenPosts
                ? "إنستغرام لا يعرض منشورات هذا الحساب للزوار الآن؛ قد يكون خاصاً أو مقيّداً."
                : nil
        )
    }

    /// يفكّ سلسلة contextJSON المهربة داخل صفحة التضمين.
    ///
    /// نستخدم أولاً استخراجاً يدوياً حرفاً بحرف لا يعتمد على محرك التعابير
    /// النمطية، لأن السلسلة طويلة (نحو ٤٢ ألف حرف) وقد يختلف سلوك المحرك
    /// بين الأنظمة. ثم نعود إلى التعابير النمطية كاحتياط.
    private func embedContext(in html: String) -> [String: Any]? {
        // بعض النسخ تُرمّز علامات التنصيص ككيانات HTML قبل السلسلة.
        let normalized = html
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x22;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")

        if let payload = contextJSONPayload(in: normalized) {
            if let context = decodeContext(payload) { return context }
            lastContextFailure = "decode-failed len=\(payload.count)"
        } else {
            lastContextFailure = "no-payload"
        }

        // الصفحة تستخدم علامات تنصيص مزدوجة عادة، وبعض النسخ تستخدم مفردة.
        let patterns = [
            #""contextJSON"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            #"'contextJSON'\s*:\s*'((?:[^'\\]|\\.)*)'"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized) else { continue }

            let escaped = String(normalized[range])
            let isSingleQuoted = pattern.hasPrefix("'")
            // JSON لا يقبل علامات التنصيص المفردة؛ نحوّل السلسلة المفردة
            // إلى سلسلة JSON صالحة مع تهريب أي علامة مزدوجة داخلها.
            let jsonBody = isSingleQuoted
                ? escaped
                    .replacingOccurrences(of: "\\'", with: "'")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                : escaped
            if let context = decodeContext(jsonBody) { return context }
            lastContextFailure = "regex-decode-failed len=\(jsonBody.count)"
        }
        if lastContextFailure == "no-payload" { lastContextFailure = "regex-no-match" }
        return nil
    }

    /// يستخرج نص سلسلة contextJSON من HTML دون تعابير نمطية: يجد المفتاح،
    /// يعبر إغلاقه والنقطتين، ثم يقرأ حتى علامة التنصيص غير المهربة التي
    /// تُغلق السلسلة.
    private func contextJSONPayload(in html: String) -> String? {
        guard let marker = html.range(of: "contextJSON") else { return nil }
        let characters = Array(html)
        let count = characters.count
        var index = html.distance(from: html.startIndex, to: marker.upperBound)
        let limit = index + 80

        // بعد اسم المفتاح يأتي إغلاقه `"` ثم `:`. نتجاوز حتى النقطتين،
        // لا نتوقف عند إغلاق المفتاح كما كان يحدث سابقاً فيُقرأ ":".
        while index < count && characters[index] != ":" {
            if index > limit { return nil }
            index += 1
        }
        guard index < count else { return nil }
        index += 1

        // نتجاوز المسافات بين النقطتين وعلامة تنصيص القيمة.
        while index < count && characters[index].isWhitespace {
            if index > limit { return nil }
            index += 1
        }
        guard index < count, characters[index] == "\"" || characters[index] == "'" else { return nil }
        let quote = characters[index]
        index += 1

        var output = String()
        output.reserveCapacity(48 * 1024)
        while index < count {
            let character = characters[index]
            if character == "\\" {
                guard index + 1 < count else { return nil }
                output.append(character)
                output.append(characters[index + 1])
                index += 2
                continue
            }
            if character == quote { return output }
            output.append(character)
            index += 1
        }
        return nil
    }

    /// السلسلة الخام لـ contextJSON: يدوياً أولاً، ثم بتعبير نمطي احتياطاً.
    private func contextJSONString(in html: String) -> String? {
        if let payload = contextJSONPayload(in: html) { return payload }
        let pattern = #""contextJSON"\s*:\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func decodeContext(_ escaped: String) -> [String: Any]? {
        // `.fragmentsAllowed` ضروري: على iOS يرفض JSONSerialization تحليل
        // سلسلة نصية في المستوى الأعلى بلا هذا الخيار. غيابه هنا كان يجعل
        // كل بيانات إنستغرام تصل ثم تُهمَل بصمت.
        guard let wrapped = ("\"" + escaped + "\"").data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: wrapped, options: [.fragmentsAllowed]) as? String,
              let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // بعض النسخ تغلّف الكائن بمفتاح context، وأخرى تعيده مباشرة.
        return (root["context"] as? [String: Any]) ?? root
    }

    /// يفكّ contextJSON كاملاً مع الاحتفاظ بـ `gql_data`، لأن صفحة الريل
    /// المفردة تضع `video_view_count` داخل `gql_data.shortcode_media`،
    /// و`decodeContext` تُسقط هذا القسم.
    private func decodeContextRoot(_ escaped: String) -> [String: Any]? {
        guard let wrapped = ("\"" + escaped + "\"").data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: wrapped, options: [.fragmentsAllowed]) as? String,
              let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            return nil
        }
        return root
    }

    /// يُكمل مشاهدات الفيديوهات من صفحة تضمين كل منشور منفرد.
    ///
    /// صفحة الحساب العامة لا تحتوي عدّاد مشاهدات، لكن صفحة المنشور
    /// المفردة تعرض `video_view_count` لأي زائر بلا تسجيل دخول. نطلبها
    /// لفيديوهات قليلة (أحدث المنشورات المحمّلة) ثم نضع الرقم الحقيقي
    /// في المنشور، فيصبح مجموع المشاهدات والتقييم الأسبوعي حقيقياً.
    private func enrichViewCounts(_ videos: [VideoItem], handle: String) async -> [VideoItem] {
        lastViewEnrichment = ""
        let candidates = videos.filter { $0.isVideo && !$0.viewsExact }
        let shortcodes = Array(Set(candidates.compactMap { shortcode(from: $0) }))
        guard !shortcodes.isEmpty else { return videos }

        var counts: [String: Int64] = [:]
        for shortcode in shortcodes {
            if let cached = viewCountCache[shortcode] { counts[shortcode] = cached }
        }
        let missing = shortcodes.filter { counts[$0] == nil }

        // ثلاث طلبات متوازية في كل دفعة: سريع بلا إغراق إنستغرام.
        var index = 0
        while index < missing.count {
            let end = min(index + 3, missing.count)
            let chunk = Array(missing[index..<end])
            let fetched = await withTaskGroup(of: (String, Int64?).self) { group -> [(String, Int64?)] in
                for code in chunk {
                    group.addTask { () -> (String, Int64?) in
                        let value = await self.fetchViewCount(shortcode: code, handle: handle)
                        return (code, value)
                    }
                }
                var results: [(String, Int64?)] = []
                for await item in group { results.append(item) }
                return results
            }
            for (code, value) in fetched {
                guard let value else { continue }
                counts[code] = value
                // نكتب الذاكرة في المهمة الأم فقط، لا داخل المهام المتوازية.
                viewCountCache[code] = value
            }
            index = end
            if index < missing.count {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        lastViewEnrichment = "views \(counts.count)/\(shortcodes.count)"
        guard !counts.isEmpty else { return videos }
        return videos.map { video in
            guard video.isVideo, !video.viewsExact,
                  let code = shortcode(from: video),
                  let views = counts[code],
                  views > 0 else { return video }
            var updated = video
            updated.views = views
            // العدد المنشور في صفحة الريل هو العدد الفعلي لا تقدير.
            updated.viewsExact = true
            return updated
        }
    }

    /// رقم المنشور (shortcode) من رابط مشاركته.
    private func shortcode(from video: VideoItem) -> String? {
        guard let link = video.shareUrl,
              let url = URL(string: link),
              let last = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }),
              last.range(of: #"^[A-Za-z0-9_-]{5,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return last
    }

    /// يقرأ عدّاد المشاهدات من صفحة تضمين منشور واحد.
    private func fetchViewCount(shortcode: String, handle: String) async -> Int64? {
        guard let url = URL(string: "https://www.instagram.com/p/\(shortcode)/embed/") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await embedSession.data(for: request) else {
            recordSample("view \(shortcode) transport-fail", for: handle)
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let html = String(data: data, encoding: .utf8) else {
            recordSample("view \(shortcode) status=\(status)", for: handle)
            return nil
        }
        guard let payload = contextJSONString(in: html),
              let root = decodeContextRoot(payload) else {
            recordSample("view \(shortcode) status=\(status) ctx=0", for: handle)
            return nil
        }
        guard let media = (root["gql_data"] as? [String: Any])?["shortcode_media"] as? [String: Any] else {
            recordSample("view \(shortcode) status=\(status) ctx=1 gql=0", for: handle)
            return nil
        }
        guard let mediaShortcode = stringValue(media["shortcode"]),
              mediaShortcode.caseInsensitiveCompare(shortcode) == .orderedSame,
              let views = firstInt64(
                media["video_view_count"],
                media["video_play_count"],
                media["play_count"],
                media["view_count"]
              ),
              views > 0 else {
            recordSample("view \(shortcode) status=\(status) ctx=1 gql=1 count=0", for: handle)
            return nil
        }
        return views
    }

    /// منشورات التضمين: مصفوفة graphql_media، أو كائن واحد، أو خلاصة
    /// edge_owner_to_timeline_media حسب نسخة الصفحة.
    private func embedMediaNodes(in context: [String: Any]) -> [[String: Any]] {
        var nodes: [[String: Any]] = []

        if let media = context["graphql_media"] as? [Any] {
            for item in media {
                guard let dictionary = item as? [String: Any] else { continue }
                if let node = dictionary["shortcode_media"] as? [String: Any] {
                    nodes.append(node)
                } else if dictionary["shortcode"] != nil || dictionary["code"] != nil {
                    nodes.append(dictionary)
                }
            }
        }

        if nodes.isEmpty, let single = context["shortcode_media"] as? [String: Any] {
            nodes.append(single)
        }

        if nodes.isEmpty,
           let timeline = context["edge_owner_to_timeline_media"] as? [String: Any],
           let edges = timeline["edges"] as? [Any] {
            for edge in edges {
                if let node = (edge as? [String: Any])?["node"] as? [String: Any] {
                    nodes.append(node)
                }
            }
        }

        return nodes
    }

    // MARK: - احتياط HTML

    private func fetchHTML(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        let page = try await load(reference.inputURL)
        recordSample(sample(name: "profile", status: 200, body: page.html), for: reference.handle)
        return try await parseProfileHTML(page.html, reference: reference, createdAt: createdAt)
    }

    /// يقرأ صفحة الملف نفسها عبر محرك Safari داخل التطبيق. إنستغرام يفحص
    /// بصمة الاتصال، وطلبات URLSession تُحجب على بعض الشبكات بينما
    /// WKWebView يمرّ كزيارة عادية. نجرّب التضمين أولاً لأنه أخف وأسرع.
    private func fetchWeb(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        let handle = reference.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { throw DirectInstagramError.invalidLink }

        if let embedURL = URL(string: "https://www.instagram.com/\(handle)/embed/"),
           let html = try? await WebPageLoader.shared.html(from: embedURL, userAgent: userAgent, timeout: 15) {
            recordSample(sample(name: "web", status: 200, body: html), for: handle)
            if let context = embedContext(in: html) {
                return try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
            }
        }

        guard let profileURL = URL(string: "https://www.instagram.com/\(handle)/") else {
            throw DirectInstagramError.invalidLink
        }
        let html = try await WebPageLoader.shared.html(from: profileURL, userAgent: userAgent, timeout: 15)
        return try await parseProfileHTML(html, reference: reference, createdAt: createdAt)
    }

    /// قراءة صفحة التضمين عبر خدمة تقرأ الموقع من شبكتها هي، لا من شبكة
    /// المستخدم. هذا هو المسار الذي ينجح عندما يعطي إنستغرام جهاز المستخدم
    /// نسخة محدودة (اسم وصورة بلا منشورات) أو يحجب الطلبات المباشرة.
    /// لا يُرسل إلا اسم الحساب العام، وهو معلومة منشورة أصلاً.
    private func fetchRelay(reference: InstagramProfileReference, createdAt: String?) async throws -> DirectInstagramResult {
        let handle = reference.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { throw DirectInstagramError.invalidLink }
        guard let target = URL(string: "https://www.instagram.com/\(handle)/embed/") else {
            throw DirectInstagramError.invalidLink
        }
        let raw = target.absoluteString
        let key = handle.lowercased()
        var tokens: [String] = []
        var lastError: DirectInstagramError = .blocked

        func success(_ name: String, _ result: DirectInstagramResult) -> DirectInstagramResult {
            tokens.append("\(name)✓\(result.videos.count)")
            relayDetails[key] = tokens.joined(separator: " · ")
            return result
        }

        // أ) قارئ صفحات يعيد HTML كاملاً بعد تنفيذ JavaScript. الأسرع.
        if let url = URL(string: "https://r.jina.ai/\(raw)") {
            do {
                let (status, body) = try await relayGet(url, accept: "text/html")
                recordSample(sample(name: "jina", status: status, body: body), for: key)
                if let context = embedContext(in: body) {
                    let result = try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
                    return success("jina", result)
                }
                tokens.append("jina✗\(status)")
                lastError = .badResponse
            } catch {
                tokens.append("jina✗t")
                lastError = .blocked
            }
        }

        // ب) وسيط Google: يفتح الصفحة من خوادم Google نفسها. ينجح غالباً
        //    حتى عندما تحجب الشبكة خدمات القراءة المتخصصة.
        if let url = URL(string: "https://www-instagram-com.translate.goog/\(handle)/embed/?_x_tr_sl=auto&_x_tr_tl=en&_x_tr_hl=en") {
            do {
                let (status, body) = try await relayGet(url, accept: "text/html")
                recordSample(sample(name: "google", status: status, body: body), for: key)
                if let context = embedContext(in: body) {
                    let result = try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
                    return success("google", result)
                }
                tokens.append("google✗\(status)")
                lastError = .badResponse
            } catch {
                tokens.append("google✗t")
                lastError = .blocked
            }
        }

        // ج) خدمة ثالثة تعيد الصفحة داخل JSON.
        var components = URLComponents(string: "https://api.microlink.io/")
        components?.queryItems = [
            URLQueryItem(name: "url", value: raw),
            URLQueryItem(name: "meta", value: "false"),
            URLQueryItem(name: "data.html.selector", value: "body"),
        ]
        if let url = components?.url {
            do {
                let (status, body) = try await relayGet(url, accept: "application/json")
                recordSample(sample(name: "micro", status: status, body: body), for: key)
                if let data = body.data(using: .utf8),
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = root["data"] as? [String: Any],
                   let html = payload["html"] as? String,
                   let context = embedContext(in: html) {
                    let result = try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
                    return success("micro", result)
                }
                // بعض الاستجابات تعيد HTML خاماً بدل JSON.
                if let context = embedContext(in: body) {
                    let result = try await makeEmbedResult(context: context, reference: reference, createdAt: createdAt)
                    return success("micro", result)
                }
                tokens.append("micro✗\(status)")
                lastError = .badResponse
            } catch {
                tokens.append("micro✗t")
                lastError = .blocked
            }
        }

        relayDetails[key] = tokens.joined(separator: " · ")
        throw lastError
    }

    /// رمز الاستجابة مع النص. لا يرمي عند 4xx/5xx كي نستطيع تدوين الرمز
    /// في التشخيص بدل فشل صامت.
    private func relayGet(_ url: URL, accept: String) async throws -> (status: Int, body: String) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // ترويسة خاصة بخدمة القراءة: أعطنا HTML الصفحة لا نصها المختصر.
        request.setValue("html", forHTTPHeaderField: "x-respond-with")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let text = String(data: data, encoding: .utf8) else {
            throw DirectInstagramError.blocked
        }
        return (http.statusCode, text)
    }

    private func parseProfileHTML(
        _ html: String,
        reference: InstagramProfileReference,
        createdAt: String?
    ) async throws -> DirectInstagramResult {
        if html.contains("Sorry, this page isn't available") ||
            html.contains("الصفحة غير متوفرة") ||
            html.contains("Page Not Found") {
            throw DirectInstagramError.notFound
        }

        let objects = jsonObjects(in: html)
        let description = metaContent(in: html, property: "og:description") ?? ""
        let title = metaContent(in: html, property: "og:title") ?? ""
        let image = metaContent(in: html, property: "og:image") ?? ""
        let profileURL = metaContent(in: html, property: "og:url") ?? reference.canonicalURL

        // أ) بيانات JSON كاملة (الملف + المنشورات) إن أرسلها إنستغرام للزائر.
        var user = embeddedUser(in: html)
        if user == nil {
            for object in objects {
                if let found = findUser(in: object) { user = found; break }
            }
        }

        var nodes: [[String: Any]] = []
        for object in objects {
            collectMediaNodes(in: object, into: &nodes)
            if nodes.count >= 40 { break }
        }
        if nodes.isEmpty {
            nodes = mediaNodesFromScriptJSON(in: html)
        }

        if let user {
            let profileHandle = (stringValue(user["username"]) ?? reference.handle).lowercased()
            let posts = await enrichViewCounts(buildVideos(from: nodes, handle: profileHandle), handle: profileHandle)
            let result = try makeResult(
                user: user,
                reference: reference,
                createdAt: createdAt,
                profileExact: true,
                postsOverride: posts.isEmpty ? nil : posts
            )
            if !result.videos.isEmpty || result.account.followers > 0 {
                return result
            }
        }

        // ب) منشورات JSON بلا كائن ملف كامل: نستخرج اسم الحساب من المنشور.
        if !nodes.isEmpty {
            let handle = usernameFromNodes(nodes) ?? referencedHandle(from: title) ?? reference.handle
            let followers = humanCount(in: description, markers: ["followers", "follower", "متابع"])
            let following = humanCount(in: description, markers: ["following", "يتابع"])
            let postsCount = humanCount(in: description, markers: ["posts", "post", "منشور"])
            let displayName = cleanTitle(title, handle: handle)
            let synthetic: [String: Any] = [
                "username": handle,
                "full_name": displayName,
                "profile_pic_url": image,
                "is_verified": title.contains("Verified"),
                "edge_followed_by": ["count": followers],
                "edge_follow": ["count": following],
                "edge_owner_to_timeline_media": ["count": postsCount, "edges": []],
            ]
            return try makeResult(
                user: synthetic,
                reference: reference,
                createdAt: createdAt,
                profileExact: false,
                postsOverride: await enrichViewCounts(buildVideos(from: nodes, handle: handle), handle: handle),
                postsCountOverride: postsCount > 0 ? Int(postsCount) : nil
            )
        }

        // ج) وسوم og فقط: نضيف الحساب ونعلّمه بوضوح أن الأرقام لم تُقرأ،
        // بدل عرض صفر كأنه رقم حقيقي.
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
            postsCountExact: false,
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
            status: "pending",
            error: "لم تُرجع إنستغرام منشورات هذا الحساب لهذا الطلب. قد تكون الشبكة تحجب القراءة أو الحساب مقيّداً؛ اضغط «مزامنة» لإعادة المحاولة.",
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
        profileExact: Bool,
        postsOverride: [VideoItem]? = nil,
        postsCountOverride: Int? = nil,
        errorOverride: String? = nil
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
        let totalPosts = postsCountOverride ?? firstInt(media["count"]) ?? 0
        let edges = media["edges"] as? [[String: Any]] ?? []

        let videos: [VideoItem]
        if let postsOverride {
            videos = postsOverride.sorted { $0.createTime > $1.createTime }
        } else {
            var seen = Set<String>()
            var built: [VideoItem] = []
            for edge in edges {
                guard let node = edge["node"] as? [String: Any] else { continue }
                guard let item = videoItem(from: node, handle: handle) else { continue }
                guard seen.insert(item.id).inserted else { continue }
                built.append(item)
            }
            videos = built.sorted { $0.createTime > $1.createTime }
        }

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

        // إذا عرفنا عدد منشورات الحساب أو متابعيه لكن لم نقرأ أي منشور،
        // فالأرقام المعروضة ستكون أصفاراً غير حقيقية. نعلّم الحساب pending
        // حتى تظهر «—» مع سبب واضح بدل 0.
        let postsUnread = videos.isEmpty && (totalPosts > 0 || followers > 0)

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
            status: postsUnread ? "pending" : "public",
            error: postsUnread
                ? (errorOverride ?? "لم تُقرأ منشورات الحساب بعد؛ ستُحدَّث الأرقام تلقائياً.")
                : nil,
            lastSyncedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            createdAt: createdAt ?? ISO8601DateFormatter.nabd.string(from: Date())
        )
        return DirectInstagramResult(account: account, videos: videos)
    }

    private func videoItem(from node: [String: Any], handle: String) -> VideoItem? {
        let shortcode = stringValue(node["shortcode"]) ?? ""
        let id = stringValue(node["id"]) ?? shortcode
        guard !id.isEmpty else { return nil }

        let created = firstInt(node["taken_at_timestamp"], node["taken_at"], node["takenAt"]) ?? 0
        let productType = (stringValue(node["product_type"]) ?? "").lowercased()
        let mediaType = firstInt(node["media_type"]) ?? 0
        let isVideo = firstBool(node["is_video"], node["isVideo"])
            || productType == "clips"
            || mediaType == 2
        let viewsValue = firstInt64(
            node["video_view_count"],
            node["video_play_count"],
            node["play_count"],
            node["view_count"]
        )
        let views = isVideo ? (viewsValue ?? 0) : 0
        let likes = firstInt64(
            (node["edge_liked_by"] as? [String: Any])?["count"],
            (node["edge_media_preview_like"] as? [String: Any])?["count"],
            node["like_count"],
            node["likeCount"]
        ) ?? 0
        let comments = firstInt64(
            (node["edge_media_to_comment"] as? [String: Any])?["count"],
            node["comment_count"],
            node["commentCount"]
        ) ?? 0
        let caption = firstString(
            captionText(in: node),
            (node["caption"] as? [String: Any])?["text"],
            node["caption"] as? String
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

        return VideoItem(
            id: id,
            title: caption,
            coverUrl: cover,
            shareUrl: shareURL,
            duration: firstInt(node["video_duration"], node["videoDuration"]) ?? 0,
            createTime: created,
            views: views,
            likes: likes,
            comments: comments,
            shares: 0,
            // مشاهدات الفيديو فقط تُنشر. الصور لا تُحتسب مشاهدات، والفيديو
            // الذي لا يحمل عدد مشاهدات يبقى غير معروف لا صفراً مؤكداً.
            viewsExact: !isVideo || viewsValue != nil,
            isVideo: isVideo
        )
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

    /// يجمع كل كتل JSON المدمجة في الصفحة: وسوم application/json،
    /// وwindow._sharedData، وكائنات contextJSON التي تعيدها صفحات
    /// التضمين. إنستغرام يغيّر مكان البيانات بين نسخة وأخرى، لذا نقرأ
    /// من كل الأشكال بدل الاعتماد على شكل واحد.
    private func jsonObjects(in html: String) -> [Any] {
        var objects: [Any] = []

        let scriptPattern = #"<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>"#
        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let bodyRange = Range(match.range(at: 1), in: html) else { continue }
                appendJSON(String(html[bodyRange]), into: &objects)
            }
        }

        let inlinePatterns = [
            #"window\._sharedData\s*=\s*(\{[\s\S]*?\});"#,
            #"window\.__additionalDataLoaded\([^,]*,\s*(\{[\s\S]*?\})\);"#,
        ]
        for pattern in inlinePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let bodyRange = Range(match.range(at: 1), in: html) else { continue }
                appendJSON(String(html[bodyRange]), into: &objects)
            }
        }

        // contextJSON يصل غالباً كسلسلة JSON مهربة داخل كائن أكبر.
        let contextPattern = #""contextJSON"\s*:\s*"((?:[^"\\]|\\.)*)""#
        if let regex = try? NSRegularExpression(pattern: contextPattern) {
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let bodyRange = Range(match.range(at: 1), in: html) else { continue }
                let escaped = String(html[bodyRange])
                guard let data = ("\"" + escaped + "\"").data(using: .utf8),
                      let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { continue }
                appendJSON(decoded, into: &objects)
            }
        }

        return objects
    }

    private func appendJSON(_ raw: String, into objects: inout [Any]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count > 1 else { return }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return
        }
        objects.append(object)
    }

    /// يجمع عقد المنشورات من أي كائن JSON مهما كان عمقه.
    private func collectMediaNodes(
        in object: Any,
        into nodes: inout [[String: Any]],
        depth: Int = 0
    ) {
        guard depth < 40, nodes.count < 60 else { return }
        if let dictionary = object as? [String: Any] {
            if isMediaNode(dictionary) {
                nodes.append(dictionary)
                return
            }
            for value in dictionary.values {
                collectMediaNodes(in: value, into: &nodes, depth: depth + 1)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectMediaNodes(in: value, into: &nodes, depth: depth + 1)
            }
        }
    }

    /// عقدة منشور حقيقية: تحمل كوداً ووقت نشر، وأحد حقول الوسائط.
    private func isMediaNode(_ dictionary: [String: Any]) -> Bool {
        guard dictionary["edge_owner_to_timeline_media"] == nil else { return false }
        let hasCode = dictionary["shortcode"] != nil || dictionary["code"] != nil
        let hasTime = dictionary["taken_at_timestamp"] != nil
            || dictionary["taken_at"] != nil
            || dictionary["takenAt"] != nil
        guard hasCode, hasTime else { return false }
        let hasMediaMarker = dictionary["is_video"] != nil
            || dictionary["media_type"] != nil
            || dictionary["video_view_count"] != nil
            || dictionary["video_play_count"] != nil
            || dictionary["like_count"] != nil
            || dictionary["edge_liked_by"] != nil
            || dictionary["edge_media_preview_like"] != nil
            || dictionary["display_url"] != nil
            || dictionary["thumbnail_src"] != nil
            || dictionary["image_versions2"] != nil
        return hasMediaMarker
    }

    /// قراءة عقد المنشورات من وسوم JSON وحدها (للصفحات التي تضع
    /// البيانات في script type=application/json فقط).
    private func mediaNodesFromScriptJSON(in html: String) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        for object in jsonObjects(in: html) {
            collectMediaNodes(in: object, into: &nodes)
            if nodes.count >= 60 { break }
        }
        return nodes
    }

    /// اسم صاحب المنشور من العقود.
    private func usernameFromNodes(_ nodes: [[String: Any]]) -> String? {
        for node in nodes {
            if let owner = node["owner"] as? [String: Any],
               let name = firstString(owner["username"], owner["name"]) {
                return name.lowercased()
            }
            if let user = node["user"] as? [String: Any],
               let name = firstString(user["username"]) {
                return name.lowercased()
            }
            if let name = firstString(
                node["ownerUsername"],
                node["username"],
                node["owner_username"]
            ) {
                return name.lowercased()
            }
        }
        return nil
    }

    /// يبني عناصر المنشورات من عقود JSON المستخرجة.
    /// عند معرفة اسم الحساب نستبعد أي منشور يخص حساباً آخر (منشورات
    /// مقترحة تظهر داخل الصفحة) حتى لا تُنسب أرقامها للحساب الخطأ.
    private func buildVideos(from nodes: [[String: Any]], handle: String? = nil) -> [VideoItem] {
        var seen = Set<String>()
        var videos: [VideoItem] = []
        let target = (handle ?? "").lowercased()
        for node in nodes {
            let nodeHandle = usernameFromNodes([node])
            if !target.isEmpty,
               let nodeHandle,
               nodeHandle != target {
                continue
            }
            let owner = nodeHandle ?? target
            guard let item = videoItem(from: node, handle: owner) else { continue }
            guard seen.insert(item.id).inserted else { continue }
            videos.append(item)
        }
        return videos.sorted { $0.createTime > $1.createTime }
    }

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
              let first = edges.first,
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

    /// يقرأ «104M Followers» أو «1,234 Followers» أو «١٢٣٤ متابع» ويعيد الرقم.
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
            guard let numberRange = prefix.range(
                of: #"([0-9][0-9,\.]*)\s*([kmb])?\s*$"#,
                options: .regularExpression
            ) else { continue }
            var rawNumber = String(prefix[numberRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            var multiplier: Double = 1
            if let last = rawNumber.last, "kmb".contains(last) {
                switch last {
                case "k": multiplier = 1_000
                case "m": multiplier = 1_000_000
                case "b": multiplier = 1_000_000_000
                default: break
                }
                rawNumber.removeLast()
            }
            rawNumber = rawNumber
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(rawNumber) else { continue }
            return Int64((value * multiplier).rounded())
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
