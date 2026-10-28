#if MUTABAA
import Foundation
import UIKit

/// يدير مسودات التقارير وملفات Excel وإعدادات الجدولة.
/// يعمل محلياً بالكامل: لا خادم ولا مفاتيح، والبيانات تُحفظ داخل Documents.
@MainActor
final class ReportsManager: ObservableObject {
    @Published private(set) var documents: [ReportDocument] = []
    @Published private(set) var exportedFiles: [ReportFile] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var progress: ReportProgress?
    @Published private(set) var lastError: String?
    @Published private(set) var lastGeneratedAt: Date?

    @Published var settings: ReportSettings = .default {
        didSet {
            guard didLoad else { return }
            persistSettings()
        }
    }

    private var didLoad = false
    private var lastAutoAttempt: Date?
    private var isAutoRunning = false

    // MARK: - التخزين

    private var reportsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MutabaaReports", isDirectory: true)
    }

    private var exportsDirectory: URL {
        reportsDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    private var documentsURL: URL {
        reportsDirectory.appendingPathComponent("reports.json")
    }

    private var settingsURL: URL {
        reportsDirectory.appendingPathComponent("settings.json")
    }

    init() {
        load()
        refreshExportedFiles()
    }

    private func load() {
        guard !didLoad else { return }
        ensureDirectories()

        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(ReportSettings.self, from: data) {
            settings = decoded
        }

        if let data = try? Data(contentsOf: documentsURL),
           let decoded = try? JSONDecoder().decode([ReportDocument].self, from: data) {
            documents = decoded.sorted { $0.generatedAt > $1.generatedAt }
        }

        didLoad = true
        syncLastGeneratedAt()
    }

    private func ensureDirectories() {
        let manager = FileManager.default
        try? manager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        try? manager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    }

    private func persistDocuments() {
        ensureDirectories()
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: documentsURL, options: .atomic)
    }

    private func persistSettings() {
        ensureDirectories()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - الوصول للتقارير

    func document(id: String) -> ReportDocument? {
        documents.first { $0.id == id }
    }

    func filteredDocuments(
        kind: ReportKind? = nil,
        platform: ReportPlatform? = nil,
        spaceID: String? = nil
    ) -> [ReportDocument] {
        documents.filter { document in
            (kind == nil || document.kind == kind) &&
            (platform == nil || document.reportPlatform == platform) &&
            (spaceID == nil || document.spaceID == spaceID)
        }
    }

    func save(_ document: ReportDocument) {
        var copy = document
        copy.lastEditedAt = Date()
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = copy
        } else {
            documents.insert(copy, at: 0)
        }
        rememberManualRows(in: copy)
        persistDocuments()
        syncLastGeneratedAt()
    }

    func delete(_ document: ReportDocument) {
        documents.removeAll { $0.id == document.id }
        persistDocuments()
        syncLastGeneratedAt()
    }

    func clearError() {
        lastError = nil
    }

    /// تعديل الإعدادات عبر نسخة جديدة حتى يُحفظ التغيير ويُحدَّث الواجهة
    /// حتى عند تعديل قاموس الصفحات اليدوية.
    func updateSettings(_ change: (inout ReportSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
    }

    private func rememberManualRows(in document: ReportDocument) {
        // الصفحات المرتبطة بحساب لا تصبح قوالب حتى لو عُدّلت أرقامها يدوياً؛
        // القالب مخصص للصفحات المضافة مستقلة. نحفظ قوالب المنصة نفسها فقط.
        let platform = document.reportPlatform
        let templates = document.rows
            .filter { $0.isManual && $0.accountID == nil && $0.platform == platform }
            .map {
                ReportManualTemplate(
                    id: $0.id,
                    pageName: $0.pageName,
                    platform: $0.platform,
                    program: $0.program,
                    notes: $0.notes,
                    url: $0.url
                )
            }
        updateSettings { settings in
            var stored = settings.manualRowsBySpace[document.spaceID] ?? []
            stored.removeAll { $0.platform == platform }
            stored.append(contentsOf: templates)
            if stored.isEmpty {
                settings.manualRowsBySpace.removeValue(forKey: document.spaceID)
            } else {
                settings.manualRowsBySpace[document.spaceID] = stored
            }
        }
    }

    private func syncLastGeneratedAt() {
        lastGeneratedAt = documents.first?.generatedAt
    }

    // MARK: - التوليد

    /// يولّد تقريراً جديداً من الصفحات الحالية في المساحة النشطة.
    /// الأرقام تُقرأ من `WeeklyWebScanner` الذي يعترض `statsV2` من TikTok،
    /// وأي قراءة ناقصة تُعلَّم بوضوح بدل تقديمها كرقم دقيق.
    func generate(
        kind: ReportKind,
        platform: ReportPlatform,
        store: AppStore,
        now: Date = Date()
    ) async -> ReportDocument? {
        guard !isGenerating else {
            lastError = "هناك تقرير قيد التوليد الآن."
            return nil
        }
        guard store.isDirect else {
            lastError = "التقارير تقرأ الصفحات مباشرة. أوقف الوضع التجريبي واستخدم الوضع المباشر أولاً."
            return nil
        }
        guard !store.accounts.isEmpty else {
            lastError = "لا توجد حسابات في المساحة النشطة. أضف حساباً أولاً."
            return nil
        }
        guard let space = store.activeSpace else {
            lastError = "تعذّر تحديد المساحة النشطة."
            return nil
        }

        let window = window(for: kind, now: now)
        let accounts = store.accounts.filter { $0.platform.reportPlatform == platform }
        guard !accounts.isEmpty else {
            lastError = "لا توجد حسابات \(platform.defaultProgram) في المساحة النشطة. أضف حساباً أولاً."
            return nil
        }
        let groups = store.groups
        let membership = space.groupMembership

        isGenerating = true
        lastError = nil
        defer {
            isGenerating = false
            progress = nil
        }

        let startedAt = Date()
        progress = ReportProgress(
            kind: kind,
            current: 0,
            total: accounts.count,
            handle: "",
            phase: "تجهيز الصفحات"
        )

        let preparedGroups = makeDraftGroups(
            accounts: accounts,
            groups: groups,
            membership: membership,
            spaceID: space.id
        )

        var reportGroups: [ReportGroup] = []
        var reportPosts: [ReportPost] = []
        let startUnix = Int(window.start.timeIntervalSince1970)
        let endUnix = Int(window.end.timeIntervalSince1970)

        for (groupIndex, draft) in preparedGroups.enumerated() {
            progress = ReportProgress(
                kind: kind,
                current: min(progress?.current ?? 0, accounts.count),
                total: accounts.count,
                handle: "",
                phase: "قراءة المجموعة \(groupIndex + 1) من \(preparedGroups.count)"
            )

            var rows: [ReportRow] = []

            for account in draft.accounts {
                let completed = min((progress?.current ?? 0) + 1, accounts.count)
                progress = ReportProgress(
                    kind: kind,
                    current: completed - 1,
                    total: accounts.count,
                    handle: account.handleLabel,
                    phase: "قراءة منشورات \(account.displayName)"
                )

                let parsed: ParsedAccount
                switch account.platform {
                case .facebook:
                    parsed = await parseFacebook(
                        account: account,
                        startUnix: startUnix,
                        endUnix: endUnix
                    )
                case .instagram:
                    parsed = await parseInstagram(
                        account: account,
                        startUnix: startUnix,
                        endUnix: endUnix
                    )
                case .tiktok:
                    let payload = await WeeklyWebScanner.shared.scan(
                        handle: account.handle,
                        cutoff: startUnix
                    )
                    parsed = parse(
                        payload: payload,
                        account: account,
                        startUnix: startUnix,
                        endUnix: endUnix
                    )
                }
                rows.append(parsed.row)
                reportPosts.append(contentsOf: parsed.posts)

                progress = ReportProgress(
                    kind: kind,
                    current: completed,
                    total: accounts.count,
                    handle: account.handleLabel,
                    phase: "تمت قراءة \(completed) من \(accounts.count)"
                )
            }

            if !rows.isEmpty {
                reportGroups.append(ReportGroup(id: draft.id, name: draft.name, rows: rows))
            }
        }

        // الصفحات اليدوية تُحفظ من تقرير المنصة نفسها وتُضاف كمجموعة مستقلة.
        let manualTemplates = (settings.manualRowsBySpace[space.id] ?? [])
            .filter { $0.platform == platform }
        if !manualTemplates.isEmpty {
            let manualRows = manualTemplates.map { template in
                ReportRow(
                    id: template.id,
                    pageName: template.pageName,
                    platform: template.platform,
                    program: template.program,
                    posts: nil,
                    views: nil,
                    notes: template.notes,
                    url: template.url,
                    quality: .manual,
                    isManual: true
                )
            }
            reportGroups.append(
                ReportGroup(name: "حسابات إضافية (إدخال يدوي)", rows: manualRows)
            )
        }

        reportPosts.sort { $0.publishedAt > $1.publishedAt }

        let title = "منصات \(space.name)"
        let document = ReportDocument(
            kind: kind,
            platform: platform,
            spaceID: space.id,
            spaceName: space.name,
            title: title,
            periodStart: window.start,
            periodEnd: window.end,
            generatedAt: Date(),
            groups: reportGroups,
            posts: reportPosts,
            note: generatedNote(for: reportGroups),
            version: 1
        )

        documents.insert(document, at: 0)
        persistDocuments()
        syncLastGeneratedAt()
        lastGeneratedAt = document.generatedAt

        let duration = Date().timeIntervalSince(startedAt)
        if duration > 20 {
            // مجرد إشارة تشخيصية خفيفة، لا تُعرض للمستخدم.
            print("Mutabaa report generated in \(Int(duration))s")
        }
        return document
    }

    /// فحص الجدولة عند فتح التطبيق أو عند بقائه مفتوحاً.
    /// iOS لا يسمح بقراءة TikTok في الخلفية، لذلك يتم التوليد عند أول فرصة
    /// بعد الساعة ١:٠٠ صباحاً (أو أثناء بقاء التطبيق مفتوحاً).
    func autoGenerateIfNeeded(store: AppStore, now: Date = Date()) async {
        guard !isAutoRunning, !isGenerating else { return }
        guard store.isDirect, !store.demoMode, !store.useServer else { return }
        guard !store.accounts.isEmpty, let space = store.activeSpace else { return }

        if let lastAutoAttempt, now.timeIntervalSince(lastAutoAttempt) < 90 {
            return
        }
        lastAutoAttempt = now

        let platforms = AccountPlatform.allCases
            .filter { platform in store.accounts.contains { $0.platform == platform } }
            .map(\.reportPlatform)
        guard !platforms.isEmpty else { return }

        if settings.dailyEnabled {
            let window = ReportDates.dailyWindow(now: now, hour: 1)
            if now >= window.end.addingTimeInterval(60) {
                for platform in platforms
                where !hasReport(kind: .daily, platform: platform, spaceID: space.id, periodEnd: window.end) {
                    isAutoRunning = true
                    let document = await generate(kind: .daily, platform: platform, store: store, now: now)
                    isAutoRunning = false
                    if let document {
                        store.showToast("تم إنشاء \(document.kind.title) \(document.reportPlatform.defaultProgram) لـ \(document.displayDate) تلقائياً", .success)
                    }
                    return
                }
            }
        }

        if settings.weeklyEnabled {
            let window = ReportDates.weeklyWindow(
                now: now,
                weekday: settings.weeklyWeekday,
                hour: settings.weeklyHour
            )
            if now >= window.end.addingTimeInterval(60) {
                for platform in platforms
                where !hasReport(kind: .weekly, platform: platform, spaceID: space.id, periodEnd: window.end) {
                    isAutoRunning = true
                    let document = await generate(kind: .weekly, platform: platform, store: store, now: now)
                    isAutoRunning = false
                    if let document {
                        store.showToast("تم إنشاء \(document.kind.title) \(document.reportPlatform.defaultProgram) لـ \(document.displayDate) تلقائياً", .success)
                    }
                    return
                }
            }
        }
    }

    private func hasReport(
        kind: ReportKind,
        platform: ReportPlatform,
        spaceID: String,
        periodEnd: Date
    ) -> Bool {
        documents.contains { document in
            document.kind == kind &&
            document.reportPlatform == platform &&
            document.spaceID == spaceID &&
            abs(document.periodEnd.timeIntervalSince(periodEnd)) < 2
        }
    }

    func window(for kind: ReportKind, now: Date = Date()) -> (start: Date, end: Date) {
        switch kind {
        case .daily:
            return ReportDates.dailyWindow(now: now, hour: 1)
        case .weekly:
            return ReportDates.weeklyWindow(
                now: now,
                weekday: settings.weeklyWeekday,
                hour: settings.weeklyHour
            )
        }
    }

    // MARK: - تحويل القراءة إلى صف

    private struct DraftGroup {
        var id: String
        var name: String
        var accounts: [Account]
    }

    private func makeDraftGroups(
        accounts: [Account],
        groups: [AccountGroup],
        membership: [String: String],
        spaceID: String
    ) -> [DraftGroup] {
        var result: [DraftGroup] = []
        var claimed = Set<String>()

        if !groups.isEmpty {
            for group in groups {
                let members = accounts.filter { membership[$0.id] == group.id }
                claimed.formUnion(members.map(\.id))
                if !members.isEmpty {
                    result.append(DraftGroup(id: group.id, name: group.name, accounts: members))
                }
            }
        }

        let orphans = accounts.filter { !claimed.contains($0.id) }
        if !orphans.isEmpty {
            if result.isEmpty {
                let chunks = stride(from: 0, to: orphans.count, by: AccountGroup.capacity)
                for (index, start) in chunks.enumerated() {
                    let end = min(start + AccountGroup.capacity, orphans.count)
                    result.append(
                        DraftGroup(
                            id: "auto-\(index)",
                            name: "المجموعة \(ReportNumber.full(Int64(index + 1)))",
                            accounts: Array(orphans[start..<end])
                        )
                    )
                }
            } else {
                result.append(DraftGroup(id: "other", name: "حسابات أخرى", accounts: orphans))
            }
        }

        return result
    }

    private struct ParsedAccount {
        var row: ReportRow
        var posts: [ReportPost]
    }

    private func parse(
        payload: WeeklyScanPayload?,
        account: Account,
        startUnix: Int,
        endUnix: Int
    ) -> ParsedAccount {
        let baseURL = account.url.isEmpty
            ? "https://www.tiktok.com/@\(account.handle)"
            : account.url

        guard let payload else {
            return ParsedAccount(
                row: ReportRow(
                    accountID: account.id,
                    pageName: account.displayName,
                    platform: .tiktok,
                    program: "تيك توك",
                    posts: nil,
                    views: nil,
                    notes: "تعذّرت قراءة الصفحة. أعد توليد التقرير أو افتح التقرير لتعديله.",
                    url: baseURL,
                    quality: .unavailable
                ),
                posts: []
            )
        }

        let windowVideos = payload.videos.filter {
            $0.createTime >= startUnix && $0.createTime < endUnix
        }
        let views = windowVideos.reduce(Int64(0)) { $0 + $1.views }
        // دقة التقرير تخصّ منشورات النافذة فقط؛ لا تجعل منشوراً قديماً
        // خارج النافذة يخفض تصنيف اليوم أو الأسبوع.
        let allExact = windowVideos.allSatisfy { $0.viewsExact }

        let quality: ReportQuality
        let notes: String
        if !payload.complete {
            quality = .partial
            notes = "لم تكتمل قراءة كل منشورات الفترة. أعد التوليد للحصول على رقم نهائي."
        } else if !allExact {
            quality = .approximate
            notes = "بعض المشاهدات مختصرة من TikTok؛ أعد التوليد لاحقاً لأرقام أدق."
        } else {
            quality = .exact
            notes = ""
        }

        let posts = windowVideos.map { video in
            ReportPost(
                id: video.id,
                accountID: account.id,
                pageName: account.displayName,
                handle: account.handle,
                platform: .tiktok,
                title: video.title,
                url: video.shareUrl ?? "https://www.tiktok.com/@\(account.handle)/video/\(video.id)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(video.createTime)),
                views: video.views,
                likes: video.likes,
                comments: video.comments,
                shares: video.shares,
                viewsExact: video.viewsExact
            )
        }

        let row = ReportRow(
            accountID: account.id,
            pageName: account.displayName,
            platform: .tiktok,
            program: "تيك توك",
            posts: windowVideos.count,
            views: views,
            notes: notes,
            url: baseURL,
            quality: quality
        )

        return ParsedAccount(row: row, posts: posts)
    }

    /// يقرأ صفحة فيسبوك العامة وقت التوليد. المنشورات المتاحة علناً هي آخر
    /// ٢٠ منشوراً، ومشاهدات الفيديو فقط هي التي تُنشر. نعلّم النتيجة جزئية
    /// أو تقريبية إن لم تغطِّ النافذة كاملة أو إن وُجدت منشورات بلا مشاهدات.
    private func parseFacebook(
        account: Account,
        startUnix: Int,
        endUnix: Int
    ) async -> ParsedAccount {
        let baseURL = account.url.isEmpty
            ? "https://www.facebook.com/\(account.handle)"
            : account.url

        do {
            let result = try await DirectFacebookService.shared.fetch(
                handle: account.handle,
                url: baseURL,
                createdAt: account.createdAt
            )
            let videos = result.videos
            let windowVideos = videos.filter {
                $0.createTime >= startUnix && $0.createTime < endUnix
            }
            let complete = facebookWindowComplete(videos: videos, startUnix: startUnix)
            let views = windowVideos.reduce(Int64(0)) { $0 + $1.views }
            let allExact = !windowVideos.isEmpty && windowVideos.allSatisfy { $0.viewsExact }

            let quality: ReportQuality
            let notes: String
            if windowVideos.isEmpty {
                quality = .partial
                notes = "لم تُرجع الصفحة منشورات عامة داخل الفترة. قد تكون الصفحة جديدة أو تحدّ فيسبوك المحتوى العام."
            } else if !complete {
                quality = .partial
                notes = "أحدث ٢٠ منشوراً فقط متاحة علناً؛ قد توجد منشورات أخرى داخل الفترة. أعد التوليد لاحقاً."
            } else if !allExact {
                quality = .approximate
                notes = "مشاهدات فيسبوك المتاحة علناً للفيديو فقط؛ المنشورات النصية والصور بلا مشاهدات معلنة."
            } else {
                quality = .exact
                notes = "مشاهدات فيديو فيسبوك من الصفحة العامة."
            }

            let posts = windowVideos.map { video in
                ReportPost(
                    id: video.id,
                    accountID: account.id,
                    pageName: account.displayName,
                    handle: account.handle,
                    platform: .facebook,
                    title: video.title,
                    url: video.shareUrl ?? baseURL,
                    publishedAt: Date(timeIntervalSince1970: TimeInterval(video.createTime)),
                    views: video.views,
                    likes: video.likes,
                    comments: video.comments,
                    shares: video.shares,
                    viewsExact: video.viewsExact
                )
            }

            let row = ReportRow(
                accountID: account.id,
                pageName: account.displayName,
                platform: .facebook,
                program: "فيسبوك",
                posts: windowVideos.count,
                views: views,
                notes: notes,
                url: baseURL,
                quality: quality
            )
            return ParsedAccount(row: row, posts: posts)
        } catch {
            return ParsedAccount(
                row: ReportRow(
                    accountID: account.id,
                    pageName: account.displayName,
                    platform: .facebook,
                    program: "فيسبوك",
                    posts: nil,
                    views: nil,
                    notes: "تعذّرت قراءة صفحة فيسبوك العامة. أعد التوليد أو افتح التقرير لتعديله.",
                    url: baseURL,
                    quality: .unavailable
                ),
                posts: []
            )
        }
    }

    /// النافذة مكتملة إذا انتهت المنشورات المحمّلة قبل بدايتها، أو إذا كانت
    /// الصفحة أعادت أقل من ٢٠ منشوراً (أي أن الخلاصة وصلت لآخرها).
    private func facebookWindowComplete(videos: [VideoItem], startUnix: Int) -> Bool {
        if videos.isEmpty { return true }
        if videos.count < 20 { return true }
        let oldest = videos.map(\.createTime).min() ?? 0
        return oldest > 0 && oldest < startUnix
    }

    /// يقرأ حساب إنستغرام العام وقت التوليد. الواجهة العامة تعرض نحو ١٢
    /// منشوراً حديثاً، ومشاهدات الفيديو والريل فقط هي المتاحة. الإعجابات
    /// متاحة لكل المنشورات لكنها لا تدخل أعمدة التقرير السبعة.
    private func parseInstagram(
        account: Account,
        startUnix: Int,
        endUnix: Int
    ) async -> ParsedAccount {
        let baseURL = account.url.isEmpty
            ? "https://www.instagram.com/\(account.handle)/"
            : account.url

        do {
            let result = try await DirectInstagramService.shared.fetch(
                handle: account.handle,
                url: baseURL,
                createdAt: account.createdAt
            )
            let videos = result.videos
            let windowVideos = videos.filter {
                $0.createTime >= startUnix && $0.createTime < endUnix
            }
            let complete = instagramWindowComplete(
                videos: videos,
                startUnix: startUnix,
                allPostsLoaded: result.account.allPostsLoaded
            )
            let views = windowVideos.reduce(Int64(0)) { $0 + $1.views }
            let allExact = !windowVideos.isEmpty && windowVideos.allSatisfy { $0.viewsExact }

            let quality: ReportQuality
            let notes: String
            if windowVideos.isEmpty {
                quality = .partial
                notes = "لم تُرجع الصفحة منشورات عامة داخل الفترة. قد تكون الصفحة جديدة أو تحدّ إنستغرام المحتوى العام."
            } else if !complete {
                quality = .partial
                notes = "يعرض إنستغرام للزائر نحو ١٢ منشوراً حديثاً؛ قد توجد منشورات أخرى داخل الفترة. أعد التوليد لاحقاً."
            } else if !allExact {
                quality = .approximate
                notes = "مشاهدات إنستغرام المتاحة علناً للفيديو والريل فقط؛ منشورات الصور بلا مشاهدات معلنة."
            } else {
                quality = .exact
                notes = "مشاهدات ريل إنستغرام من الصفحة العامة."
            }

            let posts = windowVideos.map { video in
                ReportPost(
                    id: video.id,
                    accountID: account.id,
                    pageName: account.displayName,
                    handle: account.handle,
                    platform: .instagram,
                    title: video.title,
                    url: video.shareUrl ?? baseURL,
                    publishedAt: Date(timeIntervalSince1970: TimeInterval(video.createTime)),
                    views: video.views,
                    likes: video.likes,
                    comments: video.comments,
                    shares: video.shares,
                    viewsExact: video.viewsExact
                )
            }

            let row = ReportRow(
                accountID: account.id,
                pageName: account.displayName,
                platform: .instagram,
                program: "إنستغرام",
                posts: windowVideos.count,
                views: views,
                notes: notes,
                url: baseURL,
                quality: quality
            )
            return ParsedAccount(row: row, posts: posts)
        } catch {
            return ParsedAccount(
                row: ReportRow(
                    accountID: account.id,
                    pageName: account.displayName,
                    platform: .instagram,
                    program: "إنستغرام",
                    posts: nil,
                    views: nil,
                    notes: "تعذّرت قراءة حساب إنستغرام العام. أعد التوليد أو افتح التقرير لتعديله.",
                    url: baseURL,
                    quality: .unavailable
                ),
                posts: []
            )
        }
    }

    private func instagramWindowComplete(
        videos: [VideoItem],
        startUnix: Int,
        allPostsLoaded: Bool
    ) -> Bool {
        if videos.isEmpty { return true }
        if allPostsLoaded { return true }
        let oldest = videos.map(\.createTime).min() ?? 0
        return oldest > 0 && oldest < startUnix
    }

    private func generatedNote(for groups: [ReportGroup]) -> String {
        let rows = groups.flatMap(\.rows)
        let incomplete = rows.filter { $0.quality == .partial || $0.quality == .unavailable }.count
        let approximate = rows.filter { $0.quality == .approximate }.count
        let manual = rows.filter { $0.isManual || $0.quality == .manual }.count
        let hasFacebook = rows.contains { $0.platform == .facebook && !$0.isManual && $0.quality != .manual }
        let hasTikTok = rows.contains { $0.platform == .tiktok && !$0.isManual && $0.quality != .manual }
        let hasInstagram = rows.contains { $0.platform == .instagram && !$0.isManual && $0.quality != .manual }
        var parts: [String] = []

        if incomplete == 0 && approximate == 0 {
            if hasInstagram {
                parts.append("تمت قراءة منشورات إنستغرام ومشاهداتها المتاحة علناً مباشرة وقت التوليد.")
            } else if hasTikTok && hasFacebook {
                parts.append("تمت قراءة منشورات TikTok وفيسبوك ومشاهداتها المتاحة مباشرة وقت التوليد.")
            } else if hasFacebook {
                parts.append("تمت قراءة منشورات فيسبوك ومشاهدات الفيديو المتاحة علناً مباشرة وقت التوليد.")
            } else {
                parts.append("تمت قراءة منشورات TikTok ومشاهداتها مباشرة وقت التوليد.")
            }
        } else if incomplete > 0 {
            parts.append("توجد \(ReportNumber.full(Int64(incomplete))) صفحة لم تكتمل قراءتها؛ الأرقام الظاهرة لما تم تحميله فقط.")
        } else {
            parts.append("توجد \(ReportNumber.full(Int64(approximate))) صفحة بمشاهدات عامة غير مكتملة.")
        }

        if approximate > 0 && hasFacebook {
            parts.append("مشاهدات فيسبوك تُنشر للفيديو فقط؛ المنشورات النصية والصور لا تكشف مشاهدات عامة.")
        }
        if hasInstagram {
            parts.append("مشاهدات إنستغرام تُنشر للفيديو والريل فقط؛ منشورات الصور لا تكشف مشاهدات عامة.")
        }

        if manual > 0 {
            parts.append("توجد \(ReportNumber.full(Int64(manual))) صفحة إدخال يدوي تُعبأ داخل التقرير ولا تُقرأ تلقائياً.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - التصدير

    func export(_ document: ReportDocument) throws -> URL {
        ensureDirectories()
        let builder = ReportExcelBuilder(document: document)
        let data = try builder.build()
        let url = exportsDirectory.appendingPathComponent("\(document.fileBaseName).xlsx")
        try data.write(to: url, options: .atomic)
        refreshExportedFiles()
        return url
    }

    func refreshExportedFiles() {
        ensureDirectories()
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            exportedFiles = []
            return
        }

        let pattern = try? NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#)
        var files: [ReportFile] = []
        for url in urls where url.pathExtension.lowercased() == "xlsx" {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("Mutabaa-") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let created = values?.contentModificationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)
            let range = NSRange(location: 0, length: (name as NSString).length)
            let match = pattern?.firstMatch(in: name, range: range)
            let dayKey = match.map { (name as NSString).substring(with: $0.range) }
                ?? ReportDates.dayKey(created)
            let kind: ReportKind = name.contains("-Weekly-") ? .weekly : .daily
            let platform = exportedPlatform(from: name)
            files.append(
                ReportFile(
                    url: url,
                    platform: platform,
                    kind: kind,
                    createdAt: created,
                    size: size,
                    dayKey: dayKey
                )
            )
        }
        exportedFiles = files.sorted { $0.createdAt > $1.createdAt }
    }

    /// يقرأ المنصة من اسم ملف مثل `Mutabaa-Instagram-Daily-2026-10-26.xlsx`.
    private func exportedPlatform(from name: String) -> ReportPlatform {
        let parts = name.split(separator: "-").map(String.init)
        if parts.count > 1 {
            switch parts[1].lowercased() {
            case "tiktok": return .tiktok
            case "facebook": return .facebook
            case "instagram": return .instagram
            case "youtube": return .youtube
            default: break
            }
        }
        // ملفات الإصدارات السابقة: Mutabaa-Daily-… كانت تقارير TikTok.
        return .tiktok
    }

    func deleteExportedFile(_ file: ReportFile) {
        try? FileManager.default.removeItem(at: file.url)
        refreshExportedFiles()
    }

    var exportsFolder: URL {
        exportsDirectory
    }
}
#endif
