import XCTest

/// Drives the real app through every screen. The goal is "nothing crashes or gets stuck",
/// plus a few checks that the numbers on screen are right.
final class CotizaUITests: XCTestCase {
    private static let englishJob = "Paint two bedrooms at 350 each, install 3 doors at 120 dollars each, and 8 hours of labor at 45 an hour. Client Maria Lopez."
    private static let spanishJob = "Pintar dos recámaras a 350 cada una y 8 horas de mano de obra a 45 la hora. Cliente María López."

    override func setUp() async throws {
        continueAfterFailure = false
    }

    @MainActor private func launch(language: String = "en", locale: String = "en_US", _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CotizaResetState", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        app.launch()
        return app
    }

    @MainActor private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("Not found: \(element)\n\(XCUIApplication().debugDescription)", file: file, line: line)
        }
    }

    /// Lists only build rows on screen, so a row below the fold has to be scrolled to first.
    /// `topmost` scrolls the list in the sheet on top (the last one in the tree) instead of the screen under it.
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, topmost: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let lists = app.collectionViews
        let list = topmost ? lists.element(boundBy: max(lists.count - 1, 0)) : lists.firstMatch
        for _ in 0..<6 where !element.waitForExistence(timeout: 1) || !element.isHittable {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists, "Not found: \(element)", file: file, line: line)
    }

    @MainActor private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.collectionViews.firstMatch.swipeDown(velocity: .fast) }
    }

    @MainActor private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        if XCTWaiter.wait(for: [gone], timeout: timeout) != .completed {
            XCTFail("Still on screen: \(element)", file: file, line: line)
        }
    }

    @MainActor private func tapMenuItem(_ app: XCUIApplication, _ title: String) {
        app.buttons["More"].tap()
        let item = app.buttons[title].firstMatch
        waitFor(item)
        item.tap()
    }

    @MainActor private func goBack(_ app: XCUIApplication) {
        // On this device the system back button sits in a side toolbar rather than a navigation bar.
        let side = app.buttons["BackButton"]
        let back = side.waitForExistence(timeout: 3) ? side : app.navigationBars.buttons.element(boundBy: 0)
        waitFor(back)
        back.tap()
    }

    @MainActor private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        waitFor(close)
        close.tap()
        waitForGone(close)
    }

    // MARK: - Free user, end to end

    @MainActor func testFreeUserJourney() {
        let app = launch(["-CotizaDemoTranscript", Self.englishJob])

        // Onboarding
        app.buttons["Get started"].tap()
        let name = app.textFields["Business name"]
        waitFor(name)
        name.tap()
        name.typeText("Lopez Painting")
        // The on-screen keyboard (when the simulator shows one) covers the trade grid; put it away first.
        if app.keyboards.count > 0 { app.keyboards.buttons["return"].firstMatch.tap() }
        scrollTo(app.buttons["Painting"], in: app)
        app.buttons["Painting"].tap()
        app.buttons["onboarding.continue"].tap()

        // The trial is offered once, right after setup.
        waitFor(app.staticTexts["Cotiza Pro"])
        closeSheet(app)

        // First estimate from the job description
        app.buttons["New estimate"].tap()
        waitFor(app.buttons["Create estimate"])
        app.buttons["Create estimate"].tap()
        waitFor(app.staticTexts["Paint bedrooms"], timeout: 15)
        XCTAssertTrue(app.staticTexts["Install doors"].exists)
        XCTAssertTrue(app.staticTexts["Labor"].exists)
        XCTAssertTrue(app.staticTexts["Maria Lopez"].exists)
        scrollTo(app.staticTexts["$1,420.00"], in: app) // 2×350 + 3×120 + 8×45
        scrollToTop(app)

        // Delete an item from its sheet
        app.staticTexts["Install doors"].tap()
        waitFor(app.buttons["Done"].firstMatch)
        scrollTo(app.buttons["Delete item"], in: app, topmost: true)
        app.buttons["Delete item"].tap()
        waitForGone(app.staticTexts["Install doors"])
        scrollTo(app.staticTexts["$1,060.00"], in: app)
        scrollToTop(app)

        // An item added and left blank is dropped
        app.buttons["Add item"].tap()
        waitFor(app.buttons["Done"].firstMatch)
        app.buttons["Done"].firstMatch.tap()
        waitForGone(app.staticTexts["New item"])

        // PDF preview
        app.buttons["Preview and send"].tap()
        waitFor(app.buttons["Send to client"], timeout: 10)
        closeSheet(app)

        // Invoices are a Pro feature
        tapMenuItem(app, "Convert to invoice")
        waitFor(app.staticTexts["Cotiza Pro"])
        closeSheet(app)

        // Duplicate, then delete the copy
        tapMenuItem(app, "Duplicate")
        waitFor(app.staticTexts["E-1002"])
        tapMenuItem(app, "Delete")
        let confirm = app.buttons["Delete"].firstMatch
        waitFor(confirm)
        confirm.tap()
        // The copy was opened from E-1001, so deleting it returns there.
        waitFor(app.navigationBars["E-1001"])
        goBack(app)
        waitFor(app.buttons["New estimate"])
        XCTAssertTrue(app.staticTexts["E-1001"].exists)
        XCTAssertFalse(app.staticTexts["E-1002"].exists, "The deleted copy is still listed")

        // Third and last free estimate, blank
        XCTAssertTrue(app.staticTexts["Free plan: 1 of 3 estimates left"].exists)
        app.buttons["New estimate"].tap()
        waitFor(app.buttons["Start with a blank estimate"])
        app.buttons["Start with a blank estimate"].tap()
        waitFor(app.staticTexts["E-1003"])
        goBack(app)

        // Limit reached: the paywall instead of the recorder
        waitFor(app.staticTexts["Free plan: 0 of 3 estimates left"])
        app.buttons["New estimate"].tap()
        waitFor(app.staticTexts["Cotiza Pro"])
        XCTAssertFalse(app.buttons["Create estimate"].exists)
        closeSheet(app)

        // Settings, clients, prices
        app.buttons["Settings"].tap()
        waitFor(app.buttons["Choose logo"])
        app.buttons["Choose logo"].tap()
        waitFor(app.staticTexts["Cotiza Pro"])
        closeSheet(app)
        let clients = app.buttons["Clients"]
        scrollTo(clients, in: app, topmost: true)
        clients.tap()
        waitFor(app.staticTexts["Maria Lopez"])
        goBack(app)
        scrollTo(app.buttons["My prices"], in: app, topmost: true)
        app.buttons["My prices"].tap()
        waitFor(app.staticTexts["Paint bedrooms"], timeout: 5)
        goBack(app)
        app.buttons["Done"].firstMatch.tap()
        waitFor(app.buttons["New estimate"])
    }

    // MARK: - Pro user

    @MainActor func testProUserInvoiceFlow() {
        let app = launch(["-CotizaDemoData", "YES", "-CotizaForcePro", "YES", "-CotizaDemoTranscript", Self.englishJob])
        waitFor(app.buttons["New estimate"])
        XCTAssertFalse(app.buttons["Go Pro"].exists)

        app.buttons["New estimate"].tap()
        app.buttons["Create estimate"].tap()
        waitFor(app.staticTexts["Paint bedrooms"], timeout: 15)

        tapMenuItem(app, "Convert to invoice")
        waitFor(app.staticTexts["INV-1001"])
        tapMenuItem(app, "Mark as paid")
        waitFor(app.staticTexts["Paid"].firstMatch)

        app.buttons["Preview and send"].tap()
        waitFor(app.buttons["Send to client"], timeout: 10)
        closeSheet(app)

        goBack(app)
        goBack(app)
        waitFor(app.staticTexts["INV-1001"])
        XCTAssertTrue(app.staticTexts["E-1001"].exists)
    }

    // MARK: - Spanish UI, Spanish job (exercises the translation fallback)

    @MainActor func testSpanishJob() {
        let app = launch(language: "es", locale: "es_US", ["-CotizaDemoData", "YES", "-CotizaDemoTranscript", Self.spanishJob])
        waitFor(app.buttons["Nueva cotización"])
        app.buttons["Nueva cotización"].tap()
        app.buttons["Crear cotización"].tap()
        // The demo profile writes documents in English. Where on-device translation is missing
        // (as in the simulator) the items keep the spoken wording; either way an estimate opens.
        let opened = app.staticTexts["E-1001"]
        waitFor(opened, timeout: 30)
        // 2×350 taxed at the demo profile's 8.25%, plus 8×45 labor (not taxed).
        waitFor(app.staticTexts["Pintar recámaras"])
        waitFor(app.staticTexts["Mano de obra"])
        // The total row is below the fold; the tax row proves the taxable split is right.
        scrollTo(app.staticTexts["Impuesto, $57.75"], in: app)
    }
}
