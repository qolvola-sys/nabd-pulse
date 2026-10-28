import Foundation
import WebKit

/// تحميل صفحة عبر محرك WebKit الحقيقي (نفس محرك Safari).
///
/// بعض المواقع — ومنها إنستغرام — ترفض طلبات `URLSession` لأنها تفحص
/// بصمة الاتصال (TLS fingerprint) وتستنتج أنها ليست متصفحاً، فترد بحجب
/// أو بصفحة فارغة. `WKWebView` يستخدم نفس شبكة Safari، فيمرّ الطلب كما
/// لو أن المستخدم فتح الصفحة بنفسه على جهازه.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {

    static let shared = WebPageLoader()

    enum LoadError: LocalizedError {
        case busy
        case timeout
        case empty

        var errorDescription: String? {
            switch self {
            case .busy:
                return "المتصفح الداخلي مشغول بطلب آخر"
            case .timeout:
                return "انتهت مهلة تحميل الصفحة"
            case .empty:
                return "أعاد الموقع صفحة فارغة"
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    /// يحمّل الصفحة ويعيد HTML بعد تنفيذ JavaScript الخاص بها.
    func html(
        from url: URL,
        userAgent: String,
        timeout: TimeInterval = 25
    ) async throws -> String {
        guard continuation == nil else { throw LoadError.busy }

        let configuration = WKWebViewConfiguration()
        // جلسة معزولة: لا كوكيز ولا تسجيل دخول سابق، حتى لا نفرض على
        // إنستغرام حالة حساب قديمة أو جدار تسجيل دخول.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 900),
            configuration: configuration
        )
        view.customUserAgent = userAgent
        view.navigationDelegate = self
        webView = view

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(LoadError.timeout))
            }

            view.load(URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: timeout
            ))
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.capture()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }

    // MARK: - التنفيذ

    private func capture() {
        guard let view = webView, continuation != nil else { return }
        view.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let html = result as? String, html.count > 500 {
                    self.finish(.success(html))
                } else if let error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.failure(LoadError.empty))
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
