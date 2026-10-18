import SwiftData
import SwiftUI

/// Everything you've added, and the diary of everything you've logged.
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case everything = "Everything"
        case diary = "Diary"
        var id: String { rawValue }
    }

    @State private var mode = Mode.everything
    @State private var filter: MediaKind?
    @State private var searchText = ""

    @Query(sort: \Item.lastActivityAt, order: .reverse) private var items: [Item]
    @Query(sort: \Log.date, order: .reverse) private var logs: [Log]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                KindFilter(selection: $filter)

                switch mode {
                case .everything: grid
                case .diary: diary
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .paperBackground()
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search your library")
    }

    private var filteredItems: [Item] {
        items.filter { item in
            (filter == nil || item.kind == filter)
                && (searchText.isEmpty || item.title.localizedStandardContains(searchText))
        }
    }

    @ViewBuilder
    private var grid: some View {
        if filteredItems.isEmpty {
            Text(items.isEmpty ? "Your library is empty. Tap + to add something." : "Nothing matches.")
                .foregroundStyle(Theme.muted)
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                ForEach(filteredItems) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(url: item.artworkURL, kind: item.kind)
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .overlay(alignment: .topTrailing) { StatusBadge(status: item.status) }
                            Text(item.title)
                                .font(Theme.display(13, weight: .bold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct DiaryMonth: Identifiable {
        let id: MonthKey
        let logs: [Log]
    }

    private var diaryGroups: [DiaryMonth] {
        let filtered = logs.filter { log in
            guard let item = log.item else { return false }
            return (filter == nil || item.kind == filter)
                && (searchText.isEmpty || item.title.localizedStandardContains(searchText))
        }
        let grouped = Dictionary(grouping: filtered) { MonthKey($0.date) }
        return grouped.keys.sorted(by: >).map { DiaryMonth(id: $0, logs: grouped[$0] ?? []) }
    }

    @ViewBuilder
    private var diary: some View {
        let groups = diaryGroups
        if groups.isEmpty {
            Text("Nothing logged yet.")
                .foregroundStyle(Theme.muted)
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.logs) { log in
                            if let item = log.item {
                                NavigationLink(value: item) {
                                    DiaryRow(log: log, item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        SectionLabel(text: group.id.title())
                            .padding(.vertical, 6)
                            .background(Theme.paper)
                    }
                }
            }
        }
    }
}

struct KindFilter: View {
    @Binding var selection: MediaKind?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", color: Theme.ink, selected: selection == nil) { selection = nil }
                ForEach(MediaKind.allCases) { kind in
                    chip(title: kind.pluralName, color: kind.color, selected: selection == kind) {
                        selection = selection == kind ? nil : kind
                    }
                }
            }
        }
    }

    private func chip(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(13, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Theme.paper : color)
                .background(selected ? color : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(color.opacity(selected ? 0 : 0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        switch status {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.ink)
                .padding(5)
        case .active:
            Image(systemName: "play.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.ink)
                .padding(5)
        case .planned, .shelved:
            EmptyView()
        }
    }
}

/// A Letterboxd-style diary line: the day, a small cover, what happened.
struct DiaryRow: View {
    let log: Log
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            Text(log.date.formatted(.dateTime.day()))
                .font(Theme.display(20, weight: .heavy))
                .monospacedDigit()
                .frame(width: 34)
                .foregroundStyle(Theme.muted)
            ArtworkView(url: item.artworkURL, kind: item.kind, cornerRadius: 5)
                .frame(width: 30, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.display(15, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(detail)
                    if let rating = log.rating {
                        Text(Stars.text(rating))
                            .foregroundStyle(item.kind.color)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                if let note = log.note {
                    Text(note)
                        .font(log.isQuote ? .caption.italic() : .caption)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        switch log.kind {
        case .finished: "Finished"
        case .episode: log.episodeRef.map { $0.label(for: item.kind) } ?? "Episode"
        case .progress: log.page.map { "Page \($0)" } ?? "Read"
        case .session: "Played \(log.minutes.hoursLabel)"
        }
    }
}

enum Stars {
    /// "★★★★½"
    static func text(_ rating: Double) -> String {
        let whole = Int(rating.rounded(.down))
        let half = rating - Double(whole) >= 0.5
        return String(repeating: "★", count: whole) + (half ? "½" : "")
    }
}
