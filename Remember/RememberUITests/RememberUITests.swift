//
//  RememberUITests.swift
//  RememberUITests
//
//  Created by Aaryan Kandiah on 21/8/26.
//

import XCTest

final class RememberUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testThreeSurfaceNavigationAndTemporaryAI() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Memories"].waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.buttons["Project"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
        XCTAssertEqual(tabBar.buttons.count, 3)

        let aiHelp = app.buttons["AI Help"]
        XCTAssertTrue(aiHelp.exists)
        aiHelp.tap()

        XCTAssertTrue(app.navigationBars["AI Help"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ask your memories"].exists)
        let composer = app.textFields["Ask about what you saved"]
        composer.tap()
        composer.typeText("temporary draft")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Remember"].waitForExistence(timeout: 3))

        aiHelp.tap()
        XCTAssertTrue(app.navigationBars["AI Help"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Ask about what you saved"].value as? String, "Ask about what you saved")
        app.buttons["Close"].tap()

        let addMemory = app.buttons["Add a memory"]
        XCTAssertTrue(addMemory.exists)
        addMemory.tap()
        XCTAssertTrue(app.buttons["New Note"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        XCTAssertTrue(app.buttons["Choose Photo"].exists)
        XCTAssertTrue(app.buttons["Import File"].exists)
        XCTAssertTrue(app.buttons["Save Link"].exists)
        XCTAssertTrue(app.buttons["Record Voice"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
