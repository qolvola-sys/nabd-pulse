import XCTest

final class GroupsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func clean(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    @discardableResult
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 18
    ) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return true
            }
            app.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.35)
        }
        return element.exists && element.isHittable
    }

    private func scrollToTop(_ app: XCUIApplication, swipes: Int = 14) {
        for _ in 0..<swipes {
            app.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func waitForCleanedText(
        _ expected: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let found = app.staticTexts.allElementsBoundByIndex.contains {
                clean($0.label) == expected
            }
            if found { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// يعيد نص العنصر المطابق بعد إزالة علامات الاتجاه، أو nil.
    private func scrollUntilCleanedText(
        containing fragment: String,
        in app: XCUIApplication,
        maxSwipes: Int = 18
    ) -> String? {
        for _ in 0..<maxSwipes {
            let matches = app.staticTexts.allElementsBoundByIndex.filter {
                clean($0.label).contains(fragment)
            }
            if let hittable = matches.first(where: { $0.isHittable }) {
                return clean(hittable.label)
            }
            app.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.35)
        }
        let matches = app.staticTexts.allElementsBoundByIndex.filter {
            clean($0.label).contains(fragment)
        }
        return matches.first.map { clean($0.label) }
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Text field was not found")
        field.tap()
        let current = (field.value as? String) ?? ""
        let deletes = String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: max(current.count + 8, 30)
        )
        field.typeText(deletes)
        field.typeText(text)
    }

    private func dumpButtons(_ app: XCUIApplication, _ tag: String) {
        print("BUTTONS_\(tag)_START")
        for button in app.buttons.allElementsBoundByIndex {
            print("BUTTON: \(button.label) id=\(button.identifier) enabled=\(button.isEnabled) frame=\(button.frame)")
        }
        print("BUTTONS_\(tag)_END")
    }

    private func openMoveSheet(for displayName: String, app: XCUIApplication) -> Bool {
        let row = app.staticTexts[displayName]
        guard scrollUntilHittable(row, in: app) else {
            attach("row-not-found-\(displayName)")
            XCTFail("Account row \(displayName) was not found")
            return false
        }

        row.press(forDuration: 1.6)
        sleep(2)

        let menuItem = app.buttons["move-to-group-menu"]
        guard menuItem.waitForExistence(timeout: 5), menuItem.isHittable else {
            dumpButtons(app, "context-menu")
            attach("move-menu-not-found")
            XCTFail("Move to group menu item was not found")
            return false
        }

        menuItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard app.staticTexts["نقل إلى مجموعة"].waitForExistence(timeout: 8) else {
            dumpButtons(app, "move-sheet")
            attach("move-sheet-not-found")
            XCTFail("Move sheet was not presented")
            return false
        }
        return true
    }

    func testGroupsCapacityRenameCreateAndMove() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screen=accounts"]
        app.launch()

        // ١) ترحيل البيانات القديمة: ١٠ حسابات إلى مجموعتين ٧ + ٣.
        let groupOne = app.staticTexts["المجموعة 1"]
        XCTAssertTrue(groupOne.waitForExistence(timeout: 25), "Migrated group 1 was not shown")
        attach("01-migrated-group-1")

        let groupTwo = app.staticTexts["المجموعة 2"]
        XCTAssertTrue(
            scrollUntilHittable(groupTwo, in: app, maxSwipes: 20),
            "Migrated group 2 was not shown"
        )
        XCTAssertTrue(
            waitForCleanedText("3 من 7", in: app),
            "Group 2 should contain 3 of 7 accounts"
        )
        attach("02-migrated-group-2")

        // ٢) السعة: الحساب الثامن يجب ألا يستطيع الانتقال إلى مجموعة ممتلئة.
        XCTAssertTrue(openMoveSheet(for: "حساب 08", app: app))
        let fullGroup = app.buttons["move-group-1"]
        XCTAssertTrue(fullGroup.waitForExistence(timeout: 5), "Full group card was not found")
        XCTAssertFalse(fullGroup.isEnabled, "A full group must not accept an 8th account")
        XCTAssertTrue(app.staticTexts["ممتلئة"].exists, "Full group should be labelled as full")
        attach("03-full-group")
        app.buttons["move-sheet-close"].tap()
        XCTAssertTrue(app.staticTexts["نقل إلى مجموعة"].waitForNonExistence(timeout: 5))

        // ٣) إعادة تسمية المجموعة الثانية من قائمة الحسابات.
        scrollToTop(app)
        let renameGroupTwo = app.buttons["rename-group-2"]
        XCTAssertTrue(
            scrollUntilHittable(renameGroupTwo, in: app, maxSwipes: 20),
            "Rename button for group 2 was not found"
        )
        renameGroupTwo.tap()
        replaceText(in: app.textFields["group-name-field"], with: "مفضلة")
        app.buttons["group-name-save"].tap()
        XCTAssertTrue(
            app.staticTexts["مفضلة"].waitForExistence(timeout: 8),
            "Group 2 should show its new name"
        )
        attach("04-renamed-group-2")

        // ٤) إنشاء مجموعة فارغة من شريط إدارة المجموعات.
        scrollToTop(app)
        let createGroup = app.buttons["create-group"]
        XCTAssertTrue(createGroup.waitForExistence(timeout: 5), "Create group button was not found")
        createGroup.tap()
        replaceText(in: app.textFields["group-name-field"], with: "يومية")
        app.buttons["group-name-save"].tap()

        let emptyGroupTitle = app.staticTexts["يومية"]
        XCTAssertTrue(
            scrollUntilHittable(emptyGroupTitle, in: app, maxSwipes: 20),
            "New empty group was not shown"
        )
        XCTAssertTrue(
            waitForCleanedText("0 من 7", in: app),
            "New group should start empty"
        )
        attach("05-created-empty-group")

        // ٥) نقل الحساب الأول إلى أول موضع في المجموعة الثانية.
        scrollToTop(app)
        XCTAssertTrue(openMoveSheet(for: "حساب 01", app: app))
        let moveGroupTwo = app.buttons["move-group-2"]
        XCTAssertTrue(moveGroupTwo.waitForExistence(timeout: 5), "Group 2 card was not found")
        XCTAssertTrue(moveGroupTwo.isEnabled, "Group 2 should accept another account")
        moveGroupTwo.tap()

        let moveToast = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "إلى مفضلة"))
            .firstMatch
        XCTAssertTrue(moveToast.waitForExistence(timeout: 4), "Move confirmation toast was not shown")
        attach("06-moved-to-group-2")

        guard let positionText = scrollUntilCleanedText(
            containing: "الموضع 1 من 4",
            in: app,
            maxSwipes: 24
        ) else {
            attach("position-not-found")
            XCTFail("Moved account should be first in group 2")
            return
        }
        XCTAssertTrue(
            positionText.contains("مفضلة"),
            "Position bar should name the group, got: \(positionText)"
        )
        attach("07-first-position")

        // ٦) الضبط الدقيق داخل المجموعة الحالية.
        XCTAssertTrue(openMoveSheet(for: "حساب 10", app: app))
        let fineTop = app.buttons["fine-top"]
        XCTAssertTrue(fineTop.waitForExistence(timeout: 5), "Fine tuning controls were not found")
        XCTAssertTrue(fineTop.isEnabled, "Moving to top should be enabled for the last account")
        fineTop.tap()
        XCTAssertTrue(
            waitForCleanedText("الموضع 1 من 4", in: app, timeout: 4),
            "Moving to group top did not update the position"
        )

        let fineDown = app.buttons["fine-down"]
        XCTAssertTrue(fineDown.isEnabled, "Moving one step down should be enabled")
        fineDown.tap()
        XCTAssertTrue(
            waitForCleanedText("الموضع 2 من 4", in: app, timeout: 4),
            "One-step move did not update the position"
        )
        attach("08-fine-tuning")
        app.buttons["move-sheet-close"].tap()
        XCTAssertTrue(app.staticTexts["نقل إلى مجموعة"].waitForNonExistence(timeout: 5))

        // ٧) إنشاء مجموعة من شاشة النقل تنقل الحساب وتغلق الشاشة.
        scrollToTop(app)
        XCTAssertTrue(openMoveSheet(for: "حساب 01", app: app))
        let createInSheet = app.buttons["create-group-sheet"]
        XCTAssertTrue(createInSheet.waitForExistence(timeout: 5), "Create group in move sheet was not found")
        createInSheet.tap()
        replaceText(in: app.textFields["group-name-field"], with: "سريعة")
        app.buttons["group-name-save"].tap()

        let createToast = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "تم إنشاء"))
            .firstMatch
        XCTAssertTrue(createToast.waitForExistence(timeout: 5), "Create and move confirmation was not shown")
        XCTAssertTrue(
            app.staticTexts["نقل إلى مجموعة"].waitForNonExistence(timeout: 6),
            "Move sheet should close after creating a group and moving the account"
        )
        attach("09-created-and-moved")

        let newGroup = app.staticTexts["سريعة"]
        XCTAssertTrue(
            scrollUntilHittable(newGroup, in: app, maxSwipes: 24),
            "New group was not shown after creating it from the move sheet"
        )
        XCTAssertTrue(
            waitForCleanedText("1 من 7", in: app),
            "New group should contain the moved account"
        )
        attach("10-final-groups")
    }
}
