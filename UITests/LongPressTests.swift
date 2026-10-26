import XCTest

final class LongPressTests: XCTestCase {
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

    /// نستهدف عنصر القائمة نفسه بمعرّفه، لأن النص وحده يطابق أيضاً
    /// زر شريط الترتيب الموجود خلف القائمة بنفس التسمية.
    private func moveMenuItem(in app: XCUIApplication) -> XCUIElement? {
        let identified = app.buttons["move-to-group-menu"]
        if identified.waitForExistence(timeout: 5), identified.isHittable {
            return identified
        }

        // احتياط: عنصر القائمة يظهر قرب الحساب، بينما شريط الترتيب أسفل الشاشة.
        let candidates = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "نقل إلى مجموعة"))
            .allElementsBoundByIndex
            .filter { $0.identifier != "move-to-group-bar" && $0.isHittable }

        return candidates.min(by: { $0.frame.minY < $1.frame.minY })
    }

    func testMoveAccountToGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screen=accounts"]
        app.launch()

        let row = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "نورة"))
            .firstMatch

        guard row.waitForExistence(timeout: 25) else {
            print("VISIBLE_TEXTS_START")
            for text in app.staticTexts.allElementsBoundByIndex {
                print("TEXT: \(text.label)")
            }
            print("VISIBLE_TEXTS_END")
            attach("account-not-found")
            XCTFail("Seeded account row was not found")
            return
        }

        row.press(forDuration: 1.6)
        sleep(2)
        attach("context-menu")

        guard let moveItem = moveMenuItem(in: app) else {
            print("MENU_BUTTONS_START")
            for button in app.buttons.allElementsBoundByIndex {
                print("BUTTON: \(button.label) id=\(button.identifier) frame=\(button.frame)")
            }
            print("MENU_BUTTONS_END")
            attach("move-item-not-found")
            XCTFail("Move to group menu item was not found")
            return
        }

        moveItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        attach("group-sheet")

        let groupTwo = app.buttons["move-group-2"]
        guard groupTwo.waitForExistence(timeout: 8) else {
            print("SHEET_BUTTONS_START")
            for button in app.buttons.allElementsBoundByIndex {
                print("BUTTON: \(button.label) id=\(button.identifier)")
            }
            print("SHEET_BUTTONS_END")
            attach("group-sheet-not-found")
            XCTFail("Group 2 card was not found")
            return
        }

        groupTwo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        attach("after-move")

        let toast = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "إلى المجموعة ٢"))
            .firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "Move confirmation toast was not shown")

        for _ in 0..<3 {
            app.swipeUp()
        }
        sleep(1)
        let position = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "الموضع ٤ من ٤"))
            .firstMatch
        XCTAssertTrue(position.waitForExistence(timeout: 8), "Account position did not update to group 2")
        attach("group-two-position")
    }
}
