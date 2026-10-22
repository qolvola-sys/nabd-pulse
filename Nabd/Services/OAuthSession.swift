import Foundation
import UIKit
import AuthenticationServices

/// جلسة ربط TikTok عبر ASWebAuthenticationSession، تعود عبر nabd://oauth
final class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func connect(serverBase: String, accountID: String) async throws -> [String: String] {
        var text = serverBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text + "/auth/tiktok/start?account=" + accountID) else {
            throw APIError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let finish: (Result<[String: String], Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nabd") { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        finish(.failure(APIError.network("أُلغيت عملية الربط")))
                    } else {
                        finish(.failure(error))
                    }
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    finish(.failure(APIError.network("لم يصل رد من TikTok")))
                    return
                }
                var values: [String: String] = [:]
                for item in components.queryItems ?? [] {
                    values[item.name] = item.value ?? ""
                }
                if values["status"] == "ok" {
                    finish(.success(values))
                } else {
                    finish(.failure(APIError.network(values["message"] ?? "لم يكتمل الربط")))
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                finish(.failure(APIError.network("تعذّر فتح صفحة تسجيل الدخول")))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
