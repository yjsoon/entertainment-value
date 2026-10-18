import SwiftData
import SwiftUI

/// One search box for everything. The medium is worked out from the result,
/// so you never pick it first.
struct AddView: View {
    var onAdded: () -> Void = {}

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MediaKind: [MetadataSearchResult]] = [:]
    @State private var problems: [String] = []
    @State private var isSearching = false
    @State private var manualKind = MediaKind.book

    private static let searchKinds: [MediaKind] = [.film, .tv, .book, .game, .podcast]

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    Section {
                        Text("Search films, TV, books, games and podcasts at once. Tap a result to start it now, or add it to Up next.")
                            .foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.raised)
                }

                ForEach(Self.searchKinds) { kind in
                    if let found = results[kind], !found.isEmpty {
                        Section(kind.pluralName) {
                            ForEach(found.prefix(6)) { result in
                                ResultRow(result: result, kind: kind) {
                                    add(result, status: .active)
                                } onLater: {
                                    add(result, status: .planned)
                                } onFinished: {
                                    addFinished(result)
                                }
                            }
                        }
                        .listRowBackground(Theme.raised)
                    }
                }

                if !trimmedQuery.isEmpty {
                    Section("Not here?") {
                        Picker("Kind", selection: $manualKind) {
                            ForEach(MediaKind.allCases) { Text($0.displayName).tag($0) }
                        }
                        Button("Add \u{201C}\(trimmedQuery)\u{201D} as a \(manualKind.displayName.lowercased())") {
                            addManually()
                        }
                    }
                    .listRowBackground(Theme.raised)
                }

                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { Text($0) }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
                }
            }
            .overlay {
                if isSearching && results.isEmpty {
                    ProgressView()
                }
            }
            .paperBackground()
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: trimmedQuery) {
                await search(trimmedQuery)
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else {
            results = [:]
            problems = []
            return
        }
        // Wait for typing to settle.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        let catalog = services.metadata.catalog
        var found: [MediaKind: [MetadataSearchResult]] = [:]
        var failures: [String] = []

        await withTaskGroup(of: (MediaKind, Result<[MetadataSearchResult], any Error>).self) { group in
            for kind in Self.searchKinds {
                group.addTask {
                    do {
                        let page = try await catalog.search(
                            MetadataSearchRequest(query: text, mediaType: kind.metadataType, limit: 8)
                        )
                        return (kind, .success(page.results))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            for await (kind, outcome) in group {
                switch outcome {
                case let .success(list):
                    found[kind] = list
                case let .failure(error):
                    if error is CancellationError { continue }
                    if let metadataError = error as? MetadataProviderError,
                       case .missingCredential = metadataError {
                        failures.append("\(kind.pluralName) search needs an API key.")
                    } else {
                        failures.append("\(kind.pluralName) search didn't work just now.")
                    }
                }
            }
        }

        guard !Task.isCancelled else { return }
        results = found
        problems = failures.sorted()
    }

    private func add(_ result: MetadataSearchResult, status: ItemStatus) {
        let library = Library(context: context)
        guard let item = try? library.add(result, status: status) else { return }
        fetchDetails(for: result, into: item)
        finish()
    }

    private func addFinished(_ result: MetadataSearchResult) {
        let library = Library(context: context)
        guard let item = try? library.add(result, status: .active) else { return }
        _ = try? library.recordPastFinish(item)
        fetchDetails(for: result, into: item)
        finish()
    }

    private func addManually() {
        guard !trimmedQuery.isEmpty else { return }
        _ = try? Library(context: context).addManually(kind: manualKind, title: trimmedQuery, status: .active)
        finish()
    }

    private func finish() {
        onAdded()
        dismiss()
    }

    /// Runtimes and page counts often only come with the details call. They
    /// arrive in the background and later logs use them.
    private func fetchDetails(for result: MetadataSearchResult, into item: Item) {
        guard let provider = services.metadata.catalog.provider(id: result.id.provider) else { return }
        let container = context.container
        let itemID = item.id
        Task {
            guard let details = try? await provider.details(for: result) else { return }
            let context = container.mainContext
            var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else { return }
            try? Library(context: context).applyDetails(details, to: item)
        }
    }
}

private struct ResultRow: View {
    let result: MetadataSearchResult
    let kind: MediaKind
    let onStart: () -> Void
    let onLater: () -> Void
    let onFinished: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStart) {
                HStack(spacing: 12) {
                    ArtworkView(url: result.thumbnailImageURL ?? result.coverImageURL, kind: kind, cornerRadius: 6)
                        .frame(width: 40, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(Theme.display(16, weight: .bold))
                            .lineLimit(2)
                        Text(detailLine)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts it now")

            Menu {
                Button("Start now", systemImage: "play", action: onStart)
                Button("Add to Up next", systemImage: "text.badge.plus", action: onLater)
                Button("Already finished", systemImage: "checkmark.circle", action: onFinished)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(kind.color)
            }
            .accessibilityLabel("More ways to add \(result.title)")
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let year = result.releaseYear { parts.append(String(year)) }
        if let creator = result.creators.first { parts.append(creator) }
        return parts.isEmpty ? kind.displayName : parts.joined(separator: " · ")
    }
}
