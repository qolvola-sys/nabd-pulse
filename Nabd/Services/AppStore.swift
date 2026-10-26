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
    @Published private(set) var accounts: [Account] = [] {
        didSet {
            #if MUTABAA
            mirrorAccountsIntoActiveSpace()
            #endif
        }
    }

    #if MUTABAA
    /// مساحات «المتابعة»: لكل مساحة حساباتها وترتيبها وإحصاءاتها.
    @Published private(set) var spaces: [AccountSpace] = []
    @Published private(set) var activeSpaceID = ""
    private var isSwitchingSpace = false
    #endif

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
    private var directVideos: [String: [VideoItem]] = [:]
    private var didBootstrap = false
    private var lastAutoRefresh: Date?
    private var lastDirectRefreshSucceeded = false

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

        // لقطات CI: --demo يعرض بيانات تجريبية بدون تغيير إعداد المستخدم
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            demoMode = true
        }
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
        accounts.filter { $0.status == "needs_reconnect" }
    }

    #if MUTABAA
    // MARK: - المساحات (المتابعة)

    var activeSpace: AccountSpace? {
        spaces.first { $0.id == activeSpaceID }
    }

    var activeSpaceName: String {
        activeSpace?.name ?? AppVariant.name
    }

    /// الشريط العلوي يظهر فقط في الوضع المباشر حيث توجد مساحات محفوظة.
    var spacesEnabled: Bool {
        !spaces.isEmpty && !isDemo && !useServer
    }

    func selectSpace(_ id: String) {
        guard isDirect,
              id != activeSpaceID,
              spaces.contains(where: { $0.id == id }) else { return }

        // نحفظ ترتيب المساحة الحالية قبل الانتقال.
        if let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) {
            spaces[index].accounts = accounts
        }
        let target = spaces.first(where: { $0.id == id })?.accounts ?? []

        activeSpaceID = id
        isSwitchingSpace = true
        accounts = target
        isSwitchingSpace = false
        summary = Summary.make(from: accounts)
        source = accounts.isEmpty ? .empty : .direct
        errorMessage = nil
        lastRefreshed = Dates.parse(summary.lastSyncedAt)
        saveDirectAccounts()
        haptic(.selection)
    }

    @discardableResult
    func createSpace(named raw: String) -> Bool {
        guard isDirect else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? "مساحة \(spaces.count + 1)"
            : String(trimmed.prefix(28))
        let space = AccountSpace(name: name)

        spaces.append(space)
        activeSpaceID = space.id
        isSwitchingSpace = true
        accounts = []
        isSwitchingSpace = false
        summary = .empty
        source = .empty
        errorMessage = nil
        lastRefreshed = nil
        saveDirectAccounts()
        haptic(.success)
        return true
    }

    func renameSpace(_ id: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = String(name.prefix(28))
        saveDirectAccounts()
        haptic(.selection)
    }

    func deleteSpace(_ id: String) {
        guard spaces.count > 1,
              let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeSpaceID
        spaces.remove(at: index)

        if wasActive, !spaces.isEmpty {
            let target = spaces[min(index, spaces.count - 1)]
            activeSpaceID = target.id
            isSwitchingSpace = true
            accounts = target.accounts
            isSwitchingSpace = false
            summary = Summary.make(from: accounts)
            source = accounts.isEmpty ? .empty : .direct
            errorMessage = nil
            lastRefreshed = Dates.parse(summary.lastSyncedAt)
        }
        saveDirectAccounts()
        haptic(.success)
    }

    func moveSpace(_ id: String, by offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard spaces.indices.contains(target), target != index else { return }
        spaces.swapAt(index, target)
        saveDirectAccounts()
        haptic(.impact)
    }

    /// تحريك حساب خطوة واحدة داخل المساحة النشطة. الفهرس 0 هو أعلى القائمة.
    func moveAccount(_ id: String, by offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        moveAccount(id, toPosition: index + offset)
    }

    /// تحريك حساب إلى أي موضع (0-based) داخل المساحة النشطة.
    func moveAccount(_ id: String, toPosition position: Int) {
        guard isDirect,
              let index = accounts.firstIndex(where: { $0.id == id }),
              !accounts.isEmpty else { return }
        let target = min(max(position, 0), accounts.count - 1)
        guard target != index else { return }

        var updated = accounts
        let account = updated.remove(at: index)
        updated.insert(account, at: target)
        accounts = updated
        saveDirectAccounts()
        haptic(.impact)
    }

    /// ينقل الحساب إلى أول موضع في المجموعة المحددة (0-based).
    /// المجموعات هي تقسيمات القائمة الحالية: ٣ حسابات لكل مجموعة.
    func moveAccount(_ id: String, toGroup group: Int, groupSize: Int = 3) {
        guard group >= 0, groupSize > 0 else { return }
        moveAccount(id, toPosition: group * groupSize)
    }

    private func mirrorAccountsIntoActiveSpace() {
        guard isDirect,
              !isSwitchingSpace,
              !activeSpaceID.isEmpty,
              let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        spaces[index].accounts = accounts
    }

    private func seedSpacesIfNeeded(with accounts: [Account]) {
        guard spaces.isEmpty else { return }
        let names = ["علي", "مساحة ٢", "مساحة ٣"]
        spaces = names.enumerated().map { index, name in
            AccountSpace(name: name, accounts: index == 0 ? accounts : [])
        }
        activeSpaceID = spaces.first?.id ?? ""
    }

    private func restoredAccounts(_ accounts: [Account]) -> [Account] {
        accounts.map { account in
            var stable = account
            if stable.status == "error" {
                stable.status = (stable.fetchedVideos > 0 || stable.views > 0) ? "cached" : "pending"
            }
            stable.error = nil
            return stable
        }
    }
    #endif

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
        guard lastRefreshed != nil, !isLoading, !isSyncing else { return }
        if let lastAutoRefresh, Date().timeIntervalSince(lastAutoRefresh) < 90 { return }
        lastAutoRefresh = Date()
        Task { await refresh(showSpinner: false) }
    }

    private func applyModeChange() {
        if isDemo {
            loadDemo()
        } else {
            #if MUTABAA
            // لا نكتب قائمة فارغة فوق المساحة النشطة أثناء تبديل المصدر؛
            // التحميل التالي من التخزين سيعيد حسابات المساحة كما هي.
            isSwitchingSpace = true
            accounts = []
            isSwitchingSpace = false
            #else
            accounts = []
            #endif
            summary = .empty
            source = .empty
            errorMessage = nil
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
            summary = Summary.make(from: response.accounts)
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
            source = .empty
            lastDirectRefreshSucceeded = false
            return
        }
        if showSpinner { isLoading = accounts.isEmpty }
        defer { isLoading = false }

        var updated: [String: Account] = [:]
        var successes = 0
        for account in accounts {
            do {
                let result = try await direct.fetch(
                    handle: account.handle,
                    knownPosts: account.posts,
                    createdAt: account.createdAt
                )
                var fresh = result.account
                if result.videos.isEmpty {
                    fresh = preservingVideoStats(in: fresh, from: account)
                }
                fresh.status = "public"
                fresh.error = nil
                updated[account.id] = fresh
                if !result.videos.isEmpty {
                    directVideos[account.handle] = result.videos
                }
                successes += 1
            } catch {
                // لا نستبدل الأرقام المحفوظة عند تعذّر الاتصال، ولا نعرض خطأ أحمر.
                var stable = account
                stable.status = (stable.fetchedVideos > 0 || stable.views > 0) ? "cached" : "pending"
                stable.error = nil
                stable.publicStats = stable.publicStats || !stable.connected
                updated[account.id] = stable
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
        }

        accounts = accounts.map { updated[$0.id] ?? $0 }
        summary = Summary.make(from: accounts)
        source = successes > 0 ? .direct : .cache
        errorMessage = nil
        lastDirectRefreshSucceeded = successes > 0
        lastRefreshed = Date()
        lastAutoRefresh = Date()
        saveDirectAccounts()
    }

    /// عند نجاح بيانات البروفايل فقط (بدون قائمة المنشورات) نحتفظ بإحصاءات الفيديو السابقة.
    private func preservingVideoStats(in fresh: Account, from old: Account) -> Account {
        var merged = fresh
        if !merged.profileExact && old.profileExact {
            merged.profileExact = true
            merged.followers = old.followers
            merged.following = old.following
            merged.likes = old.likes
            merged.posts = old.posts
        }
        merged.views = old.views
        merged.avgViews = old.avgViews
        merged.fetchedVideos = old.fetchedVideos
        merged.coverage = old.coverage
        merged.posts24h = old.posts24h
        merged.views24h = old.views24h
        merged.posts7d = old.posts7d
        merged.weeklyViews = old.weeklyViews
        merged.viewsExact = old.viewsExact
        merged.dailyComplete = old.dailyComplete
        merged.dailyViewsExact = old.dailyViewsExact
        merged.weeklyComplete = old.weeklyComplete
        merged.weeklyViewsExact = old.weeklyViewsExact
        merged.allPostsLoaded = old.allPostsLoaded
        return merged
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
            if lastDirectRefreshSucceeded {
                showToast("تم تحديث \(accounts.count) حساباً من TikTok", .success)
                haptic(.success)
            } else if !accounts.isEmpty {
                showToast("تم عرض أحدث الإحصاءات المحفوظة", .info)
                haptic(.impact)
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
                var fresh = result.account
                if result.videos.isEmpty {
                    fresh = preservingVideoStats(in: fresh, from: account)
                }
                fresh.status = "public"
                fresh.error = nil
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = fresh
                    summary = Summary.make(from: accounts)
                }
                if !result.videos.isEmpty {
                    directVideos[account.handle] = result.videos
                }
                saveDirectAccounts()
                showToast("تم تحديث @\(account.handle)", .success)
                haptic(.success)
            } catch {
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index].status = (account.fetchedVideos > 0 || account.views > 0) ? "cached" : "pending"
                    accounts[index].error = nil
                    summary = Summary.make(from: accounts)
                }
                saveDirectAccounts()
                showToast("تم الاحتفاظ بآخر إحصاءات @\(account.handle)", .info)
                haptic(.impact)
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
        guard !isDemo else {
            showToast("أوقف الوضع التجريبي أولاً", .info)
            return nil
        }
        if isDirect {
            return await addDirect(links: links)
        }
        guard let client else {
            showToast("اختر مصدر البيانات من الإعدادات", .info)
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

    private func addDirect(links: [String]) async -> AddAccountsResponse? {
        isAdding = true
        defer { isAdding = false }

        var created: [Account] = []
        var skipped: [SkippedAccount] = []
        var invalid: [String] = []

        for raw in links {
            guard let handle = Self.handle(from: raw) else {
                invalid.append(raw)
                continue
            }
            if accounts.contains(where: { $0.handle.lowercased() == handle }) {
                skipped.append(SkippedAccount(handle: handle, reason: "duplicate"))
                continue
            }

            let placeholder = Account(
                id: "direct-\(handle)",
                handle: handle,
                displayName: "@\(handle)",
                url: "https://www.tiktok.com/@\(handle)",
                status: "pending",
                createdAt: ISO8601DateFormatter.nabd.string(from: Date())
            )
            accounts.append(placeholder)
            #if !MUTABAA
            // «نبض» يحافظ على الترتيب الأبجدي. «المتابعة» تحفظ الترتيب اليدوي
            // وتضع الحساب الجديد في نهاية المساحة.
            accounts.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            #endif

            do {
                let result = try await direct.fetch(handle: handle)
                if let index = accounts.firstIndex(where: { $0.handle == handle }) {
                    accounts[index] = result.account
                }
                directVideos[handle] = result.videos
                created.append(result.account)
            } catch {
                // نضيف الحساب بحالة انتظار بدل عرض خطأ. التحديث التالي سيكمل البيانات.
                var pending = placeholder
                pending.status = "pending"
                pending.error = nil
                if let index = accounts.firstIndex(where: { $0.handle == handle }) {
                    accounts[index] = pending
                }
                created.append(pending)
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
        }

        summary = Summary.make(from: accounts)
        source = .direct
        lastRefreshed = Date()
        lastDirectRefreshSucceeded = created.contains { $0.status == "public" || $0.status == "ok" }
        saveDirectAccounts()

        let ready = created.filter { $0.status == "public" || $0.status == "ok" }.count
        if !created.isEmpty {
            if ready == 0 {
                showToast("تمت الإضافة — ستُحدَّث الأرقام تلقائياً", .info)
            } else if ready < created.count {
                showToast("تمت إضافة \(created.count) حساب — بعضها سيُحدَّث تلقائياً", .info)
            } else {
                showToast("تمت إضافة \(created.count) حساب", .success)
            }
            haptic(.success)
        } else if !invalid.isEmpty {
            showToast("لم نتعرف على أي رابط صالح", .info)
        }

        return AddAccountsResponse(
            created: created,
            skipped: skipped,
            invalid: invalid,
            accounts: accounts
        )
    }

    static func handle(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        value = value.replacingOccurrences(of: "www.", with: "")
        if value.lowercased().hasPrefix("tiktok.com/") {
            value = String(value.dropFirst("tiktok.com/".count))
        }
        value = value.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? value
        while value.hasSuffix("/") { value.removeLast() }
        value = value.replacingOccurrences(of: "@", with: "")

        if value.range(of: #"^[A-Za-z0-9._]{2,24}$"#, options: .regularExpression) != nil,
           !value.lowercased().hasSuffix(".com") {
            return value.lowercased()
        }
        if let range = raw.range(of: #"@([A-Za-z0-9._]{2,24})"#, options: .regularExpression) {
            return String(raw[range]).replacingOccurrences(of: "@", with: "").lowercased()
        }
        return nil
    }

    func detail(for account: Account, limit: Int = 40) async throws -> (Account, [VideoItem]) {
        if isDemo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            return (account, DemoData.videos(for: account, limit: min(limit, 30)))
        }
        if isDirect {
            if let cached = directVideos[account.handle], !cached.isEmpty {
                let current = accounts.first(where: { $0.id == account.id }) ?? account
                return (current, Array(cached.prefix(limit)))
            }
            let result = try await direct.fetch(
                handle: account.handle,
                knownPosts: account.posts,
                createdAt: account.createdAt
            )
            var fresh = result.account
            if result.videos.isEmpty {
                fresh = preservingVideoStats(in: fresh, from: account)
            }
            if !result.videos.isEmpty {
                directVideos[account.handle] = result.videos
            }
            saveDirectAccounts()
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = fresh
                summary = Summary.make(from: accounts)
            }
            let videos = result.videos.isEmpty
                ? (directVideos[account.handle] ?? [])
                : result.videos
            return (fresh, Array(videos.prefix(limit)))
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
        if isDirect {
            accounts.removeAll { $0.id == account.id }
            #if MUTABAA
            // قد يكون الحساب نفسه مضافاً في مساحة أخرى؛ لا نحذف فيديوهاته حينها.
            let usedInAnotherSpace = spaces.contains { space in
                space.accounts.contains { $0.handle == account.handle }
            }
            if !usedInAnotherSpace {
                directVideos.removeValue(forKey: account.handle)
            }
            #else
            directVideos.removeValue(forKey: account.handle)
            #endif
            summary = Summary.make(from: accounts)
            saveDirectAccounts()
            showToast("تم حذف @\(account.handle)", .success)
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
        if isDirect {
            showToast("الإحصاءات تُقرأ مباشرة من TikTok — لا حاجة لتسجيل الدخول", .info)
            return
        }
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
            updated.views24h = Int64(Double(updated.views24h) * drift)
            updated.weeklyViews = Int64(Double(updated.weeklyViews) * drift)
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

    // MARK: - التخزين المحلي للوضع المباشر

    private struct DirectCacheFile: Codable {
        var savedAt: String
        var accounts: [Account]
        var videos: [String: [VideoItem]]
        #if MUTABAA
        var spaces: [AccountSpace]? = nil
        var activeSpaceID: String? = nil
        #endif
    }

    private var directCacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("nabd-direct.json")
    }

    private func saveDirectAccounts() {
        guard !isDemo, !useServer, let directCacheURL else { return }
        #if MUTABAA
        let payload = DirectCacheFile(
            savedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            accounts: accounts,
            videos: directVideos,
            spaces: spaces,
            activeSpaceID: activeSpaceID
        )
        #else
        let payload = DirectCacheFile(
            savedAt: ISO8601DateFormatter.nabd.string(from: Date()),
            accounts: accounts,
            videos: directVideos
        )
        #endif
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: directCacheURL, options: .atomic)
        } catch {
            // التخزين المحلي ليس حرجاً
        }
    }

    private func loadDirectAccounts() {
        guard let directCacheURL, let data = try? Data(contentsOf: directCacheURL),
              let payload = try? JSONDecoder().decode(DirectCacheFile.self, from: data) else {
            #if MUTABAA
            seedSpacesIfNeeded(with: [])
            #endif
            accounts = []
            summary = .empty
            source = .empty
            lastRefreshed = nil
            #if MUTABAA
            saveDirectAccounts()
            #endif
            return
        }

        #if MUTABAA
        if let saved = payload.spaces, !saved.isEmpty {
            spaces = saved.map { space in
                var copy = space
                copy.accounts = restoredAccounts(space.accounts)
                return copy
            }
            if let active = payload.activeSpaceID,
               spaces.contains(where: { $0.id == active }) {
                activeSpaceID = active
            } else {
                activeSpaceID = spaces.first?.id ?? ""
            }
            isSwitchingSpace = true
            accounts = activeSpace?.accounts ?? []
            isSwitchingSpace = false
        } else {
            // ترحيل نسخة قديمة: كل الحسابات الحالية تنتقل إلى مساحة «علي».
            let migrated = restoredAccounts(payload.accounts)
            spaces = []
            seedSpacesIfNeeded(with: migrated)
            isSwitchingSpace = true
            accounts = migrated
            isSwitchingSpace = false
        }
        #else
        accounts = payload.accounts.map { account in
            var stable = account
            if stable.status == "error" {
                stable.status = (stable.fetchedVideos > 0 || stable.views > 0) ? "cached" : "pending"
            }
            stable.error = nil
            return stable
        }
        #endif

        directVideos = payload.videos
        summary = Summary.make(from: accounts)
        source = accounts.isEmpty ? .empty : .direct
        errorMessage = nil
        lastRefreshed = Dates.parse(payload.savedAt)
        #if MUTABAA
        saveDirectAccounts()
        #endif
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
