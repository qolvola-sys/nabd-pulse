import Foundation

/// يبني ملف Excel حقيقياً (`.xlsx`) من مسودة التقرير.
/// الورقة الأولى تطابق نموذج «منصات الأصفر»: العنوان، الأعمدة السبعة،
/// صفوف الصفحات، فواصل المجموعات، والإجمالي. وتُضاف ورقة ملخص وورقة
/// تفاصيل لكل منشور حتى يمكن التحقق من كل رقم.
struct ReportExcelBuilder {
    let document: ReportDocument

    func build() throws -> Data {
        let workbook = XLSXWorkbook(
            title: "\(document.title) — \(document.displayDate)",
            creator: "المتابعة",
            sheets: [mainSheet(), summarySheet(), postsSheet()]
        )
        return try workbook.data()
    }

    // MARK: - الورقة الرئيسية

    private func mainSheet() -> XLSXSheet {
        var rows: [XLSXRow] = []
        var merges: [String] = []

        // العنوان
        rows.append(mergedRow(
            text: document.title.isEmpty ? "منصات الأصفر" : document.title,
            columns: 7,
            style: .title,
            height: 28,
            merge: "A1:G3",
            mergeInto: &merges
        ))
        rows.append(blankRow(columns: 7, style: .title, height: 28))
        rows.append(blankRow(columns: 7, style: .title, height: 28))

        // الفترة ووقت التوليد
        let periodLine = "\(document.kind.longTitle)  ·  \(document.periodText)  ·  تم التوليد: \(ReportDates.displayDateTime(document.generatedAt))"
        rows.append(mergedRow(
            text: periodLine,
            columns: 7,
            style: .subtitle,
            height: 24,
            merge: "A4:G4",
            mergeInto: &merges
        ))

        // رأس الجدول
        let headers = ["التسلسل", "اسم الصفحة", "البرامج", "عدد النشر", "عدد المشاهدات", "الملاحظات", "الروابط"]
        rows.append(XLSXRow(cells: headers.map { XLSXCell.text($0, style: .tableHeader) }, height: 30))

        // فاصل كما في النموذج
        rows.append(blankRow(columns: 7, style: .body, height: 8))

        var serial: Int64 = 0
        for (groupIndex, group) in document.groups.enumerated() {
            if groupIndex > 0 {
                rows.append(blankRow(columns: 7, style: .body, height: 8))
            }

            let groupLine = "\(group.name)  ·  \(ReportNumber.full(Int64(group.rows.count))) صفحة  ·  \(ReportNumber.full(Int64(group.totalPosts))) منشور  ·  \(ReportNumber.full(group.totalViews)) مشاهدة"
            rows.append(mergedRow(
                text: groupLine,
                columns: 7,
                style: .section,
                height: 25,
                merge: "A\(rows.count + 1):G\(rows.count + 1)",
                mergeInto: &merges
            ))

            for (index, row) in group.rows.enumerated() {
                serial += 1
                let alt = index % 2 == 1
                rows.append(XLSXRow(cells: [
                    XLSXCell.integer(serial, style: alt ? .integerAlt : .integer),
                    XLSXCell.text(displayName(row.pageName), style: alt ? .bodyAlt : .body),
                    XLSXCell.text(row.program, style: alt ? .bodyAlt : .body),
                    optionalInteger(row.posts.map { Int64($0) }, alt: alt),
                    optionalInteger(row.views, alt: alt),
                    XLSXCell.text(row.notes, style: alt ? .bodyAlt : .body),
                    linkCell(row.url, alt: alt),
                ], height: 22))
            }
        }

        if document.groups.isEmpty {
            rows.append(mergedRow(
                text: "لا توجد صفحات في هذا التقرير",
                columns: 7,
                style: .note,
                height: 30,
                merge: "A\(rows.count + 1):G\(rows.count + 1)",
                mergeInto: &merges
            ))
        }

        // الإجمالي
        let totalStart = rows.count + 1
        rows.append(XLSXRow(cells: [
            XLSXCell.text("الإجمالي", style: .totalText),
            XLSXCell.text("", style: .totalText),
            XLSXCell.text("", style: .totalText),
            XLSXCell.integer(Int64(document.totalPosts), style: .totalInteger),
            XLSXCell.number(Double(document.totalViews), style: .totalNumber),
            XLSXCell.text(document.qualitySummary, style: .totalText),
            XLSXCell.text("", style: .totalText),
        ], height: 28))
        merges.append("A\(totalStart):C\(totalStart)")

        // ملاحظات الجودة
        rows.append(blankRow(columns: 7, style: .body, height: 8))
        rows.append(mergedRow(
            text: qualityNote(),
            columns: 7,
            style: .note,
            height: 42,
            merge: "A\(rows.count + 1):G\(rows.count + 1)",
            mergeInto: &merges
        ))
        rows.append(mergedRow(
            text: "النافذة الزمنية: \(document.periodText). الحد الأخير غير شامل. المشاهدات هي الأرقام الفعلية وقت توليد التقرير، وقد تزيد بعد ذلك.",
            columns: 7,
            style: .note,
            height: 38,
            merge: "A\(rows.count + 1):G\(rows.count + 1)",
            mergeInto: &merges
        ))
        rows.append(mergedRow(
            text: "الخلايا الفارغة تعني عدم توفر إدخال لهذه الصفحة. يمكن تعديل كل الحقول من شاشة التقرير ثم إعادة التصدير.",
            columns: 7,
            style: .note,
            height: 38,
            merge: "A\(rows.count + 1):G\(rows.count + 1)",
            mergeInto: &merges
        ))

        return XLSXSheet(
            name: "ورقه1",
            rightToLeft: true,
            tabColor: "FF0F766E",
            columns: [
                XLSXColumn(width: 7),
                XLSXColumn(width: 24),
                XLSXColumn(width: 13),
                XLSXColumn(width: 11),
                XLSXColumn(width: 17),
                XLSXColumn(width: 32),
                XLSXColumn(width: 44),
            ],
            rows: rows,
            freezeRows: 5,
            autoFilter: nil,
            merges: merges,
            showGridLines: false
        )
    }

    // MARK: - ورقة الملخص

    private func summarySheet() -> XLSXSheet {
        var rows: [XLSXRow] = []
        var merges: [String] = []

        rows.append(mergedRow(
            text: "ملخص \(document.kind.title)",
            columns: 5,
            style: .title,
            height: 28,
            merge: "A1:E2",
            mergeInto: &merges
        ))
        rows.append(blankRow(columns: 5, style: .title, height: 26))
        rows.append(mergedRow(
            text: "\(document.spaceName)  ·  \(document.periodText)",
            columns: 5,
            style: .subtitle,
            height: 24,
            merge: "A3:E3",
            mergeInto: &merges
        ))
        rows.append(blankRow(columns: 5, style: .body, height: 8))

        rows.append(XLSXRow(cells: [
            XLSXCell.text("المؤشر", style: .tableHeader),
            XLSXCell.text("القيمة", style: .tableHeader),
            XLSXCell.text("", style: .tableHeader),
            XLSXCell.text("", style: .tableHeader),
            XLSXCell.text("", style: .tableHeader),
        ], height: 28))
        merges.append("A5:E5")

        let kpis: [(String, String)] = [
            ("المجموعات", ReportNumber.full(Int64(document.groups.count))),
            ("الصفحات", ReportNumber.full(Int64(document.rows.count))),
            ("إجمالي المنشورات", ReportNumber.full(Int64(document.totalPosts))),
            ("إجمالي المشاهدات", ReportNumber.full(document.totalViews)),
            ("صفحات محمّلة بدقة", ReportNumber.full(Int64(document.exactRows.count))),
            ("صفحات تحتاج مراجعة", ReportNumber.full(Int64(document.incompleteRows.count + document.approximateRows.count))),
            ("صفحات إدخال يدوي", ReportNumber.full(Int64(document.manualRows.count))),
        ]
        for (index, item) in kpis.enumerated() {
            let alt = index % 2 == 1
            rows.append(XLSXRow(cells: [
                XLSXCell.text(item.0, style: alt ? .bodyAlt : .body),
                XLSXCell.text(item.1, style: alt ? .bodyAlt : .body),
                XLSXCell.text("", style: alt ? .bodyAlt : .body),
                XLSXCell.text("", style: alt ? .bodyAlt : .body),
                XLSXCell.text("", style: alt ? .bodyAlt : .body),
            ], height: 22))
            let rowNumber = rows.count
            merges.append("B\(rowNumber):E\(rowNumber)")
        }

        rows.append(blankRow(columns: 5, style: .body, height: 10))

        rows.append(XLSXRow(cells: [
            XLSXCell.text("المجموعة", style: .tableHeader),
            XLSXCell.text("الصفحات", style: .tableHeader),
            XLSXCell.text("المنشورات", style: .tableHeader),
            XLSXCell.text("المشاهدات", style: .tableHeader),
            XLSXCell.text("الحالة", style: .tableHeader),
        ], height: 28))

        for (index, group) in document.groups.enumerated() {
            let alt = index % 2 == 1
            let quality = quality(for: group)
            rows.append(XLSXRow(cells: [
                XLSXCell.text(group.name, style: alt ? .bodyAlt : .body),
                XLSXCell.integer(Int64(group.rows.count), style: alt ? .integerAlt : .integer),
                XLSXCell.integer(Int64(group.totalPosts), style: alt ? .integerAlt : .integer),
                XLSXCell.integer(group.totalViews, style: alt ? .integerAlt : .integer),
                XLSXCell.text(quality.label, style: quality.style),
            ], height: 22))
        }

        if document.groups.isEmpty {
            rows.append(XLSXRow(cells: [
                XLSXCell.text("لا توجد مجموعات", style: .body),
                XLSXCell.blank(style: .integer),
                XLSXCell.blank(style: .integer),
                XLSXCell.blank(style: .integer),
                XLSXCell.text("—", style: .note),
            ], height: 22))
        }

        rows.append(XLSXRow(cells: [
            XLSXCell.text("الإجمالي", style: .totalText),
            XLSXCell.integer(Int64(document.rows.count), style: .totalInteger),
            XLSXCell.integer(Int64(document.totalPosts), style: .totalInteger),
            XLSXCell.number(Double(document.totalViews), style: .totalNumber),
            XLSXCell.text(document.qualitySummary, style: .totalText),
        ], height: 28))

        rows.append(blankRow(columns: 5, style: .body, height: 8))
        rows.append(mergedRow(
            text: document.note,
            columns: 5,
            style: .note,
            height: 36,
            merge: "A\(rows.count + 1):E\(rows.count + 1)",
            mergeInto: &merges
        ))

        return XLSXSheet(
            name: "الملخص",
            rightToLeft: true,
            tabColor: "FF0369A1",
            columns: [
                XLSXColumn(width: 24),
                XLSXColumn(width: 16),
                XLSXColumn(width: 16),
                XLSXColumn(width: 18),
                XLSXColumn(width: 24),
            ],
            rows: rows,
            freezeRows: 0,
            merges: merges,
            showGridLines: false
        )
    }

    // MARK: - ورقة تفاصيل المنشورات

    private func postsSheet() -> XLSXSheet {
        var rows: [XLSXRow] = []
        var merges: [String] = []

        rows.append(mergedRow(
            text: "تفاصيل المنشورات",
            columns: 11,
            style: .title,
            height: 28,
            merge: "A1:K2",
            mergeInto: &merges
        ))
        rows.append(blankRow(columns: 11, style: .title, height: 26))
        rows.append(mergedRow(
            text: "\(document.periodText)  ·  \(ReportNumber.full(Int64(document.posts.count))) منشوراً  ·  \(ReportNumber.full(document.posts.reduce(Int64(0)) { $0 + $1.views })) مشاهدة",
            columns: 11,
            style: .subtitle,
            height: 24,
            merge: "A3:K3",
            mergeInto: &merges
        ))

        let headers = ["#", "المجموعة", "اسم الصفحة", "المنصة", "وقت النشر", "المشاهدات", "الإعجابات", "التعليقات", "المشاركات", "دقة المشاهدات", "الرابط"]
        rows.append(XLSXRow(cells: headers.map { XLSXCell.text($0, style: .tableHeader) }, height: 28))

        let groupByAccount = groupNamesByAccount()
        let sorted = document.posts.sorted { $0.publishedAt > $1.publishedAt }
        for (index, post) in sorted.enumerated() {
            let alt = index % 2 == 1
            let groupName = post.accountID.flatMap { groupByAccount[$0] } ?? "—"
            let exactText = post.viewsExact ? "دقيق" : "مقرّب"
            rows.append(XLSXRow(cells: [
                XLSXCell.integer(Int64(index + 1), style: alt ? .integerAlt : .integer),
                XLSXCell.text(groupName, style: alt ? .bodyAlt : .body),
                XLSXCell.text(displayName(post.pageName), style: alt ? .bodyAlt : .body),
                XLSXCell.text(post.platform.defaultProgram, style: alt ? .bodyAlt : .body),
                XLSXCell.text(ReportDates.displayDateTime(post.publishedAt), style: alt ? .bodyAlt : .body),
                XLSXCell.integer(post.views, style: alt ? .integerAlt : .integer),
                XLSXCell.integer(post.likes, style: alt ? .integerAlt : .integer),
                XLSXCell.integer(post.comments, style: alt ? .integerAlt : .integer),
                XLSXCell.integer(post.shares, style: alt ? .integerAlt : .integer),
                XLSXCell.text(exactText, style: post.viewsExact ? .goodPlain : .warningPlain),
                linkCell(post.url, alt: alt),
            ], height: 22))
        }

        if sorted.isEmpty {
            rows.append(mergedRow(
                text: "لا توجد منشورات مسجلة في هذه الفترة",
                columns: 11,
                style: .note,
                height: 30,
                merge: "A\(rows.count + 1):K\(rows.count + 1)",
                mergeInto: &merges
            ))
        } else {
            rows.append(XLSXRow(cells: [
                XLSXCell.text("الإجمالي", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.number(Double(sorted.reduce(Int64(0)) { $0 + $1.views }), style: .totalNumber),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
                XLSXCell.text("", style: .totalText),
            ], height: 28))
            let totalRow = rows.count
            merges.append("A\(totalRow):E\(totalRow)")
        }

        return XLSXSheet(
            name: "تفاصيل المنشورات",
            rightToLeft: true,
            tabColor: "FF7C3AED",
            columns: [
                XLSXColumn(width: 6),
                XLSXColumn(width: 20),
                XLSXColumn(width: 22),
                XLSXColumn(width: 11),
                XLSXColumn(width: 24),
                XLSXColumn(width: 15),
                XLSXColumn(width: 11),
                XLSXColumn(width: 11),
                XLSXColumn(width: 11),
                XLSXColumn(width: 13),
                XLSXColumn(width: 46),
            ],
            rows: rows,
            freezeRows: 4,
            autoFilter: sorted.isEmpty ? nil : "A4:K\(4 + sorted.count)",
            merges: merges,
            showGridLines: false
        )
    }

    // MARK: - أدوات

    private func displayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func optionalInteger(_ value: Int64?, alt: Bool) -> XLSXCell {
        guard let value else { return .blank(style: alt ? .integerAlt : .integer) }
        return XLSXCell.integer(value, style: alt ? .integerAlt : .integer)
    }

    private func linkCell(_ raw: String, alt: Bool) -> XLSXCell {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .blank(style: alt ? .bodyAlt : .body) }
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return XLSXCell.text(text, style: .link, hyperlink: text)
        }
        return XLSXCell.text(text, style: alt ? .bodyAlt : .body)
    }

    private func mergedRow(
        text: String,
        columns: Int,
        style: XLSXStyle,
        height: Double,
        merge: String,
        mergeInto merges: inout [String]
    ) -> XLSXRow {
        var cells = [XLSXCell.text(text, style: style)]
        if columns > 1 {
            for _ in 1..<columns {
                cells.append(XLSXCell.text("", style: style))
            }
        }
        merges.append(merge)
        return XLSXRow(cells: cells, height: height)
    }

    private func blankRow(columns: Int, style: XLSXStyle, height: Double) -> XLSXRow {
        XLSXRow(cells: (0..<columns).map { _ in XLSXCell.text("", style: style) }, height: height)
    }

    private func quality(for group: ReportGroup) -> ReportQuality {
        let rows = group.rows
        guard !rows.isEmpty else { return .unavailable }
        if rows.contains(where: { $0.quality == .unavailable }) { return .unavailable }
        if rows.contains(where: { $0.quality == .partial }) { return .partial }
        if rows.contains(where: { $0.quality == .approximate }) { return .approximate }
        if rows.allSatisfy({ $0.quality == .manual }) { return .manual }
        return .exact
    }

    private func groupNamesByAccount() -> [String: String] {
        var result: [String: String] = [:]
        for group in document.groups {
            for row in group.rows {
                if let accountID = row.accountID, result[accountID] == nil {
                    result[accountID] = group.name
                }
            }
        }
        return result
    }

    private func qualityNote() -> String {
        var parts: [String] = []
        if document.isFullyExact {
            parts.append("كل الأرقام المحمّلة في هذه الفترة قُرئت مباشرة من المنصة بدقة ١٠٠٪.")
        } else {
            parts.append(document.qualitySummary)
        }
        if !document.note.isEmpty {
            parts.append(document.note)
        }
        parts.append("لا تُقدَّم أي قراءة ناقصة كرقم نهائي؛ تُعلَّم الصفحة باللون والملاحظة المناسبة.")
        if document.rows.contains(where: { $0.platform == .facebook }) {
            parts.append("مشاهدات فيسبوك المتاحة علناً هي مشاهدات الفيديو فقط؛ المنشورات النصية والصور لا تكشف مشاهدات عامة.")
        }
        if document.rows.contains(where: { $0.platform == .instagram }) {
            parts.append("مشاهدات إنستغرام المتاحة علناً هي مشاهدات الفيديو والريل فقط؛ منشورات الصور لا تكشف مشاهدات عامة.")
        }
        return parts.joined(separator: " ")
    }
}
