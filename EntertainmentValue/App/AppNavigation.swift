import Observation
import SwiftUI

enum AppTab: Hashable, Sendable {
  case home
  case library
  case lists
  case search
}

enum AppRoute: Hashable, Sendable {
  case item(UUID)
  case list(UUID)
  case settings
  case mediaValueSetup
  case importExport
  case archived
  case recentlyDeleted
}

enum AppSheet: Identifiable, Hashable, Sendable {
  case quickAdd(
    initialMediaKind: MediaKind? = nil,
    destinationListID: UUID? = nil,
    logsAfterAdding: Bool = false
  )
  case addItem
  case addItemFor(MediaKind, String)
  case chooseItemToLog
  case logSession(UUID)
  case editItem(UUID)
  case createList

  var id: String {
    switch self {
    case .quickAdd(let initialMediaKind, let destinationListID, let logsAfterAdding):
      "quick-add-\(initialMediaKind?.rawValue ?? "remembered")-\(destinationListID?.uuidString ?? "library")-\(logsAfterAdding)"
    case .addItem:
      "add-item"
    case .addItemFor(let kind, let query):
      "add-item-\(kind.rawValue)-\(query)"
    case .chooseItemToLog:
      "choose-item-to-log"
    case .logSession(let id):
      "log-session-\(id.uuidString)"
    case .editItem(let id):
      "edit-item-\(id.uuidString)"
    case .createList:
      "create-list"
    }
  }
}

@Observable
final class AppNavigation {
  var selectedTab = AppTab.home
  var homePath: [AppRoute] = []
  var libraryPath: [AppRoute] = []
  var listsPath: [AppRoute] = []
  var searchPath: [AppRoute] = []
  var presentedSheet: AppSheet?
  private var pendingLogSessionID: UUID?
  private var shouldAddNewTitleToLog = false

  func showLogChooser() {
    presentedSheet = .chooseItemToLog
  }

  /// Defers the editor until the chooser's dismissal has completed so SwiftUI
  /// never has to replace one sheet with another in the same update.
  func chooseItemToLog(_ id: UUID) {
    pendingLogSessionID = id
    presentedSheet = nil
  }

  func logAfterCurrentSheetDismisses(_ id: UUID) {
    pendingLogSessionID = id
  }

  func addNewTitleToLog() {
    shouldAddNewTitleToLog = true
    presentedSheet = nil
  }

  func presentPendingLogSessionIfNeeded() {
    if shouldAddNewTitleToLog, presentedSheet == nil {
      shouldAddNewTitleToLog = false
      presentedSheet = .quickAdd(logsAfterAdding: true)
      return
    }
    guard let pendingLogSessionID, presentedSheet == nil else { return }
    self.pendingLogSessionID = nil
    presentedSheet = .logSession(pendingLogSessionID)
  }

  func showItem(_ id: UUID, from tab: AppTab? = nil) {
    let sourceTab = tab ?? selectedTab
    switch sourceTab {
    case .home:
      homePath.append(.item(id))
    case .library:
      libraryPath.append(.item(id))
    case .lists:
      listsPath.append(.item(id))
    case .search:
      searchPath.append(.item(id))
    }
  }

  func showSettings() {
    switch selectedTab {
    case .home:
      homePath.append(.settings)
    case .library:
      libraryPath.append(.settings)
    case .lists:
      listsPath.append(.settings)
    case .search:
      searchPath.append(.settings)
    }
  }

  func showImportExport() {
    switch selectedTab {
    case .home:
      homePath.append(.importExport)
    case .library:
      libraryPath.append(.importExport)
    case .lists:
      listsPath.append(.importExport)
    case .search:
      searchPath.append(.importExport)
    }
  }

  func popCurrent() {
    switch selectedTab {
    case .home:
      if !homePath.isEmpty { homePath.removeLast() }
    case .library:
      if !libraryPath.isEmpty { libraryPath.removeLast() }
    case .lists:
      if !listsPath.isEmpty { listsPath.removeLast() }
    case .search:
      if !searchPath.isEmpty { searchPath.removeLast() }
    }
  }
}
