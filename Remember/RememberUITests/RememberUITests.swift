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
    func testRadialCaptureMenuExposesEveryCaptureAction() throws {
        let app = XCUIApplication()
        app.launch()

        let addMemory = app.buttons["Add a memory"]
        XCTAssertTrue(addMemory.waitForExistence(timeout: 3))
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(addMemory.frame.midX, windowFrame.midX)
        XCTAssertGreaterThan(addMemory.frame.midY, windowFrame.midY)
        addMemory.tap()

        let actionNames = ["New Note", "Take Photo", "Choose Photo", "Import File"]
        let actionButtons = actionNames.map { app.buttons[$0] }
        for (action, button) in zip(actionNames, actionButtons) {
            XCTAssertTrue(button.waitForExistence(timeout: 2), "Missing radial action: \(action)")
        }
        for firstIndex in actionButtons.indices {
            for secondIndex in actionButtons.indices where secondIndex > firstIndex {
                let firstFrame = actionButtons[firstIndex].frame
                let secondFrame = actionButtons[secondIndex].frame
                let horizontalDistance = firstFrame.midX - secondFrame.midX
                let verticalDistance = firstFrame.midY - secondFrame.midY
                let centerDistance = sqrt(
                    horizontalDistance * horizontalDistance
                        + verticalDistance * verticalDistance
                )
                XCTAssertGreaterThanOrEqual(
                    centerDistance,
                    44,
                    "Radial actions overlap: \(actionNames[firstIndex]) and \(actionNames[secondIndex])"
                )
            }
        }

        let captureDial = app.otherElements["Capture dial"]
        XCTAssertTrue(captureDial.exists)
        app.buttons["Choose Photo"].swipeUp()
        XCTAssertTrue(app.buttons["Record Voice"].waitForExistence(timeout: 2))
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
        XCTAssertTrue(aiHelp.waitForExistence(timeout: 3))

        XCTAssertFalse(app.buttons["All types"].exists)
        XCTAssertFalse(app.buttons["Any time"].exists)

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Collections & Tags"].exists)
        XCTAssertTrue(app.staticTexts["Privacy & AI"].exists)

        tabBar.buttons["Memories"].tap()
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
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
