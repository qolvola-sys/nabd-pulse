#if MUTABAA
import Foundation
import UIKit
import WebKit

/// نتيجة قراءة صفحة الحساب من الويب.
struct WeeklyScanPayload {
    var videos: [VideoItem]
    /// بيانات الملف الشخصي الدقيقة (statsV2) إن توفرت.
    var profile: [String: Any]?
    /// هل كل المشاهدات أرقام دقيقة ١٠٠٪؟
    var exact: Bool
    /// هل غطّت القراءة كل نافذة آخر ٧ أيام؟
    var complete: Bool
    var hasMore: Bool
}

/// يفتح صفحة الحساب العامة داخل WKWebView حقيقي، ويعترض استجابات
/// `api/post/item_list/` التي يوقّعها TikTok بنفسه. بهذا نحصل على كل
/// منشورات آخر ٧ أيام مع أرقام مشاهدات دقيقة، بدون خادم وبدون مفاتيح
/// وبدون إعادة تنفيذ توقيعات TikTok.
///
/// لا يظهر أي شيء للمستخدم: عرض الصفحة شفاف تقريباً وخارج مسار اللمس.
@MainActor
final class WeeklyWebScanner: NSObject, WKNavigationDelegate {
    static let shared = WeeklyWebScanner()

    private var webView: WKWebView?
    private var navContinuation: CheckedContinuation<Void, Never>?
    private var navTimeout: Task<Void, Never>?
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    private var pollInterval: UInt64 { 1_250_000_000 }

    // MARK: - القراءة

    /// يقرأ كل منشورات الحساب حتى يغطي نافذة آخر ٧ أيام (أو حتى نهاية القائمة).
    func scan(handle: String, cutoff: Int) async -> WeeklyScanPayload? {
        await acquire()
        defer { release() }

        var payload = await runScan(handle: handle, cutoff: cutoff, rounds: 14)
        if shouldRetry(payload) {
            // محاولة ثانية بعد مهلة قصيرة: أحياناً يعيد TikTok صفحة تحقق مؤقتة.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            payload = await runScan(handle: handle, cutoff: cutoff, rounds: 10)
        }
        return payload
    }

    /// لا نعيد المحاولة لحساب جديد بلا منشورات: الصفر رقم حقيقي.
    private func shouldRetry(_ payload: WeeklyScanPayload?) -> Bool {
        guard let payload else { return true }
        if !payload.videos.isEmpty { return false }
        let postCount = Int(intValue(payload.profile?["posts"]))
        return postCount > 0
    }

    /// يضمن أن قراءة واحدة فقط تستخدم المتصفح المخفي في أي لحظة.
    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    private func runScan(handle: String, cutoff: Int, rounds: Int) async -> WeeklyScanPayload? {
        guard let url = URL(string: "https://www.tiktok.com/@\(handle)?lang=en") else { return nil }
        await load(url)

        try? await Task.sleep(nanoseconds: 700_000_000)

        var items: [String: [String: Any]] = [:]
        var cards: [String: String] = [:]
        var profile: [String: Any]?
        var hasMore = true
        var sawOlderThanCutoff = false
        var stagnant = 0
        var previousCount = 0

        for _ in 0..<rounds {
            _ = await evaluate("(function(){try{window.__nabd&&window.__nabd.scroll()}catch(e){};return 1})()")
            try? await Task.sleep(nanoseconds: pollInterval)

            let rawPayload = await evaluate("window.__nabd?window.__nabd.payload():null")
            guard let payload = rawPayload as? [String: Any] else {
                stagnant += 1
                if stagnant >= 5 && items.isEmpty { break }
                continue
            }

            if let list = payload["items"] as? [[String: Any]] {
                for item in list {
                    guard let id = item["id"] as? String, !id.isEmpty else { continue }
                    if items[id] == nil { items[id] = item }
                }
            }
            if let list = payload["cards"] as? [[String: Any]] {
                for card in list {
                    guard let id = card["id"] as? String, !id.isEmpty else { continue }
                    if cards[id] == nil, let text = card["viewsText"] as? String, !text.isEmpty {
                        cards[id] = text
                    }
                }
            }
            if profile == nil, let value = payload["profile"] as? [String: Any] {
                profile = value
            }
            if let more = payload["hasMore"] as? Bool { hasMore = more }

            let count = items.count
            if count <= previousCount { stagnant += 1 } else { stagnant = 0 }
            previousCount = count

            let times = items.values.compactMap { raw -> Int? in
                // أول ٣ منشورات قد تكون مثبتة (قديمة)؛ لا نحسبها عند قياس
                // تغطية النافذة حتى لا نعتبر الأسبوع مكتملاً قبل أوانه.
                let position = raw["idx"] as? Int ?? 0
                guard position >= 3 else { return nil }
                let created = raw["createTime"] as? Int ?? 0
                return created > 0 ? created : nil
            }.sorted()
            if let oldest = times.first, oldest < cutoff, count >= 8 {
                sawOlderThanCutoff = true
            }

            if sawOlderThanCutoff || !hasMore { break }
            if count >= 400 { break }
            if stagnant >= 4 && count > 0 { break }
            if stagnant >= 6 && count == 0 { break }
        }

        var videos: [VideoItem] = []
        var exact = true

        for raw in items.values {
            guard let id = raw["id"] as? String else { continue }
            var created = Int(intValue(raw["createTime"]))
            if created <= 0 { created = DirectTikTokService.createTime(from: id) }
            let videoExact = raw["viewsExact"] as? Bool ?? false
            if !videoExact { exact = false }
            videos.append(VideoItem(
                id: id,
                title: raw["title"] as? String ?? "",
                coverUrl: raw["cover"] as? String,
                shareUrl: "https://www.tiktok.com/@\(handle)/video/\(id)",
                duration: 0,
                createTime: created,
                views: intValue(raw["views"]),
                likes: intValue(raw["likes"]),
                comments: intValue(raw["comments"]),
                shares: intValue(raw["shares"]),
                viewsExact: videoExact,
                isVideo: true
            ))
        }

        // احتياط: لو لم نلتقط استجابات API، نقرأ بطاقات الصفحة (أرقام مختصرة).
        if videos.isEmpty && !cards.isEmpty {
            exact = false
            for (id, text) in cards {
                videos.append(VideoItem(
                    id: id,
                    title: "",
                    coverUrl: nil,
                    shareUrl: "https://www.tiktok.com/@\(handle)/video/\(id)",
                    duration: 0,
                    createTime: DirectTikTokService.createTime(from: id),
                    views: Self.abbreviatedCount(text),
                    likes: 0,
                    comments: 0,
                    shares: 0,
                    viewsExact: false,
                    isVideo: true
                ))
            }
        }

        // حساب جديد بلا منشورات: الصفر رقم حقيقي وليس فشل قراءة.
        if videos.isEmpty, let profile, Int(intValue(profile["posts"])) == 0 {
            return WeeklyScanPayload(
                videos: [],
                profile: profile,
                exact: true,
                complete: true,
                hasMore: false
            )
        }

        guard !videos.isEmpty else { return nil }
        videos.sort { $0.createTime > $1.createTime }

        // نعتبر النافذة مكتملة إذا تجاوزنا حد البداية، أو انتهت القائمة،
        // أو عرفنا من statsV2 أننا قرأنا كل منشورات الحساب.
        let profilePosts = Int(intValue(profile?["posts"]))
        let readEveryPost = profilePosts > 0 && videos.count >= profilePosts
        let complete = sawOlderThanCutoff || !hasMore || readEveryPost

        return WeeklyScanPayload(
            videos: videos,
            profile: profile,
            exact: exact,
            complete: complete,
            hasMore: hasMore
        )
    }

    // MARK: - العرض المخفي

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.hookScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        view.customUserAgent = desktopUA
        view.navigationDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.alpha = 0.01
        view.isUserInteractionEnabled = false

        if let window = Self.hostWindow() {
            view.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
            window.addSubview(view)
        }

        webView = view
        return view
    }

    private static func hostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
    }

    private func load(_ url: URL) async {
        let view = ensureWebView()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navContinuation = continuation
            navTimeout?.cancel()
            navTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishNavigation()
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 22)
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            view.load(request)
        }
    }

    private func finishNavigation() {
        navTimeout?.cancel()
        navTimeout = nil
        if let continuation = navContinuation {
            navContinuation = nil
            continuation.resume()
        }
    }

    private func evaluate(_ script: String) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(script)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigation()
    }

    // MARK: - أدوات

    private func intValue(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) ?? 0 }
        return 0
    }

    /// يحوّل «183.4K» أو «1.5M» إلى رقم تقريبي (للاحتياط فقط).
    static func abbreviatedCount(_ text: String) -> Int64 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { return 0 }
        var multiplier: Double = 1
        if value.hasSuffix("K") { multiplier = 1_000; value.removeLast() }
        else if value.hasSuffix("M") { multiplier = 1_000_000; value.removeLast() }
        else if value.hasSuffix("B") { multiplier = 1_000_000_000; value.removeLast() }
        value = value.replacingOccurrences(of: ",", with: "")
        guard let number = Double(value) else { return 0 }
        return Int64(number * multiplier)
    }

    // MARK: - السكربت المحقون

    /// يعترض استجابات قائمة المنشورات التي يطلبها TikTok بنفسه، ويجمعها،
    /// ثم يمرّر الصفحة للأسفل لتحميل المزيد.
    private static let hookScript = #"""
    (function () {
      if (window.__nabd) { return; }
      var state = { items: {}, order: [], hasMore: true };
      window.__nabd = state;

      function num(value) {
        var number = Number(value);
        return isFinite(number) ? number : 0;
      }

      function ingest(object) {
        if (!object || !object.itemList || !object.itemList.length) { return; }
        if (typeof object.hasMore === "boolean") { state.hasMore = object.hasMore; }
        for (var i = 0; i < object.itemList.length; i++) {
          var item = object.itemList[i];
          if (!item || !item.id) { continue; }
          var id = String(item.id);
          if (state.items[id]) { continue; }
          var stats = item.stats || {};
          var stats2 = item.statsV2 || {};
          var video = item.video || {};
          var exactViews = stats2.playCount !== undefined &&
                           stats2.playCount !== null &&
                           stats2.playCount !== "";
          state.items[id] = {
            id: id,
            createTime: num(item.createTime),
            views: num(exactViews ? stats2.playCount : stats.playCount),
            likes: num(stats2.diggCount || stats.diggCount),
            comments: num(stats2.commentCount || stats.commentCount),
            shares: num(stats2.shareCount || stats.shareCount),
            title: item.desc || "",
            cover: video.cover || video.originCover || video.dynamicCover || "",
            viewsExact: exactViews
          };
          state.order.push(id);
        }
      }

      var originalFetch = window.fetch;
      window.fetch = function () {
        var args = arguments;
        return originalFetch.apply(this, args).then(function (response) {
          try {
            var url = String((args[0] && args[0].url) || args[0] || "");
            if (url.indexOf("/api/post/item_list/") >= 0) {
              response.clone().text().then(function (text) {
                try { ingest(JSON.parse(text)); } catch (e) {}
              }).catch(function () {});
            }
          } catch (e) {}
          return response;
        });
      };

      var originalOpen = XMLHttpRequest.prototype.open;
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__nabdURL = String(url);
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var request = this;
        request.addEventListener("load", function () {
          try {
            if (String(request.__nabdURL || "").indexOf("/api/post/item_list/") >= 0) {
              ingest(JSON.parse(request.responseText));
            }
          } catch (e) {}
        });
        return originalSend.apply(this, arguments);
      };

      state.scroll = function () {
        try {
          var scroller = document.scrollingElement || document.documentElement;
          window.scrollTo(0, scroller.scrollHeight);
          scroller.scrollTop = scroller.scrollHeight;
        } catch (e) {}
        return 1;
      };

      function profileInfo() {
        try {
          var element = document.getElementById("__UNIVERSAL_DATA_FOR_REHYDRATION__");
          if (!element) { return null; }
          var root = JSON.parse(element.textContent);
          var scope = root.__DEFAULT_SCOPE__ || {};
          var detail = scope["webapp.user-detail"] || {};
          var info = detail.userInfo || {};
          var user = info.user || {};
          var stats = info.stats || {};
          var stats2 = info.statsV2 || {};
          if (!user.uniqueId) { return null; }
          return {
            handle: String(user.uniqueId),
            name: user.nickname || "",
            avatar: user.avatarLarger || user.avatarMedium || "",
            verified: !!user.verified,
            followers: num(stats2.followerCount || stats.followerCount),
            following: num(stats2.followingCount || stats.followingCount),
            hearts: num(stats2.heartCount || stats2.heart || stats.heartCount || stats.heart),
            posts: num(stats2.videoCount || stats.videoCount)
          };
        } catch (e) { return null; }
      }

      state.payload = function () {
        var items = [];
        for (var i = 0; i < state.order.length; i++) {
          var item = state.items[state.order[i]];
          if (item) { item.idx = i; items.push(item); }
        }
        var cards = [];
        try {
          var elements = document.querySelectorAll('[data-e2e="user-post-item"]');
          for (var k = 0; k < elements.length; k++) {
            var link = elements[k].querySelector('a[href*="/video/"]');
            if (!link) { continue; }
            var match = String(link.getAttribute("href")).match(/\/video\/(\d+)/);
            if (!match) { continue; }
            var views = elements[k].querySelector('strong[data-e2e="video-views"]');
            cards.push({ id: match[1], viewsText: views ? String(views.textContent) : "" });
          }
        } catch (e) {}
        return {
          items: items,
          cards: cards,
          hasMore: state.hasMore,
          profile: profileInfo(),
          title: document.title,
          href: location.href
        };
      };
    })();
    """#
}
#endif
