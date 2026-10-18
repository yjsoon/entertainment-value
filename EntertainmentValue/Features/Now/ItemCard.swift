import SwiftUI

/// A card for something in progress. The big button is the whole point:
/// it already knows the date, the service and what comes next.
struct ItemCard: View {
    let item: Item
    let services: [Service]
    let onAction: (PrimaryAction) -> Void
    let onSetPage: () -> Void
    let onSession: (Double) -> Void
    let onFinish: () -> Void
    let onShelve: () -> Void
    let onService: (UUID?, FreeReason?) -> Void

    var body: some View {
        let progress = item.progress
        let action = LogPlanner.primaryAction(for: progress)

        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: item) {
                HStack(alignment: .top, spacing: 12) {
                    ArtworkView(url: item.artworkURL, kind: item.kind)
                        .frame(width: 54, height: 78)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(Theme.display(17, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(progressLine(progress))
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        if let fraction = LogPlanner.fractionRead(progress) {
                            ProgressView(value: fraction)
                                .tint(item.kind.color)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    onAction(action)
                } label: {
                    Text(action.title(for: item.kind))
                        .font(Theme.display(15, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(item.kind.color, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(hint(for: action))

                if item.kind.isPaged {
                    Button("Set page", action: onSetPage)
                        .font(Theme.display(13, weight: .bold))
                        .buttonStyle(.bordered)
                        .tint(item.kind.color)
                }

                Spacer(minLength: 0)
                serviceMenu
            }
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
        .contextMenu { extraActions(progress) }
    }

    private var serviceMenu: some View {
        Menu {
            let usable = services.filter(\.isActive)
            if !usable.isEmpty {
                Section("Your services") {
                    ForEach(usable) { service in
                        Button(service.name) { onService(service.id, nil) }
                    }
                }
            }
            Section("Free") {
                ForEach(FreeReason.allCases, id: \.self) { reason in
                    Button(reason.displayName) { onService(nil, reason) }
                }
            }
            Button("Not set") { onService(nil, nil) }
        } label: {
            Text(serviceLabel)
                .font(Theme.display(12, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Theme.line))
        }
        .accessibilityLabel("Service: \(serviceLabel)")
    }

    private var serviceLabel: String {
        if let id = item.serviceID, let service = services.first(where: { $0.id == id }) {
            return service.name
        }
        if let reason = item.freeReason { return reason.displayName }
        return "Where?"
    }

    @ViewBuilder
    private func extraActions(_ progress: ItemProgress) -> some View {
        switch item.kind {
        case .game:
            ForEach([30.0, 60, 120, 180], id: \.self) { minutes in
                Button("Played \(minutes.hoursLabel)") { onSession(minutes) }
            }
            Button("Finished", systemImage: "checkmark.circle", action: onFinish)
        case .tv, .podcast:
            if let last = progress.lastEpisode, item.kind == .tv {
                Button("Watched \(last.nextSeason.label(for: item.kind))") {
                    onAction(.episode(last.nextSeason))
                }
            }
            Button(item.kind == .tv ? "Finished the show" : "Stopped listening", systemImage: "checkmark.circle", action: onFinish)
        case .book, .comic:
            Button("Set page", systemImage: "number", action: onSetPage)
            Button("Finished", systemImage: "checkmark.circle", action: onFinish)
        case .film:
            Button("Watched part of it") { onSession(45) }
        }
        Divider()
        Button("Shelve", systemImage: "archivebox", action: onShelve)
    }

    private func progressLine(_ progress: ItemProgress) -> String {
        switch item.kind {
        case .tv, .podcast:
            if let last = progress.lastEpisode { return "Last: \(last.label(for: item.kind))" }
            return "Not started"
        case .book, .comic:
            if let page = progress.currentPage {
                if let count = item.pageCount { return "Page \(page) of \(count)" }
                return "Page \(page)"
            }
            return item.pageCount.map { "\($0) pages" } ?? "Not started"
        case .game:
            let minutes = item.totalMinutes
            return minutes > 0 ? "\(minutes.hoursLabel) played" : "Not started"
        case .film:
            if let runtime = item.runtimeMinutes { return Double(runtime).hoursLabel }
            return item.subtitleLine
        }
    }

    private func hint(for action: PrimaryAction) -> String {
        switch action {
        case .finish: "Logs it as finished today."
        case .episode: "Logs this episode as watched today."
        case .pages: "Adds pages to your progress."
        case .played: "Logs a session of your usual length. Long-press the card to pick a length."
        }
    }
}
