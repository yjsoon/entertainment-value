import XCTest

/// A scripted walk through the app for the recorded demo video. It runs on
/// sample data in memory and never fails on a missing element, so the video
/// always gets made.
@MainActor
final class DemoTour: XCTestCase {
    private var app: XCUIApplication!

    func testTour() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-demoData"]
        app.launch()
        // The workflow trims the video to start here.
        print("DEMO_START \(Date().timeIntervalSince1970)")
        pause(3)

        // One-tap logging on the Now tab.
        tap(app.buttons["Watched S2 E6"])
        pause(2)
        tap(app.buttons["+25 pages"].firstMatch)
        pause(2)
        tap(app.buttons["Played Ep 12"])
        pause(2)

        // Finish a film, rate it on the dial and leave a note.
        tap(app.buttons["Finished"].firstMatch)
        pause(1.5)
        let dial = app.descendants(matching: .any)["ratingDial"]
        if dial.waitForExistence(timeout: 4) {
            let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.95))
            let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
            start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        pause(1)
        let note = app.descendants(matching: .any)["noteField"]
        if note.waitForExistence(timeout: 3) {
            note.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            app.typeText("Loud, joyful, and that juke joint scene.")
        }
        pause(1)
        tap(app.buttons["Save"])
        pause(3)
        if app.state != .runningForeground {
            print("DEMO_APP_DIED_AFTER_SAVE state=\(app.state.rawValue)")
            app.launch()
            pause(2)
        }

        // Money: what each service cost per hour this month.
        tap(tab("Money"))
        pause(4)
        app.swipeUp()
        pause(3)
        app.swipeDown()
        pause(1)

        // Library: covers, then the diary.
        tap(tab("Library"))
        pause(3)
        tap(app.buttons["Diary"])
        pause(3)
        app.swipeUp()
        pause(2)

        // Add anything.
        tap(app.buttons["Add something"].firstMatch)
        pause(1.5)
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Klara and the Sun")
        }
        pause(6)
        tap(app.buttons["Close"])
        pause(1)

        tap(tab("Now"))
        pause(3)
    }

    private func tab(_ name: String) -> XCUIElement {
        let bar = app.tabBars.buttons[name]
        return bar.exists ? bar : app.buttons[name].firstMatch
    }

    private func tap(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) {
            element.tap()
        } else {
            XCTContext.runActivity(named: "Missing element: \(element)") { _ in }
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
