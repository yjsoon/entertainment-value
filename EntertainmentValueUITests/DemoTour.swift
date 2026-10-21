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

        // The daily check-in: two episodes, a bit of reading, a game session.
        tap(element("checkin.plus.Andor"))
        pause(1)
        tap(element("checkin.plus.Andor"))
        pause(1.5)
        tap(element("checkin.step.Piranesi"))
        pause(1.5)
        tap(element("checkin.toggle.Hades II"))
        pause(2)

        // Watch a film, rate it on the dial and leave a note.
        tap(element("checkin.toggle.Sinners"))
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
        pause(2.5)
        relaunchIfNeeded()

        // The edit screen for a book.
        tap(element("checkin.open.Piranesi"))
        pause(2.5)
        app.swipeUp()
        pause(2)
        app.swipeDown()
        pause(1)
        tap(app.buttons["Cancel"])
        pause(1.5)

        // The log, a day at a time.
        tap(element("openLog"))
        pause(3)
        app.swipeUp()
        pause(2.5)
        app.swipeDown()
        pause(1)
        app.navigationBars.buttons.firstMatch.tap()
        pause(1.5)

        // Value: what each service cost per hour this month.
        tap(tab("Value"))
        pause(4)
        app.swipeUp()
        pause(2.5)
        app.swipeDown()
        pause(1)

        // Library: the shelf, then the log inside it.
        tap(tab("Library"))
        pause(3)
        app.swipeUp()
        pause(2)
        app.swipeDown()
        pause(1)

        // Add anything.
        tap(app.buttons["Add something"].firstMatch)
        pause(1.5)
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Klara and the Sun")
        }
        pause(5)
        tap(app.buttons["Close"])
        pause(1)

        tap(tab("Today"))
        pause(3)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tab(_ name: String) -> XCUIElement {
        let bar = app.tabBars.buttons[name]
        return bar.exists ? bar : app.buttons[name].firstMatch
    }

    private func relaunchIfNeeded() {
        if app.state != .runningForeground {
            print("DEMO_APP_DIED state=\(app.state.rawValue)")
            app.launch()
            pause(2)
        }
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
