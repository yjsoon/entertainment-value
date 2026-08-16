import SwiftData
import SwiftUI

struct LogSessionChooserView: View {
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: \LibraryItem.sortTitle
    ) private var items: [LibraryItem]
    @State private var searchText = ""

    private var availableItems: [LibraryItem] {
        items.filter { $0.archivedAt == nil }
    }

    private var searchResults: [LibraryItem] {
        guard !searchText.isEmpty else { return availableItems }
        return availableItems.filter {
            $0.title.localizedStandardContains(searchText)
                || ($0.creatorLine?.localizedStandardContains(searchText) ?? false)
        }
    }

    private var activeItems: [LibraryItem] {
        availableItems
            .filter { $0.status == .inProgress || $0.status == .paused }
            .sorted(by: activityOrder)
    }

    private var recentlyLoggedItems: [LibraryItem] {
        let activeIDs = Set(activeItems.map(\.id))
        return Array(availableItems
            .filter { $0.lastSessionAt != nil && !activeIDs.contains($0.id) }
            .sorted { ($0.lastSessionAt ?? .distantPast) > ($1.lastSessionAt ?? .distantPast) }
            .prefix(8))
    }

    private var remainingItems: [LibraryItem] {
        let promotedIDs = Set(activeItems.map(\.id) + recentlyLoggedItems.map(\.id))
        return availableItems.filter { !promotedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    chooserSections
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section("Library") {
                        itemRows(searchResults)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(EntertainmentValueTheme.background)
            .navigationTitle("Log a Session")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search your library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var chooserSections: some View {
        if availableItems.isEmpty {
            ContentUnavailableView(
                "No Titles to Log Yet",
                systemImage: "books.vertical",
                description: Text("Add a book, movie, show, game, comic, or podcast to your library first.")
            )
        } else {
            if !activeItems.isEmpty {
                Section("In Progress") {
                    itemRows(activeItems)
                }
            }

            if !recentlyLoggedItems.isEmpty {
                Section("Recently Logged") {
                    itemRows(recentlyLoggedItems)
                }
            }

            if !remainingItems.isEmpty {
                Section("More Titles") {
                    itemRows(remainingItems)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRows(_ items: [LibraryItem]) -> some View {
        ForEach(items) { item in
            Button {
                onSelect(item.id)
            } label: {
                HStack(spacing: 12) {
                    CoverArtworkView(item: item)
                        .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                        .frame(width: 36, height: 50)
                        .clipShape(CoverShape(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .foregroundStyle(.primary)
                        Text(item.creatorLine ?? String(localized: item.mediaKind.singularName))
                            .font(.caption)
                            .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: item.mediaKind.symbolName)
                        .foregroundStyle(item.mediaKind.accentColor)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .accessibilityLabel("Log a session for \(item.title), \(String(localized: item.mediaKind.singularName))")
        }
    }

    private func activityOrder(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        let lhsDate = lhs.lastSessionAt ?? lhs.updatedAt
        let rhsDate = rhs.lastSessionAt ?? rhs.updatedAt
        return lhsDate > rhsDate
    }
}

#Preview("Log Session Chooser") {
    let container = try! AppModelContainer.make(isStoredInMemoryOnly: true)

    LogSessionChooserView(onSelect: { _ in })
        .modelContainer(container)
}
