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

    /// Simulator only: seed Photos with the documented synthetic movie before running.
    @MainActor
    func testPhotosVideoImportAndInlineRiverPlayback() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Imports a synthetic video; never run on a personal phone.")
        #else
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add a memory"].tap()
        app.buttons["Choose Photo or Video"].tap()
        let video = app.images.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "PXGGridLayout-Info", "Video,")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 8), "Seed the simulator Photos library with the synthetic movie.")
        // Photos exposes thumbnails as images with no activation point; tap the resolved frame.
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Add Video"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Play video"].exists)
        let title = "River movie \(UUID().uuidString.prefix(6))"
        let caption = app.textFields["What should Remember know about this?"]
        // A multiline SwiftUI field is exposed as a text view on some OS versions.
        let input = caption.exists ? caption : app.textViews["What should Remember know about this?"]
        input.tap()
        input.typeText(title)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Video"].waitForNonExistence(timeout: 15), "Saving the selected video must complete.")
        XCTAssertTrue(app.tabBars.buttons["Project"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Timeline"].tap()
        let topic = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", title)).firstMatch
        revealTimelineThread(topic, title: title, in: app)
        topic.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sources"].exists)
        let play = app.buttons["Play video"].firstMatch
        for _ in 0..<6 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Video embedded in chronological river"
        before.lifetime = .keepAlways
        add(before)
        play.tap()
        let player = app.otherElements.matching(NSPredicate(format: "label == %@", "Saved video player")).firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let playPause = app.buttons["Play/Pause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        let position = app.sliders.matching(NSPredicate(format: "identifier == %@", "Current position")).firstMatch
        XCTAssertTrue(position.exists)
        let initialPosition = position.value as? String
        XCTAssertNotNil(initialPosition)
        if playPause.label == "Play" { playPause.tap() }
        let advances = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard position.exists, let value = position.value as? String else { return false }
            return value != initialPosition
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advances], timeout: 3), .completed)
        XCTAssertTrue(app.navigationBars["Thread history"].exists, "Playback must stay in the river.")
        let playing = XCTAttachment(screenshot: app.screenshot())
        playing.name = "Native inline video playback"
        playing.lifetime = .keepAlways
        add(playing)
        if playPause.exists && playPause.label == "Pause" { playPause.tap() }
        app.navigationBars["Thread history"].buttons.element(boundBy: 0).tap()
        #endif
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

        let actionNames = ["New Note", "Take Photo", "Choose Photo or Video", "Import File"]
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
        let dialImage = XCTAttachment(screenshot: app.screenshot())
        dialImage.name = "Capture dial background separation"
        dialImage.lifetime = .keepAlways
        add(dialImage)
        let photo = app.buttons["Choose Photo or Video"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        photo.press(forDuration: 0.1, thenDragTo: photo.withOffset(CGVector(dx: 20, dy: -75)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["Record Voice"].waitForExistence(timeout: 2))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["Close add menu"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add a memory"].exists)
    }

    @MainActor
    func testDialFollowsDragInBothDirections() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add a memory"].tap()
        let note = app.buttons["New Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        let original = note.frame
        let start = note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -45, dy: 8))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let draggedImage = XCTAttachment(screenshot: app.screenshot())
        draggedImage.name = "Dial after leftward drag"
        draggedImage.lifetime = .keepAlways
        add(draggedImage)
        XCTAssertLessThan(note.frame.midX, original.midX - 20, "The top action must follow a leftward drag")
        let moved = note.frame
        let reverse = note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        reverse.press(forDuration: 0.1, thenDragTo: reverse.withOffset(CGVector(dx: 35, dy: -5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertGreaterThan(note.frame.midX, moved.midX + 15, "Reversing the drag must move the action back right")
        app.buttons["Close add menu"].tap()
        XCTAssertTrue(app.buttons["Add a memory"].exists)
        XCTAssertTrue(app.buttons["New Note"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(
            XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
            "Closing the dial must not request device permissions"
        )
        app.tabBars.buttons["Project"].tap()
        XCTAssertTrue(app.segmentedControls["Project view"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Memories"].tap()
    }

    @MainActor
    func testMemoryMapDragAndSourceNavigation() throws {
        try checkMemoryMap(appearance: "light")
    }

    @MainActor
    func testDialFlingCanBeDismissedAndReopened() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add a memory"].tap()
        let start = app.buttons["Choose Photo or Video"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 20, dy: -100)), withVelocity: .fast, thenHoldForDuration: 0)
        app.buttons["Close add menu"].tap()
        XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 3))
        app.buttons["Add a memory"].tap()
        for title in ["New Note", "Take Photo", "Choose Photo or Video", "Import File"] {
            XCTAssertTrue(app.buttons[title].exists)
        }
        app.buttons["Close add menu"].tap()
        app.tabBars.buttons["Project"].tap()
        XCTAssertTrue(app.segmentedControls["Project view"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Memories"].tap()
    }

    /// Requires an existing capture; does not change it.
    @MainActor
    func testCaptureButtonIsHiddenOnMemoryDetail() throws {
        let app = XCUIApplication()
        app.launch()
        let memory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library-memory-")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in memory.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        memory.tap()
        XCTAssertTrue(app.buttons["Memory details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add a memory"].exists)
        XCTAssertFalse(app.buttons["Close add menu"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Memory detail without capture button"
        detail.lifetime = .keepAlways
        add(detail)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapUncoveredBack(in app: XCUIApplication, title: String) {
        // A system banner can cover an otherwise-hittable Back button on a
        // personal device. Wait; never open or interact with its contents.
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .descendants(matching: .any).matching(identifier: "NotificationShortLookView").firstMatch
        XCTAssertTrue(banner.waitForNonExistence(timeout: 20), "A notification is covering the navigation bar.")
        app.navigationBars[title].buttons["BackButton"].tap()
    }

    @MainActor
    private func waitForMapCenter(_ node: XCUIElement, at frame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        // Display-link frames aren't tracked by XCTest's implicit-animation idle wait.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(node.frame.midX - frame.midX) < 1 && abs(node.frame.midY - frame.midY) < 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed, file: file, line: line)
    }

    /// Safe for a connected phone: does not seed, edit, archive, or restore memories.
    @MainActor
    func testExistingMapFocusHoldDragAndReturn() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let previousView = picker.buttons["Timeline"].isSelected ? "Timeline" : "Graph"
        picker.buttons["Graph"].tap()
        app.buttons["Recenter map"].tap()
        let node = try visibleMapNode(in: app)
        let original = node.frame
        let canvasFrame = app.descendants(matching: .any)["memory-map-canvas"].frame
        let neighbor = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graph-node-"))
            .allElementsBoundByIndex.first { $0.identifier != node.identifier && canvasFrame.contains($0.frame) }
        let neighborID = neighbor?.identifier
        let neighborFrame = neighbor?.frame
        node.press(forDuration: 0.7)
        XCTAssertFalse(app.navigationBars["Thread history"].exists, "A hold highlights; only a quick tap enters the River.")
        XCTAssertTrue(node.isSelected)
        XCTAssertGreaterThan(node.frame.width, original.width)
        XCTAssertEqual(node.frame.midX, original.midX, accuracy: 1)
        XCTAssertEqual(node.frame.midY, original.midY, accuracy: 1)
        if let neighborID, let neighborFrame {
            XCTAssertEqual(app.buttons[neighborID].frame.midX, neighborFrame.midX, accuracy: 1)
            XCTAssertEqual(app.buttons[neighborID].frame.midY, neighborFrame.midY, accuracy: 1)
        }
        XCTAssertTrue(app.buttons["Clear focus"].exists)
        XCTAssertTrue(app.buttons["map-focus-preview"].waitForExistence(timeout: 3))
        let held = XCTAttachment(screenshot: app.screenshot())
        held.name = "Memory map held focus"
        held.lifetime = .keepAlways
        add(held)

        let center = node.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 35, dy: 18)), withVelocity: .slow, thenHoldForDuration: 0.2)
        waitForMapCenter(node, at: original)
        XCTAssertFalse(app.navigationBars["Thread history"].exists)
        XCTAssertTrue(node.isSelected)
        XCTAssertEqual(node.frame.midX, original.midX, accuracy: 2, "A short drag must settle back on the same center node.")
        XCTAssertEqual(node.frame.midY, original.midY, accuracy: 2)
        if let neighborID, let neighborFrame {
            let movedNeighbor = app.buttons[neighborID].frame
            XCTAssertEqual(movedNeighbor.midX - neighborFrame.midX, node.frame.midX - original.midX, accuracy: 2,
                           "Dragging must translate all grid slots by the same amount.")
            XCTAssertEqual(movedNeighbor.midY - neighborFrame.midY, node.frame.midY - original.midY, accuracy: 2)
        }
        app.buttons["Clear focus"].tap()
        XCTAssertFalse(node.isSelected)
        XCTAssertFalse(app.buttons["map-focus-preview"].exists)
        app.buttons["Recenter map"].tap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(node.frame.width - original.width) < 2 && abs(node.frame.midX - original.midX) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 3), .completed)

        if let neighborID, let neighborFrame {
            let nextNode = app.buttons[neighborID]
            let delta = CGVector(dx: (original.midX - neighborFrame.midX) * 0.72,
                                 dy: (original.midY - neighborFrame.midY) * 0.72)
            let lensStart = node.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            lensStart.press(forDuration: 0.1, thenDragTo: lensStart.withOffset(delta),
                            withVelocity: .slow, thenHoldForDuration: 0.2)
            waitForMapCenter(nextNode, at: original)
            XCTAssertEqual(nextNode.frame.midX, original.midX, accuracy: 2, "Release must finish centering the nearest occupied slot.")
            XCTAssertEqual(nextNode.frame.midY, original.midY, accuracy: 2)
            XCTAssertTrue(nextNode.isSelected)
            XCTAssertFalse(app.buttons["map-focus-preview"].exists, "Snapping must not open a preview or River.")
            XCTAssertLessThan(node.frame.width, original.width * 0.96)
            XCTAssertEqual(node.frame.midX - original.midX, nextNode.frame.midX - neighborFrame.midX, accuracy: 2)
            XCTAssertEqual(node.frame.midY - original.midY, nextNode.frame.midY - neighborFrame.midY, accuracy: 2)
            let settled = XCTAttachment(screenshot: app.screenshot())
            settled.name = "Memory map snapped to neighboring thread"
            settled.lifetime = .keepAlways
            add(settled)
            let reverse = nextNode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            reverse.press(forDuration: 0.1, thenDragTo: reverse.withOffset(CGVector(dx: -delta.dx, dy: -delta.dy)),
                          withVelocity: .slow, thenHoldForDuration: 0.2)
            waitForMapCenter(node, at: original)
            XCTAssertEqual(node.frame.midX, original.midX, accuracy: 2)
            XCTAssertEqual(node.frame.midY, original.midY, accuracy: 2)
        }
        app.buttons["Recenter map"].tap()
        waitForMapCenter(node, at: original)
        XCTAssertEqual(node.frame.width, original.width, accuracy: 2)

        // Quick releases exercise the handoff without a stationary hold at the end.
        for delta in [CGVector(dx: 28, dy: -16), CGVector(dx: -25, dy: 18)] {
            let start = node.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(delta),
                        withVelocity: .fast, thenHoldForDuration: 0)
            let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(node.frame.midX - original.midX) < 2 && abs(node.frame.midY - original.midY) < 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 3), .completed)
            XCTAssertFalse(app.navigationBars["Thread history"].exists)
        }

        for _ in 0..<2 {
            node.tap()
            XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Thread preview"].exists)
            tapUncoveredBack(in: app, title: "Thread history")
            XCTAssertTrue(node.waitForExistence(timeout: 5))
            XCTAssertTrue(node.isHittable, "The zoom source must remain usable after returning.")
        }
        node.press(forDuration: 0.7)
        app.buttons["map-focus-preview"].tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        tapUncoveredBack(in: app, title: "Thread history")
        XCTAssertFalse(app.buttons["map-focus-preview"].exists)
        app.buttons["Clear focus"].tap()
        picker.buttons[previousView].tap()
        app.tabBars.buttons["Memories"].tap()
    }

    /// Safe for a connected phone: does not seed, edit, archive, or restore memories.
    @MainActor
    func testExistingLibraryGraphNavigationWithoutCaptures() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let previousView = picker.buttons["Timeline"].isSelected ? "Timeline" : "Graph"
        picker.buttons["Graph"].tap()
        let first = try visibleMapNode(in: app)
        let originalFrame = first.frame
        XCTAssertEqual(originalFrame.width, originalFrame.height, accuracy: 2, "Map nodes should be circular.")
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Existing library memory map"
        overview.lifetime = .keepAlways
        add(overview)

        assertMapDoesNotZoom(in: app, node: first)
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 35, dy: 15)))
        waitForMapCenter(first, at: originalFrame)
        XCTAssertEqual(first.frame.midX, originalFrame.midX, accuracy: 2, "Short drags snap back to the centered circle.")
        app.buttons["Recenter map"].tap()
        let expectsPhoto = first.value as? String == "Photos"
        first.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Thread preview"].exists)
        XCTAssertFalse(app.staticTexts["Sources"].exists, "Media belongs in the chronological river, not a separate section.")
        XCTAssertFalse(app.staticTexts["Details & provenance"].exists)
        XCTAssertTrue(app.buttons["Thread options"].exists)
        XCTAssertFalse(app.navigationBars["Thread history"].buttons["Rename"].exists)
        if expectsPhoto {
            let openPhoto = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "river-open-image-")).firstMatch
            // A chronological River can have activity above its first media entry.
            for _ in 0..<8 where !openPhoto.exists { app.swipeUp() }
            XCTAssertTrue(openPhoto.waitForExistence(timeout: 5), "Photos must be visible and tappable directly in the river")
            XCTAssertGreaterThan(openPhoto.frame.height, 100)
            let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-source-")).firstMatch
            XCTAssertEqual(openPhoto.frame.minX, source.frame.minX, accuracy: 1,
                           "Media and its header should share the content column to the right of the river.")
            for _ in 0..<4 where !openPhoto.isHittable { app.swipeUp() }
            openPhoto.tap()
            XCTAssertTrue(app.navigationBars["Memory"].waitForExistence(timeout: 5))
            tapUncoveredBack(in: app, title: "Memory")
            XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Imported history"].exists)
        }
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Existing library inline river"
        preview.lifetime = .keepAlways
        add(preview)
        if expectsPhoto {
            app.swipeUp()
            let continuousRiver = XCTAttachment(screenshot: app.screenshot())
            continuousRiver.name = "Continuous river beside media and between entries"
            continuousRiver.lifetime = .keepAlways
            add(continuousRiver)
        }
        tapUncoveredBack(in: app, title: "Thread history")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons[previousView].tap()
        app.tabBars.buttons["Memories"].tap()
    }

    @MainActor
    func testThreadMenuEditDeleteRestoreAndDirectMemoryBack() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Creates and archives a synthetic thread; simulator only.")
        #else
        let app = XCUIApplication()
        app.launch()
        let title = "Thread controls \(UUID().uuidString.prefix(6))"
        app.buttons["Add a memory"].tap()
        app.buttons["New Note"].tap()
        app.textFields["Title"].tap()
        app.textFields["Title"].typeText(title)
        app.buttons["Save"].tap()
        app.tabBars.buttons["Project"].tap()
        let picker = app.segmentedControls["Project view"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Timeline"].tap()
        let topic = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", title)).firstMatch
        revealTimelineThread(topic, title: title, in: app)
        topic.tap()
        XCTAssertFalse(app.staticTexts["Details & provenance"].exists)
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-source-")).firstMatch
        source.tap()
        XCTAssertTrue(app.navigationBars["Memory"].waitForExistence(timeout: 5))
        app.navigationBars["Memory"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Imported history"].exists)
        app.buttons["Thread options"].tap()
        app.buttons["Edit thread"].tap()
        let name = app.alerts.textFields["Topic name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // Tapping the center places the caret inside the existing title.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count))
        let renamed = "Renamed \(title)"
        name.typeText(renamed)
        XCTAssertEqual(name.value as? String, renamed)
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[renamed].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Thread options"].tap()
        app.buttons["Delete thread…"].tap()
        app.buttons["Delete thread"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.tabBars.buttons["Memories"].tap()
        XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5), "Deleting a thread must retain its memories.")
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Archive"].firstMatch.tap()
        let restore = app.buttons["Restore thread \(renamed)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Project"].tap()
        let restored = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", renamed)).firstMatch
        revealTimelineThread(restored, title: renamed, in: app)
        #endif
    }

    @MainActor
    func testMemoryMapDarkAppearance() throws {
        try checkMemoryMap(appearance: "dark")
    }

    @MainActor
    private func revealTimelineThread(_ row: XCUIElement, title: String, in app: XCUIApplication) {
        let threads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-topic-"))
        // The native vertical list virtualizes rows, unlike the old horizontal chips.
        for _ in 0..<30 {
            if row.exists && row.isHittable { return }
            let firstVisible = threads.allElementsBoundByIndex.first { $0.isHittable }
            if let firstVisible, firstVisible.label > title {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(row.exists && row.isHittable, "The full thread list must allow reaching every title.")
    }

    @MainActor
    private func visibleMapNode(in app: XCUIApplication) throws -> XCUIElement {
        let nodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graph-node-"))
        XCTAssertTrue(nodes.firstMatch.waitForExistence(timeout: 15), "Requires an existing thread; does not create one.")
        let canvas = app.descendants(matching: .any)["memory-map-canvas"].firstMatch
        XCTAssertTrue(canvas.exists)
        // Fixed-scale maps intentionally have offscreen nodes in larger libraries.
        let candidates = nodes.allElementsBoundByIndex.filter {
            $0.isHittable && canvas.frame.insetBy(dx: 1, dy: 1).contains($0.frame)
                && $0.frame.maxY < app.buttons["Recenter map"].frame.minY
        }
        let center = CGPoint(x: canvas.frame.midX, y: canvas.frame.midY - 20)
        let visible = try XCTUnwrap(candidates.min {
            hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
                < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
        }, "At least one complete circle should be visible in the browsing viewport.")
        // Focus raises z-order, so an index-based query can start resolving a different circle.
        return app.buttons[visible.identifier]
    }

    @MainActor
    private func assertMapDoesNotZoom(in app: XCUIApplication, node: XCUIElement) {
        XCTAssertFalse(app.buttons["Zoom in"].exists)
        XCTAssertFalse(app.buttons["Zoom out"].exists)
        XCTAssertFalse(app.buttons["Fit map"].exists)
        XCTAssertFalse(app.staticTexts["All threads"].exists)
        let canvas = app.descendants(matching: .any)["memory-map-canvas"].firstMatch
        XCTAssertGreaterThan(canvas.frame.height, app.frame.height * 0.5, "Graph dedicates the available space to the map.")
        let width = node.frame.width
        canvas.pinch(withScale: 1.7, velocity: 1)
        if app.buttons["Clear focus"].exists { app.buttons["Clear focus"].tap() }
        XCTAssertFalse(app.navigationBars["Thread history"].exists)
        // Permit subtle viewport depth, but never user-controlled magnification.
        XCTAssertEqual(node.frame.width, width, accuracy: width * 0.08)
        app.buttons["Recenter map"].tap()
    }

    @MainActor
    private func checkMemoryMap(appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-remember.appearance", appearance]
        app.launch()
        for title in ["Hackathon submission guidelines", "Judging criteria for the hackathon", "Application submission confirmation", "Building with Gemma", "Digital entrepreneurship class", "Ideas from today's voice memo"] {
            app.tabBars.buttons["Memories"].tap()
            if app.buttons[title].firstMatch.exists { continue }
            app.buttons["Add a memory"].tap()
            app.buttons["New Note"].tap()
            let field = app.textFields["Title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Project"].tap()
        app.segmentedControls["Project view"].buttons["Graph"].tap()
        XCTAssertTrue(app.staticTexts["Your memory map"].waitForExistence(timeout: 5))
        let nodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "graph-node-"))
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Memory map overview — \(appearance)"
        overview.lifetime = .keepAlways
        add(overview)
        XCTAssertGreaterThanOrEqual(nodes.count, 6)
        let first = try visibleMapNode(in: app)
        let originalFrame = first.frame
        assertMapDoesNotZoom(in: app, node: first)
        let panStart = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        panStart.press(forDuration: 0.1, thenDragTo: panStart.withOffset(CGVector(dx: 35, dy: 15)))
        waitForMapCenter(first, at: originalFrame)
        XCTAssertEqual(first.frame.midX, originalFrame.midX, accuracy: 2, "Short drags snap back to the centered circle.")
        app.buttons["Recenter map"].tap()
        first.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Thread preview"].exists)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "Memory map direct river — \(appearance)"
        selected.lifetime = .keepAlways
        add(selected)
        app.navigationBars["Thread history"].buttons.element(boundBy: 0).tap()
        let threadID = first.identifier.replacingOccurrences(of: "graph-node-", with: "project-topic-")
        app.segmentedControls["Project view"].buttons["Timeline"].tap()
        XCTAssertTrue(app.staticTexts["All threads"].waitForExistence(timeout: 5))
        let row = app.buttons[threadID]
        for _ in 0..<20 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.exists, "The same River is also available in Timeline's full thread list.")
        row.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        app.navigationBars["Thread history"].buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Memories"].tap()
        app.buttons["Add a memory"].tap()
        let dial = XCTAttachment(screenshot: app.screenshot())
        dial.name = "Capture dial — \(appearance)"
        dial.lifetime = .keepAlways
        add(dial)
        app.buttons["Close add menu"].tap()
    }

    @MainActor
    func testMemoryMapAccessibilityTextSize() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Creates a synthetic accessibility fixture; simulator only.")
        #else
        let app = XCUIApplication()
        app.launch()
        let title = "Accessible memory map source \(UUID().uuidString.prefix(6))"
        if !app.buttons[title].firstMatch.exists {
            app.buttons["Add a memory"].tap()
            app.buttons["New Note"].tap()
            let field = app.textFields["Title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            app.buttons["Save"].tap()
            XCTAssertTrue(app.buttons["Add a memory"].waitForExistence(timeout: 5))
        }
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Project"].tap()
        app.segmentedControls["Project view"].buttons["Graph"].tap()
        XCTAssertTrue(app.staticTexts["Your memory map"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["All threads"].exists)
        XCTAssertFalse(app.buttons["Zoom in"].exists)
        app.segmentedControls["Project view"].buttons["Timeline"].tap()
        for _ in 0..<4 where !app.staticTexts["All threads"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["All threads"].exists)
        let threads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-topic-"))
        XCTAssertGreaterThan(threads.count, 0)
        // Use this run's source, not an old thread whose capture can precede the River's history window.
        let firstThread = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", title)).firstMatch
        revealTimelineThread(firstThread, title: title, in: app)
        for _ in 0..<6 where firstThread.frame.maxY > app.tabBars.firstMatch.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(firstThread.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Timeline full thread titles at accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        firstThread.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-source-")).firstMatch
        for _ in 0..<4 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.exists)
        let river = XCTAttachment(screenshot: app.screenshot())
        river.name = "River first-line junction alignment at accessibility text size"
        river.lifetime = .keepAlways
        add(river)
        #endif
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
        XCTAssertTrue(app.buttons["Choose Photo or Video"].exists)
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
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "project-topic-", title)).firstMatch
        revealTimelineThread(chip, title: title, in: app)
        chip.tap()
        XCTAssertTrue(app.navigationBars["Thread history"].waitForExistence(timeout: 5))
        let history = app.switches["Travel through time"]
        XCTAssertTrue(history.exists)
        let toggle = history.switches.firstMatch
        (toggle.exists ? toggle : history).tap()
        XCTAssertEqual(history.value as? String, "1")
        XCTAssertTrue(app.sliders["History date"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Project river and historical comparison"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        picker.buttons["Graph"].tap()
        XCTAssertTrue(app.buttons["Recenter map"].exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Project"].tap()
        XCTAssertTrue(app.buttons["Recenter map"].waitForExistence(timeout: 5))
        let graphImage = XCTAttachment(screenshot: app.screenshot())
        graphImage.name = "Project graph"
        graphImage.lifetime = .keepAlways
        add(graphImage)
        picker.buttons["Timeline"].tap()
        revealTimelineThread(chip, title: title, in: app)
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
