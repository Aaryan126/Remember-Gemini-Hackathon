import XCTest

/// Simulator-only visual tour. Drafts are cancelled, no AI question is sent, and
/// only a synthetic note is saved. Never run this fixture on a personal device.
final class AppearanceReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testLightSurfaces() throws { try review("light") }
    @MainActor func testDarkSurfaces() throws { try review("dark") }

    /// Read-only tour, safe for an existing personal library. Launch arguments
    /// override appearance for this process without writing the saved preference.
    @MainActor func testExistingLightLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-remember.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 15))
        capture("Existing memories", "light", app)
        let memory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-memory-")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 10))
        memory.tap()
        XCTAssertTrue(app.buttons["Memory details"].waitForExistence(timeout: 5))
        capture("Existing memory detail", "light", app)
        app.buttons["Memory details"].tap()
        XCTAssertTrue(app.navigationBars["Memory Details"].waitForExistence(timeout: 5))
        capture("Existing memory information", "light", app)
        app.buttons["Done"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("Existing memory editor", "light", app)
        app.buttons["Cancel"].tap()
        back(app)
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Graph"].tap()
        let nodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graph-node-"))
        XCTAssertTrue(nodes.firstMatch.waitForExistence(timeout: 15))
        capture("Existing map", "light", app)
        let canvas = app.descendants(matching: .any)["memory-map-canvas"].firstMatch
        let candidate = try XCTUnwrap(nodes.allElementsBoundByIndex.filter {
            $0.isHittable && canvas.frame.insetBy(dx: 1, dy: 1).contains($0.frame)
        }.max { $0.frame.width < $1.frame.width })
        app.buttons[candidate.identifier].tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        capture("Existing river", "light", app)
        app.swipeUp()
        capture("Existing river media", "light", app)
        back(app)
        picker.buttons["Timeline"].tap()
        capture("Existing timeline", "light", app)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        capture("Existing settings", "light", app)
        app.buttons["AI Help"].tap()
        XCTAssertTrue(app.staticTexts["Ask your memories"].waitForExistence(timeout: 5))
        capture("Existing assistant", "light", app)
        app.buttons["Close"].tap()
        app.staticTexts["Privacy & AI"].tap()
        XCTAssertTrue(app.navigationBars["Privacy & AI"].waitForExistence(timeout: 5))
        capture("Existing privacy", "light", app)
        app.terminate()
    }

    @MainActor private func review(_ appearance: String) throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual fixture is simulator-only.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-remember.appearance", appearance, "-remember.project.cloudAssistance", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 15))
        capture("Memories", appearance, app)
        app.buttons["Add a memory"].tap()
        capture("Capture dial", appearance, app)
        app.buttons["New Note"].tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        let title = "A quieter place for ideas \(appearance)"
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText(title)
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("Keep the original thought. Connect it to what matters.\n\nA short note for reviewing reading, writing, and the River.")
        capture("Note capture", appearance, app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 15))
        let note = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "library-memory-", title)).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15))
        note.tap()
        XCTAssertTrue(app.buttons["Memory details"].waitForExistence(timeout: 5))
        capture("Note detail", appearance, app)
        app.buttons["Memory details"].tap()
        XCTAssertTrue(app.navigationBars["Memory Details"].waitForExistence(timeout: 5))
        capture("Memory information", appearance, app)
        app.buttons["Done"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("Note editor", appearance, app)
        app.buttons["Cancel"].tap()
        back(app)

        app.buttons["AI Help"].tap()
        XCTAssertTrue(app.staticTexts["Ask your memories"].waitForExistence(timeout: 5))
        capture("Assistant", appearance, app)
        app.buttons["Speak a question"].tap()
        XCTAssertTrue(app.navigationBars["Speak a Question"].waitForExistence(timeout: 5))
        capture("Assistant voice", appearance, app)
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()

        app.buttons["Add a memory"].tap()
        let photo = app.buttons["Choose Photo or Video"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        photo.press(forDuration: 0.1, thenDragTo: photo.withOffset(CGVector(dx: 20, dy: -75)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["Record Voice"].waitForExistence(timeout: 5))
        app.buttons["Record Voice"].tap()
        XCTAssertTrue(app.navigationBars["Voice Memory"].waitForExistence(timeout: 5))
        capture("Voice capture", appearance, app)
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Timeline"].tap()
        capture("Timeline", appearance, app)
        picker.buttons["Graph"].tap()
        let nodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graph-node-"))
        XCTAssertTrue(nodes.firstMatch.waitForExistence(timeout: 15))
        capture("Map", appearance, app)
        let canvas = app.descendants(matching: .any)["memory-map-canvas"].firstMatch
        let candidate = try XCTUnwrap(nodes.allElementsBoundByIndex.filter {
            $0.isHittable && canvas.frame.insetBy(dx: 1, dy: 1).contains($0.frame)
        }.max { $0.frame.width < $1.frame.width })
        let node = app.buttons[candidate.identifier]
        node.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["map-focus-preview"].waitForExistence(timeout: 5))
        capture("Map focus", appearance, app)
        app.buttons["map-focus-preview"].tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        capture("River", appearance, app)
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-source-")).firstMatch
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        XCTAssertTrue(app.navigationBars["Memory"].waitForExistence(timeout: 5))
        capture("River memory and evidence", appearance, app)
        back(app)
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        back(app)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        capture("Settings", appearance, app)
        app.staticTexts["Archive"].tap()
        XCTAssertTrue(app.navigationBars["Archive"].waitForExistence(timeout: 5))
        capture("Archive", appearance, app)
        back(app)
        app.staticTexts["Collections & Tags"].tap()
        XCTAssertTrue(app.navigationBars["Collections & Tags"].waitForExistence(timeout: 5))
        capture("Collections and tags", appearance, app)
        app.buttons["New Collection"].tap()
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 5))
        capture("Collection editor", appearance, app)
        app.buttons["Cancel"].tap()
        back(app)
        app.staticTexts["Privacy & AI"].tap()
        XCTAssertTrue(app.navigationBars["Privacy & AI"].waitForExistence(timeout: 5))
        capture("Privacy", appearance, app)
        app.swipeUp()
        capture("Privacy activity", appearance, app)
        back(app)
        app.tabBars.buttons["Memories"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("zxqvplmn874209zz")
        XCTAssertTrue(app.staticTexts["No matching memories"].waitForExistence(timeout: 10))
        capture("Empty search", appearance, app)
        app.terminate()
        #endif
    }

    @MainActor private func back(_ app: XCUIApplication) {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    @MainActor private func capture(_ name: String, _ appearance: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(appearance) — \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
