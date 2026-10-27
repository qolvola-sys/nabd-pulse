#!/usr/bin/env python3
"""يتحقق من بنية ملف Excel الذي يبنيه ReportExcelBuilder.

يعمل على macOS وLinux دون Excel: يفتح ZIP، يقرأ XML، ويتأكد من
الأوراق الثلاث، العنوان، رؤوس الجدول، الأرقام، الدمج، والروابط.
"""

from __future__ import annotations

import sys
import zipfile
import xml.etree.ElementTree as ET

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

NS = {"m": MAIN_NS, "r": REL_NS}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_xml(archive: zipfile.ZipFile, name: str) -> ET.Element:
    try:
        return ET.fromstring(archive.read(name))
    except KeyError:
        fail(f"الملف ينقصه الجزء {name}")
    except ET.ParseError as error:
        fail(f"XML غير صالح في {name}: {error}")
    raise AssertionError("unreachable")


def cell_value(cell: ET.Element) -> str:
    if cell.get("t") == "inlineStr":
        node = cell.find("m:is/m:t", NS)
        return node.text if node is not None and node.text is not None else ""
    node = cell.find("m:v", NS)
    return node.text if node is not None and node.text is not None else ""


def sheet_cells(root: ET.Element) -> dict[str, str]:
    cells: dict[str, str] = {}
    for cell in root.findall(".//m:sheetData/m:row/m:c", NS):
        reference = cell.get("r")
        if reference:
            cells[reference] = cell_value(cell)
    return cells


def main() -> None:
    if len(sys.argv) < 2:
        fail("مرّر مسار ملف .xlsx")

    path = sys.argv[1]
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as error:
        fail(f"ليس ملف ZIP صالحاً: {error}")

    with archive:
        bad = archive.testzip()
        if bad:
            fail(f"جزء ZIP تالف: {bad}")

        required = [
            "[Content_Types].xml",
            "_rels/.rels",
            "docProps/core.xml",
            "docProps/app.xml",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/styles.xml",
            "xl/worksheets/sheet1.xml",
            "xl/worksheets/sheet2.xml",
            "xl/worksheets/sheet3.xml",
        ]
        names = set(archive.namelist())
        for part in required:
            if part not in names:
                fail(f"الملف ينقصه الجزء {part}")

        workbook = read_xml(archive, "xl/workbook.xml")
        sheet_names = [
            sheet.get("name")
            for sheet in workbook.findall(".//m:sheets/m:sheet", NS)
        ]
        if sheet_names != ["ورقه1", "الملخص", "تفاصيل المنشورات"]:
            fail(f"أسماء الأوراق غير متوقعة: {sheet_names}")

        sheet1 = read_xml(archive, "xl/worksheets/sheet1.xml")
        cells = sheet_cells(sheet1)

        if cells.get("A1") != "منصات الأصفر":
            fail(f"عنوان التقرير غير صحيح في A1: {cells.get('A1')!r}")

        headers = ["التسلسل", "اسم الصفحة", "البرامج", "العدد المطلوب", "عدد النشر", "عدد المشاهدات", "الملاحظات", "الروابط"]
        actual_headers = [cells.get(f"{column}5") for column in "ABCDEFGH"]
        if actual_headers != headers:
            fail(f"رؤوس الجدول غير مطابقة: {actual_headers}")

        rows: dict[str, dict[str, str]] = {}
        for reference, value in cells.items():
            column = reference[0]
            row_number = reference[1:]
            rows.setdefault(row_number, {})[column] = value

        def find_row(page_name: str) -> dict[str, str]:
            for row in rows.values():
                if row.get("B") == page_name:
                    return row
            fail(f"لم يُعثر على صف الصفحة: {page_name}")
            raise AssertionError("unreachable")

        tiktok_row = find_row("الأصفر علي")
        if tiktok_row.get("E") != "2" or tiktok_row.get("F") != "3456789":
            fail(f"أرقام صف TikTok غير صحيحة: {tiktok_row}")
        if tiktok_row.get("H") != "https://www.tiktok.com/@yellow.plus":
            fail(f"رابط صف TikTok غير صحيح: {tiktok_row.get('H')!r}")

        facebook_row = find_row("صفحة فيسبوك")
        if facebook_row.get("E") != "7" or facebook_row.get("F") != "98000":
            fail(f"أرقام صف فيسبوك غير صحيحة: {facebook_row}")
        if facebook_row.get("C") != "فيسبوك":
            fail(f"برنامج صف فيسبوك غير صحيح: {facebook_row.get('C')!r}")

        # يجب أن تكون الأرقام خلايا رقمية حقيقية لا نصوصاً.
        for cell in sheet1.findall(".//m:sheetData/m:row/m:c", NS):
            if cell.get("r") in {f"{column}{row_number}" for row_number, row in rows.items() if row.get("B") in {"الأصفر علي", "صفحة فيسبوك"} for column in "EF"}:
                if cell.get("t") == "inlineStr":
                    fail(f"الخلية {cell.get('r')} مخزّنة كنص بدل رقم")
                if not cell_value(cell).isdigit():
                    fail(f"الخلية {cell.get('r')} لا تحتوي رقماً صحيحاً")

        merges = {
            merge.get("ref")
            for merge in sheet1.findall(".//m:mergeCells/m:mergeCell", NS)
        }
        if "A1:H3" not in merges:
            fail(f"دمج العنوان A1:H3 غير موجود. الموجود: {sorted(merges)[:8]}")

        view = sheet1.find(".//m:sheetView", NS)
        if view is None or view.get("rightToLeft") != "1":
            fail("ورقة التقرير ليست باتجاه من اليمين إلى اليسار")

        hyperlinks = sheet1.findall(".//m:hyperlinks/m:hyperlink", NS)
        if len(hyperlinks) < 3:
            fail(f"عدد الروابط في الورقة قليل: {len(hyperlinks)}")

        rels_name = "xl/worksheets/_rels/sheet1.xml.rels"
        if rels_name not in names:
            fail("ملف علاقات الروابط غير موجود")
        rels = read_xml(archive, rels_name)
        external_targets = [
            rel.get("Target")
            for rel in rels.findall(f"{{{REL_NS}}}Relationship")
            if rel.get("TargetMode") == "External"
        ]
        if "https://www.tiktok.com/@yellow.plus" not in external_targets:
            fail(f"رابط TikTok غير موجود في العلاقات: {external_targets}")
        if "https://www.facebook.com/yellowplus" not in external_targets:
            fail(f"رابط فيسبوك غير موجود في العلاقات: {external_targets}")

        styles = read_xml(archive, "xl/styles.xml")
        formats = [
            node.get("formatCode")
            for node in styles.findall(".//m:numFmts/m:numFmt", NS)
        ]
        if "#,##0" not in formats:
            fail(f"تنسيق الأرقام #,##0 غير موجود: {formats}")

        content_types = read_xml(archive, "[Content_Types].xml")
        overrides = [
            node.get("PartName")
            for node in content_types.findall("{http://schemas.openxmlformats.org/package/2006/content-types}Override")
        ]
        for index in (1, 2, 3):
            part = f"/xl/worksheets/sheet{index}.xml"
            if part not in overrides:
                fail(f"نوع المحتوى غير معلن للجزء {part}")

        posts_sheet = read_xml(archive, "xl/worksheets/sheet3.xml")
        posts_cells = sheet_cells(posts_sheet)
        if posts_cells.get("A4") != "#" or posts_cells.get("F4") != "المشاهدات":
            fail("رؤوس ورقة تفاصيل المنشورات غير صحيحة")

        print("PASS: ZIP/XML, 3 sheets, RTL, title, headers, numeric cells, merges and hyperlinks are valid")


if __name__ == "__main__":
    main()
