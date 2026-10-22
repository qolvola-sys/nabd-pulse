import Foundation
import SwiftUI
import UIKit

enum DataSource: Equatable {
    case demo
    case live
    case direct
    case cache
    case empty

    var label: String {
        switch self {
        case .demo: return "بيانات تجريبية"
        case .live: return "متصل بالخادم"
        case .direct: return "بيانات TikTok حقيقية"
        case .cache: return "آخر نسخة محفوظة"
        case .empty: return "لا توجد بيانات"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, error, info }
    let id = UUID()
    var message: String
    var style: Style
}

struct ConnectionReport {
    var ok: Bool
    var message: String
    var demo: Bool
    var tiktokConfigured: Bool
}

@MainActor
final class AppStore: ObservableObject {
    // البيانات
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var summary: Summary = .empty
    @Published private(set) var source: DataSource = .empty
    @Published private(set) var serverInfo: ServerMeta?
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isAdding = false
    @Published private(set) var connectingAccountID: String?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var errorMessage: String?
    @Published var toast: Toast?

    // الإعدادات
    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
        }
    }
    @Published var apiToken: String {
        didSet {
            Keychain.set(apiToken, for: Keys.token)
        }
    }
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: Keys.demoMode)
            if demoMode != oldValue { applyModeChange() }
        }
    }
    @Published var useServer: Bool {
        didSet {
            UserDefaults.standard.set(useServer, forKey: Keys.useServer)
            if useServer != oldValue { applyModeChange() }
        }
    }
    @Published var autoSync: Bool {
        didSet { UserDefaults.standard.set(autoSync, forKey: Keys.autoSync) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    private let oauth = OAuthSession()
    private let direct = DirectTikTokService.shared
    private var didBootstrap = false
    private var lastAutoRefresh: Date?

    private enum Keys {
        static let serverURL = "nabd.serverURL"
        static let demoMode = "nabd.demoMode"
        static let useServer = "nabd.useServer"
        static let autoSync = "nabd.autoSync"
        static let haptics = "nabd.haptics"
        static let token = "nabd.apiToken"
    }

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        demoMode = defaults.object(forKey: Keys.demoMode) as? Bool ?? false
        useServer = defaults.object(forKey: Keys.useServer) as? Bool ?? false
        autoSync = defaults.object(forKey: Keys.autoSync) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        apiToken = Keychain.get(Keys.token)
    }

    // MARK: - اشتقاقات

    var client: APIClient? {
        guard useServer, !demoMode else { return nil }
        return APIClient(baseURL: serverURL, token: apiToken)
    }

    var isDemo: Bool {
        demoMode
    }

    var isDirect: Bool {
        !demoMode && !useServer
    }

    var hasServer: Bool {
        client != nil
    }

    var topAccounts: [Account] {
        accounts.sorted { $0.views > $1.views }
    }

    var connectedCount: Int {
        accounts.filter { $0.connected }.count
    }

    var totalFollowers: Int64 {
        accounts.reduce(Int64(0)) { $0 + $1.followers }
    }

    var needsReconnect: [Account] {
        accounts.filter { $0.status == "needs_reconnect" || ($0.status == "error" && !$0.connected) }
    }

    // MARK: - الإقلاع

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if isDemo {
            loadDemo()
        } else if useServer {
            if let cached = loadCache() {
                accounts = cached
                summary = Summary.make(from: cached)
                source = .cache
            }
            Task { await refresh() }
        } else {
            loadDirectAccounts()
            Task { await refresh() }
        }
    }

    func refreshIfStale() {
        guard !isDemo else { return }
        guard autoSync else { return }
        if let lastAutoRefresh, Date().timeIntervalSince(lastAutoRefresh) < 90 { return }
        lastAutoRefresh = Date()
        Task { await refresh() }
    }

    private func applyModeChange() {
        if isDemo {
            loadDemo()
        } else {
            accounts = []
            summary = .empty
            source = .empty
            if useServer {
                if let cached = loadCache() {
                    accounts = cached
                    summary = Summary.make(from: cached)
                    source = .cache
                }
                Task { await refresh() }
            } else {
                loadDirectAccounts()
                Task { await refresh() }
            }
        }
        haptic(.selection)
    }

    private func loadDemo() {
        accounts = DemoData.accounts()
        summary = Summary.make(from: accounts)
        source = .demo
        lastRefreshed = Date()
        serverInfo = nil
        errorMessage = nil
    }

    // MARK: - الشبكة

    func refresh(showSpinner: Bool = true) async {
        guard !isDemo else { return }
        if let client {
            await refreshFromServer(client, showSpinner: showSpinner)
        } else {
            await refreshDirect(showSpinner: showSpinner)
        }
    }

    private func refreshFromServer(_ client: APIClient, showSpinner: Bool) async {
        if showSpinner && accounts.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let response: AccountsResponse = try await client.get("/api/accounts")
            accounts = response.accounts
            summary = response.summary ?? Summary.make(from: response.accounts)
            source = .live
            errorMessage = nil
            lastRefreshed = Date()
            lastAutoRefresh = Date()
            saveCache()

            if let meta: ServerMeta = try? await client.get("/api/meta") {
                serverInfo = meta
            }
        } catch {
            errorMessage = error.localizedDescription
            if accounts.isEmpty { source = .empty }
            if source != .cache { source = accounts.isEmpty ? .empty : .cache }
        }
    }

    private func refreshDirect(showSpinner: Bool = true) async {
        guard !accounts.isEmpty else {
            source = accounts.isEmpty ? .empty : .direct
            return
        }
        if showSpinner { isLoading = accounts.isEmpty }
        defer { isLoading = false }

        var updated: [String: Account] = [:]
        var lastError: String?
        for account in accounts {
            do {
                let result = try await direct.fetch(
                    handle: account.handle,
                    knownPosts: account.posts,
                    createdAt: account.createdAt
                )
                updated[account.id] = result.account
            } catch {
                var failed = account
                failed.status = "error"
                failed.error = error.localizedDescription
                updated[account.id] = failed
                lastError = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        accounts = accounts.map { updated[$0.id] ?? $0 }
        summary = Summary.make(from: accounts)
        source = .direct
        errorMessage = lastError
        lastRefreshed = Date()
        lastAutoRefresh = Date()
        saveDirectAccounts()
    }

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if isDemo {
            try? await Task.sleep(nanoseconds: 850_000_000)
            simulateDemoGrowth()
            lastRefreshed = Date()
            showToast("تم تحديث البيانات التجريبية", .success)
            haptic(.success)
            return
        }

        if isDirect {
            await refreshDirect(showSpinner: false)
            if let error = errorMessage {
                showToast(error, .error)
                haptic(.error)
            } else {
                showToast("تم تحديث \(accounts.count) حساباً من TikTok", .success)
                haptic(.success)
            }
            return
        }

        guard let client else {
            showToast("اختر مصدر البيانات من الإعدادات", .error)
            return
        }
        do {
            let _: SyncResponse = try await client.post("/api/sync", body: ["force": true])
            await refresh(showSpinner: false)
            showToast("تمت مزامنة \(accounts.count) حساباً", .success)
            haptic(.success)
        } catch {
            showToast(error.localizedDescription, .error)
            haptic(.error)
        }
    }

    func sync(_ account: Account) async {
        guard !isSyncing else { return }
        if isDemo {
            simulateDemoGrowth()
            showToast("تم تحديث @\(account.handle)", .success)
            haptic(.success)
            return
        }
        if isDirect {
            isSyncing = true
            defer { isSyncing = false }
            do {
                let result = try await direct.fetch(
                    handle: account.handle,
                    knownPosts: account.posts,
                    createdAt: account.createdAt
                )
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = result.account
                    summary = Summary.make(from: accounts)
                }
                saveDirectAccounts()
                showToast("تم تحديث @\(account.handle)", .success)
                haptic(.success)
            } catch {
                showToast(error.localizedDescription, .error)
                haptic(.error)
            }
            return
        }
        guard let client else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response: AccountEnvelope = try await client.post("/api/accounts/\(account.id)/sync")
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = response.account
                summary = Summary.make(from: accounts)
            }
            saveCache()
            showToast("تم تحديث @\(account.handle)", .success)
            haptic(.success)
        } catch {
            showToast(error.localizedDescription, .error)
            haptic(.error)
        }
    }

    func add(links: [String]) async -> AddAccountsResponse? {
        guard !isDemo, let client else {
            showToast("الإضافة تحتاج الاتصال بالخادم — أوقف الوضع التجريبي أولاً", .info)
            return nil
        }
        isAdding = true
        defer { isAdding = false }
        do {
            let response: AddAccountsResponse = try await client.post("/api/accounts", body: ["links": links])
            await refresh(showSpinner: false)
            haptic(.success)
            return response
        } catch {
            showToast(error.localizedDescription, .error)
            haptic(.error)
            return nil
        }
    }

    func detail(for account: Account, limit: Int = 40) async throws -> (Account, [VideoItem]) {
        if isDemo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            return (account, DemoData.videos(for: account, limit: min(limit, 30)))
        }
        guard let client else { throw APIError.missingCredentials }
        let response: AccountDetailResponse = try await client.get("/api/accounts/\(account.id)?limit=\(limit)")
        return (response.account, response.videos)
    }

    func delete(_ account: Account) async {
        if isDemo {
            accounts.removeAll { $0.id == account.id }
            summary = Summary.make(from: accounts)
            haptic(.success)
            return
        }
        guard let client else { return }
        do {
            let _: [String: String] = try await client.delete("/api/accounts/\(account.id)")
            accounts.removeAll { $0.id == account.id }
            summary = Summary.make(from: accounts)
            saveCache()
            showToast("تم حذف @\(account.handle)", .success)
            haptic(.success)
        } catch {
            showToast(error.localizedDescription, .error)
            haptic(.error)
        }
    }

    func disconnect(_ account: Account) async {
        guard !isDemo, let client else { return }
        do {
            let response: AccountEnvelope = try await client.post("/api/accounts/\(account.id)/disconnect")
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = response.account
                summary = Summary.make(from: accounts)
            }
            saveCache()
            showToast("تم فصل @\(account.handle)", .info)
        } catch {
            showToast(error.localizedDescription, .error)
        }
    }

    func connect(_ account: Account) async {
        guard !isDemo else {
            showToast("الربط متاح بعد الاتصال بالخادم", .info)
            return
        }
        guard hasServer else {
            showToast("أضف عنوان الخادم من الإعدادات", .error)
            return
        }
        connectingAccountID = account.id
        defer { connectingAccountID = nil }
        do {
            _ = try await oauth.connect(serverBase: serverURL, accountID: account.id)
            await refresh(showSpinner: false)
            showToast("تم ربط @\(account.handle) بنجاح", .success)
            haptic(.success)
        } catch {
            let message = error.localizedDescription
            if !message.contains("أُلغيت") {
                showToast(message, .error)
                haptic(.error)
            }
        }
    }

    func testConnection(url: String, token: String) async -> ConnectionReport {
        guard let client = APIClient(baseURL: url, token: token) else {
            return ConnectionReport(ok: false, message: "عنوان غير صالح. مثال: https://api.example.com", demo: false, tiktokConfigured: false)
        }
        do {
            let health: HealthResponse = try await client.health()
            let meta: ServerMeta? = try? await client.get("/api/meta")
            return ConnectionReport(
                ok: health.ok == true,
                message: "الخادم يعمل\(health.demo == true ? " — الوضع التجريبي" : "")",
                demo: health.demo ?? false,
                tiktokConfigured: meta?.tiktokConfigured ?? health.tiktokConfigured ?? false
            )
        } catch {
            return ConnectionReport(ok: false, message: error.localizedDescription, demo: false, tiktokConfigured: false)
        }
    }

    private func simulateDemoGrowth() {
        var rng = DemoData.Rng(seed: UInt64(Date().timeIntervalSince1970))
        accounts = accounts.map { account in
            var updated = account
            let drift = 1.0 + rng.next() * 0.018
            updated.views = Int64(Double(updated.views) * drift) + Int64(rng.int(0..<900))
            updated.avgViews = Int64(Double(updated.avgViews) * drift)
            updated.videoLikes = Int64(Double(updated.videoLikes) * drift)
            updated.lastSyncedAt = ISO8601DateFormatter.nabd.string(from: Date())
            return updated
        }
        summary = Summary.make(from: accounts)
    }

    // MARK: - التخزين المؤقت

    private struct CacheFile: Codable {
        var savedAt: String
        var accounts: [Account]
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("nabd-cache.json")
    }

    private func saveCache() {
        guard !isDemo, let cacheURL else { return }
        let payload = CacheFile(savedAt: ISO8601DateFormatter.nabd.string(from: Date()), accounts: accounts)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // التخزين المؤقت ليس حرجاً
        }
    }

    private func loadCache() -> [Account]? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data).accounts
    }

    func clearCache() {
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
        showToast("تم مسح النسخة المحفوظة", .info)
    }

    // MARK: - أدوات

    func showToast(_ message: String, _ style: Toast.Style) {
        let item = Toast(message: message, style: style)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = item }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.toast?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
        }
    }

    enum Haptic { case success, error, selection, impact }

    func haptic(_ kind: Haptic) {
        guard hapticsEnabled else { return }
        switch kind {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impact:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

extension ISO8601DateFormatter {
    static let nabd: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
