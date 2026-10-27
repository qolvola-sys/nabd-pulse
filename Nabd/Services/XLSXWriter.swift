import Foundation

/// كاتب ملفات Excel بصيغة `.xlsx` مبني على Foundation فقط.
/// الملفات تُبنى من أجزاء XML قياسية وتُحزم في ZIP بطريقة Store
/// حتى تعمل بدون أي مكتبة خارجية أو اتصال بالشبكة.
enum XLSXWriterError: LocalizedError {
    case noSheets
    case tooManySheets
    case invalidSheetName(String)
    case archiveTooLarge

    var errorDescription: String? {
        switch self {
        case .noSheets:
            return "لا توجد أوراق لكتابتها في الملف"
        case .tooManySheets:
            return "عدد أوراق Excel يتجاوز الحد المسموح"
        case .invalidSheetName(let name):
            return "اسم ورقة Excel غير صالح: \(name)"
        case .archiveTooLarge:
            return "حجم التقرير يتجاوز الحد المسموح"
        }
    }
}

struct XLSXWorkbook {
    var title: String
    var creator: String
    var sheets: [XLSXSheet]

    init(title: String, creator: String = "Nabd", sheets: [XLSXSheet]) {
        self.title = title
        self.creator = creator
        self.sheets = sheets
    }

    func data() throws -> Data {
        guard !sheets.isEmpty else { throw XLSXWriterError.noSheets }
        guard sheets.count <= 200 else { throw XLSXWriterError.tooManySheets }

        var normalizedSheets: [XLSXSheet] = []
        var usedNames = Set<String>()
        for (index, sheet) in sheets.enumerated() {
            let name = try Self.safeSheetName(sheet.name, fallback: "ورقة \(index + 1)")
            guard !usedNames.contains(name) else {
                throw XLSXWriterError.invalidSheetName(sheet.name)
            }
            usedNames.insert(name)
            var copy = sheet
            copy.name = name
            normalizedSheets.append(copy)
        }

        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", Data(partContentTypes(sheets: normalizedSheets).utf8)))
        files.append(("_rels/.rels", Data(rootRelationships().utf8)))
        files.append(("docProps/core.xml", Data(coreProperties().utf8)))
        files.append(("docProps/app.xml", Data(appProperties().utf8)))
        files.append(("xl/workbook.xml", Data(workbookXML(sheets: normalizedSheets).utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(workbookRelationships(sheetCount: normalizedSheets.count).utf8)))
        files.append(("xl/styles.xml", Data(styleSheetXML().utf8)))

        for (index, sheet) in normalizedSheets.enumerated() {
            let rendered = sheetXML(sheet)
            files.append(("xl/worksheets/sheet\(index + 1).xml", Data(rendered.xml.utf8)))
            if !rendered.hyperlinks.isEmpty {
                files.append((
                    "xl/worksheets/_rels/sheet\(index + 1).xml.rels",
                    Data(sheetRelationships(hyperlinks: rendered.hyperlinks).utf8)
                ))
            }
        }

        return try ZIPStore.archive(files)
    }

    // MARK: - أجزاء الحزمة

    private func partContentTypes(sheets: [XLSXSheet]) -> String {
        var overrides = """
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        """
        for index in sheets.indices {
            overrides += "\n<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        \(overrides)
        </Types>
        """
    }

    private func rootRelationships() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private func coreProperties() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:title>\(Self.xmlEscape(title))</dc:title>
        <dc:creator>\(Self.xmlEscape(creator))</dc:creator>
        <cp:lastModifiedBy>\(Self.xmlEscape(creator))</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func appProperties() -> String {
        let titles = sheets.map { sheet in
            "<vt:lpstr>\(Self.xmlEscape(sheet.name))</vt:lpstr>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>\(Self.xmlEscape(creator))</Application>
        <DocSecurity>0</DocSecurity>
        <ScaleCrop>false</ScaleCrop>
        <HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>\(sheets.count)</vt:i4></vt:variant></vt:vector></HeadingPairs>
        <TitlesOfParts><vt:vector size="\(sheets.count)" baseType="lpstr">\(titles)</vt:vector></TitlesOfParts>
        </Properties>
        """
    }

    private func workbookXML(sheets: [XLSXSheet]) -> String {
        var sheetTags: [String] = []
        for (index, sheet) in sheets.enumerated() {
            sheetTags.append("<sheet name=\"\(Self.xmlEscape(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <fileVersion appName="xl" lastEdited="7" lowestEdited="7" rupBuild="23426"/>
        <workbookPr date1904="0" defaultThemeVersion="164011"/>
        <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="26000" windowHeight="16000"/></bookViews>
        <sheets>\(sheetTags.joined())</sheets>
        <calcPr calcId="191029" fullCalcOnLoad="1"/>
        </workbook>
        """
    }

    private func workbookRelationships(sheetCount: Int) -> String {
        var relationships: [String] = []
        for index in 1...sheetCount {
            relationships.append("<Relationship Id=\"rId\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>")
        }
        relationships.append("<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(relationships.joined(separator: "\n"))
        </Relationships>
        """
    }

    // MARK: - ورقة العمل

    private struct SheetHyperlink {
        var reference: String
        var target: String
    }

    private struct RenderedSheet {
        var xml: String
        var hyperlinks: [SheetHyperlink]
    }

    private func sheetXML(_ sheet: XLSXSheet) -> RenderedSheet {
        let maxColumn = max(sheet.rows.map(\.cells.count).max() ?? 1, 1)
        let maxRow = max(sheet.rows.count, 1)
        let dimension = "A1:\(Self.columnName(maxColumn))\(maxRow)"
        let safeColumns = sheet.columns.isEmpty
            ? [XLSXColumn(width: 16)]
            : sheet.columns

        var colsXML = ""
        for (index, column) in safeColumns.enumerated() {
            colsXML += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(Self.decimal(column.width))\" customWidth=\"1\"/>"
        }

        var rowsXML = ""
        var hyperlinks: [SheetHyperlink] = []
        for (rowIndex, row) in sheet.rows.enumerated() {
            let number = rowIndex + 1
            var attributes = "r=\"\(number)\""
            if let height = row.height {
                attributes += " ht=\"\(Self.decimal(height))\" customHeight=\"1\""
            }
            var cellsXML = ""
            for (cellIndex, cell) in row.cells.enumerated() {
                if let target = cell.hyperlink, !target.isEmpty {
                    hyperlinks.append(
                        SheetHyperlink(
                            reference: "\(Self.columnName(cellIndex + 1))\(number)",
                            target: target
                        )
                    )
                }
                cellsXML += cellXML(cell, column: cellIndex + 1, row: number)
            }
            rowsXML += "<row \(attributes)>\(cellsXML)</row>"
        }

        var paneXML = ""
        if sheet.freezeRows > 0 {
            let split = min(sheet.freezeRows, maxRow)
            let topLeft = "A\(split + 1)"
            paneXML = "<pane ySplit=\"\(split)\" topLeftCell=\"\(topLeft)\" activePane=\"bottomLeft\" state=\"frozen\"/><selection pane=\"bottomLeft\" activeCell=\"\(topLeft)\" sqref=\"\(topLeft)\"/>"
        } else {
            paneXML = "<selection activeCell=\"A1\" sqref=\"A1\"/>"
        }

        var autoFilterXML = ""
        if let reference = sheet.autoFilter, !reference.isEmpty {
            autoFilterXML = "<autoFilter ref=\"\(Self.xmlEscape(reference))\"/>"
        }

        var mergesXML = ""
        let merges = sheet.merges.filter { !$0.isEmpty }
        if !merges.isEmpty {
            let mergeTags = merges.map { merge in
                "<mergeCell ref=\"\(Self.xmlEscape(merge))\"/>"
            }.joined()
            mergesXML = "<mergeCells count=\"\(merges.count)\">\(mergeTags)</mergeCells>"
        }

        var sheetPr = "<sheetPr><pageSetUpPr fitToPage=\"1\"/></sheetPr>"
        if let tabColor = sheet.tabColor, !tabColor.isEmpty {
            sheetPr = "<sheetPr><tabColor rgb=\"\(Self.xmlEscape(tabColor))\"/><pageSetUpPr fitToPage=\"1\"/></sheetPr>"
        }

        var hyperlinksXML = ""
        if !hyperlinks.isEmpty {
            let links = hyperlinks.enumerated().map { index, link in
                "<hyperlink ref=\"\(link.reference)\" r:id=\"rId\(index + 1)\"/>"
            }
            hyperlinksXML = "<hyperlinks>\(links.joined())</hyperlinks>"
        }

        let rightToLeft = sheet.rightToLeft ? " rightToLeft=\"1\"" : ""
        let gridLines = sheet.showGridLines ? "1" : "0"

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        \(sheetPr)
        <dimension ref="\(dimension)"/>
        <sheetViews><sheetView showGridLines="\(gridLines)"\(rightToLeft) workbookViewId="0">\(paneXML)</sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="18"/>
        <cols>\(colsXML)</cols>
        <sheetData>\(rowsXML)</sheetData>
        \(autoFilterXML)
        \(mergesXML)
        \(hyperlinksXML)
        <pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>
        <pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0" horizontalDpi="300" verticalDpi="300"/>
        </worksheet>
        """
        return RenderedSheet(xml: xml, hyperlinks: hyperlinks)
    }

    private func sheetRelationships(hyperlinks: [SheetHyperlink]) -> String {
        var links: [String] = []
        for (index, link) in hyperlinks.enumerated() {
            links.append(
                "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(Self.xmlEscape(link.target))\" TargetMode=\"External\"/>"
            )
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(links.joined(separator: "\n"))
        </Relationships>
        """
    }

    private func cellXML(_ cell: XLSXCell, column: Int, row: Int) -> String {
        let reference = "\(Self.columnName(column))\(row)"
        let style = cell.style.rawValue

        switch cell.value {
        case .blank:
            return "<c r=\"\(reference)\" s=\"\(style)\"/>"
        case .text(let value):
            guard !value.isEmpty else {
                return "<c r=\"\(reference)\" s=\"\(style)\"/>"
            }
            return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(Self.xmlEscape(String(value.prefix(32_767))))</t></is></c>"
        case .integer(let value):
            return "<c r=\"\(reference)\" s=\"\(style)\"><v>\(value)</v></c>"
        case .number(let value):
            let safe = value.isFinite ? value : 0
            return "<c r=\"\(reference)\" s=\"\(style)\"><v>\(Self.numberString(safe))</v></c>"
        }
    }

    // MARK: - الأنماط

    private func styleSheetXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="2">
        <numFmt numFmtId="164" formatCode="#,##0"/>
        <numFmt numFmtId="165" formatCode="0.0%"/>
        </numFmts>
        <fonts count="15">
        <font><sz val="11"/><color rgb="FF182230"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="20"/><color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>
        <font><sz val="10"/><color rgb="FFE6F4F1"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>
        <font><sz val="10"/><color rgb="FF182230"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="10"/><color rgb="FF0F766E"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="10"/><color rgb="FF047857"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="10"/><color rgb="FFB45309"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="10"/><color rgb="FFB91C1C"/><name val="Arial"/><family val="2"/></font>
        <font><sz val="9"/><color rgb="FF667085"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="11"/><color rgb="FF0F172A"/><name val="Arial"/><family val="2"/></font>
        <font><b/><sz val="14"/><color rgb="FF0F172A"/><name val="Arial"/><family val="2"/></font>
        <font><u/><sz val="10"/><color rgb="FF0369A1"/><name val="Arial"/><family val="2"/></font>
        <font><u/><sz val="10"/><color rgb="FF0563C1"/><name val="Arial"/><family val="2"/></font>
        </fonts>
        <fills count="10">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF0B1220"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF0F766E"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF1E293B"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFF1F5F9"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFECFDF5"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFFFBEB"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFEF2F2"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFE0F2FE"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="3">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left/><right/><top/><bottom style="thin"><color rgb="FFD7DEE8"/></bottom><diagonal/></border>
        <border><left style="thin"><color rgb="FFD7DEE8"/></left><right style="thin"><color rgb="FFD7DEE8"/></right><top style="thin"><color rgb="FFD7DEE8"/></top><bottom style="thin"><color rgb="FFD7DEE8"/></bottom><diagonal/></border>
        </borders>
        <cellStyleXfs count="1">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
        </cellStyleXfs>
        <cellXfs count="33">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="3" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="4" fillId="4" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="5" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="5" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="5" fillId="5" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="5" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="5" fillId="5" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="165" fontId="5" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="165" fontId="5" fillId="5" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="11" fillId="9" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="11" fillId="9" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="11" fillId="9" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="165" fontId="11" fillId="9" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="7" fillId="6" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="8" fillId="7" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="9" fillId="8" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="10" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="right" vertical="top" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="10" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="12" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" readingOrder="1"/></xf>
        <xf numFmtId="164" fontId="12" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" readingOrder="1"/></xf>
        <xf numFmtId="165" fontId="12" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center" readingOrder="1"/></xf>
        <xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="5" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="13" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="7" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="8" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="0" fontId="9" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>
        <xf numFmtId="164" fontId="7" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="1"/></xf>
        <xf numFmtId="0" fontId="14" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1" readingOrder="1"/></xf>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        <dxfs count="0"/>
        <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
        </styleSheet>
        """
    }

    // MARK: - أدوات

    private static func safeSheetName(_ raw: String, fallback: String) throws -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = fallback }
        let invalid = CharacterSet(charactersIn: "[]:*?/\\")
        name = name.components(separatedBy: invalid).joined(separator: " ")
        name = String(name.prefix(31)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw XLSXWriterError.invalidSheetName(raw) }
        return name
    }

    private static func columnName(_ index: Int) -> String {
        var value = max(index, 1)
        var result = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar(65 + (value % 26))!
            result = String(scalar) + result
            value /= 26
        }
        return result
    }

    private static func decimal(_ value: Double) -> String {
        let safe = value.isFinite ? value : 0
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), safe)
    }

    private static func numberString(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 9_007_199_254_740_992 {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private static func xmlEscape(_ value: String) -> String {
        let cleaned = value.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D ||
            (scalar.value >= 0x20 && scalar.value <= 0xD7FF) ||
            (scalar.value >= 0xE000 && scalar.value <= 0xFFFD) ||
            (scalar.value >= 0x10000 && scalar.value <= 0x10FFFF)
        }
        var result = cleaned.map { String($0) }.joined()
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }
}

struct XLSXSheet {
    var name: String
    var rightToLeft: Bool
    var tabColor: String?
    var columns: [XLSXColumn]
    var rows: [XLSXRow]
    var freezeRows: Int
    var autoFilter: String?
    var merges: [String]
    var showGridLines: Bool

    init(
        name: String,
        rightToLeft: Bool = true,
        tabColor: String? = nil,
        columns: [XLSXColumn],
        rows: [XLSXRow],
        freezeRows: Int = 0,
        autoFilter: String? = nil,
        merges: [String] = [],
        showGridLines: Bool = false
    ) {
        self.name = name
        self.rightToLeft = rightToLeft
        self.tabColor = tabColor
        self.columns = columns
        self.rows = rows
        self.freezeRows = freezeRows
        self.autoFilter = autoFilter
        self.merges = merges
        self.showGridLines = showGridLines
    }
}

struct XLSXColumn {
    var width: Double
}

struct XLSXRow {
    var cells: [XLSXCell]
    var height: Double?

    init(cells: [XLSXCell], height: Double? = nil) {
        self.cells = cells
        self.height = height
    }
}

struct XLSXCell {
    enum Value {
        case blank
        case text(String)
        case number(Double)
        case integer(Int64)
    }

    var value: Value
    var style: XLSXStyle
    var hyperlink: String?

    init(_ value: Value = .blank, style: XLSXStyle = .body, hyperlink: String? = nil) {
        self.value = value
        self.style = style
        self.hyperlink = hyperlink
    }

    static func text(_ value: String, style: XLSXStyle = .body, hyperlink: String? = nil) -> XLSXCell {
        XLSXCell(.text(value), style: style, hyperlink: hyperlink)
    }

    static func integer(_ value: Int64, style: XLSXStyle = .integer) -> XLSXCell {
        XLSXCell(.integer(value), style: style)
    }

    static func number(_ value: Double, style: XLSXStyle = .number) -> XLSXCell {
        XLSXCell(.number(value), style: style)
    }

    static func blank(style: XLSXStyle = .body) -> XLSXCell {
        XLSXCell(.blank, style: style)
    }
}

enum XLSXStyle: Int {
    case base = 0
    case title = 1
    case subtitle = 2
    case section = 3
    case tableHeader = 4
    case body = 5
    case bodyAlt = 6
    case number = 7
    case numberAlt = 8
    case integer = 9
    case integerAlt = 10
    case percent = 11
    case percentAlt = 12
    case totalText = 13
    case totalInteger = 14
    case totalNumber = 15
    case totalPercent = 16
    case good = 17
    case warning = 18
    case bad = 19
    case note = 20
    case kpiLabel = 21
    case kpiInteger = 22
    case kpiNumber = 23
    case kpiPercent = 24
    case centered = 25
    case centeredAlt = 26
    case kpiText = 27
    case goodPlain = 28
    case warningPlain = 29
    case badPlain = 30
    case accentInteger = 31
    case link = 32
}

// MARK: - ZIP (Store)

private enum ZIPStore {
    private struct Entry {
        let name: String
        let data: Data
    }

    static func archive(_ files: [(String, Data)]) throws -> Data {
        var entries: [Entry] = []
        for (name, data) in files {
            entries.append(Entry(name: name, data: data))
        }
        guard entries.count <= Int(UInt16.max) else { throw XLSXWriterError.archiveTooLarge }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let year = max(1980, min(2107, parts.year ?? 2026))
        let month = max(1, min(12, parts.month ?? 1))
        let day = max(1, min(31, parts.day ?? 1))
        let hour = max(0, min(23, parts.hour ?? 0))
        let minute = max(0, min(59, parts.minute ?? 0))
        let second = max(0, min(59, parts.second ?? 0))
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)

        var output = Data()
        var central = Data()
        var offset = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= Int(UInt16.max),
                  let size = UInt32(exactly: entry.data.count),
                  let localOffset = UInt32(exactly: offset) else {
                throw XLSXWriterError.archiveTooLarge
            }
            let crc = crc32(entry.data)

            output.appendUInt32(0x0403_4B50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(dosTime)
            output.appendUInt16(dosDate)
            output.appendUInt32(crc)
            output.appendUInt32(size)
            output.appendUInt32(size)
            output.appendUInt16(UInt16(nameData.count))
            output.appendUInt16(0)
            output.append(nameData)
            output.append(entry.data)

            central.appendUInt32(0x0201_4B50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(dosTime)
            central.appendUInt16(dosDate)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(localOffset)
            central.append(nameData)

            offset += 30 + nameData.count + entry.data.count
        }

        guard let centralSize = UInt32(exactly: central.count),
              let centralOffset = UInt32(exactly: offset) else {
            throw XLSXWriterError.archiveTooLarge
        }

        output.append(central)
        output.appendUInt32(0x0605_4B50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(centralSize)
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)
        return output
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
