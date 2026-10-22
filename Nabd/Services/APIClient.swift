import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case missingCredentials
    case http(status: Int, code: String?, message: String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "عنوان الخادم غير صالح"
        case .missingCredentials:
            return "أضف عنوان الخادم ومفتاح الوصول من الإعدادات"
        case let .http(status, _, message):
            if status == 401 { return "مفتاح الوصول غير صحيح" }
            return message
        case let .decoding(detail):
            return "رد غير متوقع من الخادم: \(detail)"
        case let .network(detail):
            return "تعذّر الاتصال بالخادم. \(detail)"
        }
    }
}

struct APIClient {
    let baseURL: URL
    let token: String

    init?(baseURL raw: String, token: String) {
        guard let url = APIClient.normalize(raw) else { return nil }
        self.baseURL = url
        self.token = token
    }

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private func makeRequest(_ path: String, method: String, body: [String: Any]?, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut { throw APIError.network("انتهت مهلة الانتظار") }
            if error.code == .notConnectedToInternet { throw APIError.network("لا يوجد اتصال بالإنترنت") }
            if error.code == .cannotFindHost || error.code == .cannotConnectToHost {
                throw APIError.network("تأكد من العنوان ومن أن الخادم يعمل")
            }
            throw APIError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status >= 400 {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.http(status: status, code: envelope.error?.code, message: envelope.error?.message ?? "خطأ من الخادم")
            }
            throw APIError.http(status: status, code: nil, message: "خطأ من الخادم (\(status))")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func get<T: Decodable>(_ path: String, timeout: TimeInterval = 30) async throws -> T {
        let request = try makeRequest(path, method: "GET", body: nil, timeout: timeout)
        return try await perform(request)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 150) async throws -> T {
        let request = try makeRequest(path, method: "POST", body: body ?? [:], timeout: timeout)
        return try await perform(request)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try makeRequest(path, method: "DELETE", body: nil, timeout: 30)
        return try await perform(request)
    }

    func health() async throws -> HealthResponse {
        try await get("/health", timeout: 12)
    }
}

private struct ErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var code: String?
        var message: String?
    }
    var error: Payload?
}
