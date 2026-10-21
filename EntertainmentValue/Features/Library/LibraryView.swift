import SwiftData
import SwiftUI

/// Everything you've added, as a shelf of covers, and the log of every day.
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case shelf = "Shelf"
        case log = "Log"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "In progress"
        case finished = "Finished"
        case planned = "Planned"
        case shelved = "Shelved"
        var id: String { rawValue }

        func includes(_ item: Item) -> Bool {
            switch self {
            case .all: true
            case .active: item.status == .active
            case .finished: item.status == .finished
            case .planned: item.status == .planned
            case .shelved: item.status == .shelved
            }
        }
    }

    var onAdd: () -> Void = {}

    @State private var mode = Mode.shelf
    @State private var filter = Filter.all
    @State private var searchText = ""
    @State private var searching = false
    @State private var editing: Item?
    @FocusState private var searchFocused: Bool

    @Query(sort: \Item.lastActivityAt, order: .reverse) private var items: [Item]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                switch mode {
                case .shelf:
                    if searching { searchField }
                    filterChips
                    grid
                case .log:
                    LogView(style: .embedded)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { item in
            ItemEditor(item: item)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if mode == .shelf {
                    Button {
                        withAnimation(.snappy) {
                            searching.toggle()
                            if !searching { searchText = "" }
                        }
                        searchFocused = searching
                    } label: {
                        Image(systemName: searching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(searching ? "Stop searching" : "Search your library")
                }
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.paper)
                        .frame(width: 40, height: 40)
                        .background(Theme.ink, in: Circle())
                }
                .accessibilityLabel("Add something")
            }
            .foregroundStyle(Theme.ink)
            HStack(alignment: .lastTextBaseline) {
                Text("Library")
                    .font(Theme.display(40, weight: .heavy))
                Spacer()
                Segmented(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                    .frame(width: 150)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("libraryMode")
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search your library", text: $searchText)
                .font(Theme.body)
                .focused($searchFocused)
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(availableFilters) { option in
                    let selected = filter == option
                    Button {
                        filter = option
                    } label: {
                        Text(option.rawValue)
                            .font(Theme.text(13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.paper : Theme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background {
                                if selected {
                                    Capsule().fill(Theme.ink)
                                } else {
                                    Capsule().strokeBorder(Theme.line, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Shelved only shows up once something is shelved.
    private var availableFilters: [Filter] {
        let hasShelved = items.contains { $0.status == .shelved }
        return Filter.allCases.filter { $0 != .shelved || hasShelved || filter == .shelved }
    }

    private var filteredItems: [Item] {
        items.filter { item in
            filter.includes(item)
                && (searchText.isEmpty
                    || item.title.localizedStandardContains(searchText)
                    || (item.creator?.localizedStandardContains(searchText) ?? false))
        }
    }

    @ViewBuilder
    private var grid: some View {
        let shown = filteredItems
        if shown.isEmpty {
            Text(items.isEmpty ? "Your library is empty. Tap + to add something." : "Nothing here.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(shown) { item in
                    Button {
                        editing = item
                    } label: {
                        ShelfTile(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A cover with its title in a fixed two-line slot, so one-line and
/// two-line titles line up across the row.
private struct ShelfTile: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: item.artworkURL, kind: item.kind)
                .aspectRatio(2 / 3, contentMode: .fit)
                .opacity(item.status == .planned ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if let rating = latestRating {
                        Text(rating.formatted(.number.precision(.fractionLength(0...1))))
                            .font(Theme.text(12, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Theme.text(14, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(caption)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var latestRating: Double? {
        item.sortedLogs.lazy.compactMap(\.rating).first
    }

    private var caption: String {
        if item.status == .planned { return "Planned" }
        if item.status == .shelved { return "Shelved" }
        var parts: [String] = []
        if item.status == .active, item.kind.isPaged, item.progressMode == .percent,
           let percent = item.currentPercent {
            parts.append(LogDetail.percent(percent))
        }
        if let creator = item.creator, !creator.isEmpty {
            parts.append(creator)
        } else {
            parts.append(item.kind.displayName)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
