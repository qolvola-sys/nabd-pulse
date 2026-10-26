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

        let moveItem = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "نقل إلى مجموعة"))
            .firstMatch

        guard moveItem.waitForExistence(timeout: 8) else {
            print("MENU_BUTTONS_START")
            for button in app.buttons.allElementsBoundByIndex {
                print("BUTTON: \(button.label)")
            }
            print("MENU_BUTTONS_END")
            attach("move-item-not-found")
            XCTFail("Move to group menu item was not found")
            return
        }

        moveItem.tap()
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

        groupTwo.tap()
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
