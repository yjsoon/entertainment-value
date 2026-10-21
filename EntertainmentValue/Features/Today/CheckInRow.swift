import SwiftUI

enum CheckInAction {
    /// Episodes up or down.
    case episodes(Int)
    /// "Played" or "Read": on, or off again.
    case toggle
    /// "+5%" or "+20 pages".
    case step
    /// Type a percentage or page.
    case enterPosition
    case finish
    /// The film button: finishes, or reopens the rating with an undo.
    case watched
    case session(Double)
    case shelve
    case edit
}

/// One thing on the check-in. Rows you've logged that day take a soft tint
/// of the medium's colour.
struct CheckInRow: View {
    let item: Item
    let log: Log?
    let day: Date
    let isToday: Bool
    let onOpen: () -> Void
    let act: (CheckInAction) -> Void

    private var logged: Bool { log != nil }
    private var colour: Color { item.kind.color }
    private var usesPosition: Bool { item.kind.isPaged && item.progressMode != .read }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        ArtworkView(url: item.artworkURL, kind: item.kind, cornerRadius: 8)
                            .frame(width: 44, height: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(Theme.text(17, weight: .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(statusLine)
                                .font(Theme.text(13))
                                .foregroundStyle(logged ? Theme.ink.opacity(0.75) : Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the edit screen")
                trailing
            }
            if usesPosition {
                readingButtons
            }
        }
        .padding(12)
        .background(logged ? colour.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu { menu }
        .animation(.snappy(duration: 0.2), value: log?.count)
        .animation(.snappy(duration: 0.2), value: logged)
    }

    // MARK: Controls

    @ViewBuilder
    private var trailing: some View {
        switch item.kind {
        case .tv, .podcast:
            episodeCounter
        case .game:
            toggleButton(title: "Played", on: logged, action: .toggle)
        case .film:
            toggleButton(title: "Watched", on: log?.kind == .finished, action: .watched)
        case .book, .comic:
            if usesPosition {
                Button { act(.enterPosition) } label: {
                    Text(positionLabel)
                        .font(Theme.display(24, weight: .heavy))
                        .foregroundStyle(logged ? colour : Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.progressMode == .pages ? "Set page" : "Set percentage")
                .accessibilityValue(positionLabel)
                .accessibilityIdentifier("checkin.position.\(item.title)")
            } else {
                toggleButton(title: "Read", on: logged, action: .toggle)
            }
        }
    }

    private var episodeCounter: some View {
        let count = log?.count ?? 0
        return HStack(spacing: 4) {
            if count > 0 {
                Button { act(.episodes(-1)) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(colour)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("One fewer episode")
                .accessibilityIdentifier("checkin.minus.\(item.title)")
                Text("\(count)")
                    .font(Theme.display(22, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
            }
            Button { act(.episodes(1)) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(count > 0 ? .white : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                        if count > 0 {
                            shape.fill(colour)
                        } else {
                            shape.fill(Theme.paper)
                            shape.strokeBorder(Theme.line, lineWidth: 1.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("One more episode")
            .accessibilityValue(count == 1 ? "1 episode" : "\(count) episodes")
            .accessibilityIdentifier("checkin.plus.\(item.title)")
        }
    }

    private func toggleButton(title: String, on: Bool, action: CheckInAction) -> some View {
        Button { act(action) } label: {
            HStack(spacing: 6) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title)
                    .font(Theme.text(15, weight: .semibold))
            }
            .foregroundStyle(on ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if on {
                    shape.fill(colour)
                } else {
                    shape.fill(Theme.paper)
                    shape.strokeBorder(Theme.line, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Tap again to undo" : "")
        .accessibilityIdentifier("checkin.toggle.\(item.title)")
    }

    /// Read (a tick for "I read today"), the step button, and Done.
    private var readingButtons: some View {
        HStack(spacing: 6) {
            Button { act(.toggle) } label: {
                HStack(spacing: 5) {
                    if logged {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                    }
                    Text("Read")
                }
                .readingChip(filled: false, colour: colour)
            }
            .accessibilityAddTraits(logged ? .isSelected : [])
            .accessibilityHint(logged ? "Tap again to remove today" : "Logs that you read, without a position")
            .accessibilityIdentifier("checkin.toggle.\(item.title)")

            Button { act(.step) } label: {
                Text(item.progressMode == .pages ? "+\(ReadingMath.pageStep) pages" : "+\(Int(ReadingMath.percentStep))%")
                    .readingChip(filled: true, colour: colour)
            }
            .accessibilityIdentifier("checkin.step.\(item.title)")

            Spacer(minLength: 0)

            Button("Done") { act(.finish) }
                .font(Theme.text(15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Finished")
                .accessibilityIdentifier("checkin.finish.\(item.title)")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Edit", systemImage: "pencil") { act(.edit) }
        switch item.kind {
        case .game:
            ForEach([30.0, 60, 120, 180], id: \.self) { minutes in
                Button("Played \(minutes.hoursLabel)") { act(.session(minutes)) }
            }
            Button("Finished", systemImage: "checkmark.circle") { act(.finish) }
        case .tv, .podcast:
            Button(item.kind == .tv ? "Finished the show" : "Stopped listening", systemImage: "checkmark.circle") {
                act(.finish)
            }
        case .book, .comic:
            if usesPosition {
                Button(item.progressMode == .pages ? "Set page" : "Set percentage", systemImage: "number") {
                    act(.enterPosition)
                }
            }
            Button("Finished", systemImage: "checkmark.circle") { act(.finish) }
        case .film:
            if log == nil {
                Button("Watched part of it") { act(.session(45)) }
            }
        }
        Divider()
        Button("Shelve", systemImage: "archivebox") { act(.shelve) }
    }

    // MARK: Text

    private var dayWord: String { isToday ? " today" : "" }

    private var positionLabel: String {
        if item.progressMode == .pages {
            if let page = log?.page ?? item.page(before: day) { return "p. \(page)" }
            return "p. \u{2013}"
        }
        let current = log.flatMap { item.percent(of: $0) } ?? item.percent(before: day)
        return current.map(LogDetail.percent) ?? "0%"
    }

    private var statusLine: String {
        switch item.kind {
        case .tv, .podcast:
            if let count = log?.count, count > 0 {
                let line = count == 1 ? "1 episode\(dayWord)" : "\(count) episodes\(dayWord)"
                return log?.kind == .finished ? line + ", finished" : line
            }
            if log?.kind == .finished { return "Finished\(dayWord)" }
            return lastLine
        case .book, .comic:
            if let log {
                if log.kind == .finished { return "Finished\(dayWord)" }
                var line = "Read\(dayWord)"
                if usesPosition, let before = item.percent(before: day), item.progressMode == .percent {
                    line += " \u{00B7} was \(LogDetail.percent(before))"
                } else if usesPosition, let before = item.page(before: day), item.progressMode == .pages {
                    line += " \u{00B7} was p. \(before)"
                }
                return line
            }
            if item.progressMode == .percent, let before = item.percent(before: day) {
                return "At \(LogDetail.percent(before)) \u{00B7} \(lastLine.lowercasedFirst)"
            }
            if item.progressMode == .pages, let page = item.page(before: day) {
                let of = item.pageCount.map { " of \($0)" } ?? ""
                return "Page \(page)\(of) \u{00B7} \(lastLine.lowercasedFirst)"
            }
            return lastLine
        case .game:
            if let log {
                if log.kind == .finished { return "Finished\(dayWord)" }
                return log.durationSource == .measured ? "Played \(log.minutes.hoursLabel)\(dayWord)" : "Played\(dayWord)"
            }
            return lastLine
        case .film:
            if let log {
                return log.kind == .finished ? "Watched\(dayWord)" : "Watched some\(dayWord)"
            }
            var parts = [item.kind.displayName]
            if let runtime = item.runtimeMinutes { parts.append(Double(runtime).hoursLabel) }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    /// "Last: Tuesday", "Last: yesterday", "Not started".
    private var lastLine: String {
        let start = Calendar.current.startOfDay(for: day)
        guard let last = (item.logs ?? []).map(\.date).filter({ $0 < start }).max() else { return "Not started" }
        return "Last: " + RelativeDay.text(for: last, from: day)
    }
}

enum RelativeDay {
    /// "yesterday", "Tuesday" within the week, otherwise "3 Oct".
    static func text(for date: Date, from reference: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: reference)
        ).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

private extension View {
    func readingChip(filled: Bool, colour: Color) -> some View {
        self
            .font(Theme.text(15, weight: .semibold))
            .foregroundStyle(filled ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if filled {
                    shape.fill(colour)
                } else {
                    shape.fill(Theme.paper)
                    shape.strokeBorder(Theme.line, lineWidth: 1.5)
                }
            }
    }
}
