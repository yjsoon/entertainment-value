import Foundation
import Testing

@testable import EntertainmentValue

@Suite("App navigation")
@MainActor
struct AppNavigationTests {
  @Test("Log chooser defers the editor until dismissal")
  func deferredLogEditor() {
    let navigation = AppNavigation()
    let itemID = UUID()

    navigation.showLogChooser()
    #expect(navigation.presentedSheet == .chooseItemToLog)

    navigation.chooseItemToLog(itemID)
    #expect(navigation.presentedSheet == nil)

    navigation.presentPendingLogSessionIfNeeded()
    #expect(navigation.presentedSheet == .logSession(itemID))

    navigation.presentPendingLogSessionIfNeeded()
    #expect(navigation.presentedSheet == .logSession(itemID))
  }

  @Test("Log chooser can continue by adding a new title")
  func addNewTitleFromLogChooser() {
    let navigation = AppNavigation()

    navigation.showLogChooser()
    navigation.addNewTitleToLog()
    #expect(navigation.presentedSheet == nil)

    navigation.presentPendingLogSessionIfNeeded()
    #expect(navigation.presentedSheet == .quickAdd(logsAfterAdding: true))
  }
}
