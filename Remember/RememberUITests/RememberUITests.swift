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
    func testProjectCaptureRiverHistoryAndViewPreference() throws {
        let app = XCUIApplication()
        app.launch()
        let title = "Provenance UI \(UUID().uuidString.prefix(6))"
        app.tabBars.buttons["Memories"].tap()
        app.buttons["Add a memory"].tap()
        app.buttons["New Note"].tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(title)
        app.buttons["Save"].tap()
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", title)).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        let history = app.switches["Travel through time"]
        XCTAssertTrue(history.exists)
        history.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.sliders["History date"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Project river and historical comparison"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        picker.buttons["Graph"].tap()
        XCTAssertTrue(app.buttons["Zoom in"].exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Project"].tap()
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        let graphImage = XCTAttachment(screenshot: app.screenshot())
        graphImage.name = "Project graph"
        graphImage.lifetime = .keepAlways
        add(graphImage)
        picker.buttons["Timeline"].tap()
        chip.tap()
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "project-source-", title)).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        let archive = app.buttons["Archive memory"]
        for _ in 0..<5 where !archive.isHittable { app.swipeUp() }
        XCTAssertTrue(archive.isHittable)
        archive.tap()
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Archive"].firstMatch.tap()
        let restore = app.buttons["Restore \(title)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
