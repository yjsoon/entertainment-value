import CoreGraphics
import Foundation
import Testing
@testable import EntertainmentValue

@Suite("Logging rules")
struct LogPlannerTests {
    @Test("Each medium gets the right one-tap action")
    func primaryActions() {
        #expect(LogPlanner.primaryAction(for: ItemProgress(kind: .film)) == .finish)
        #expect(LogPlanner.primaryAction(for: ItemProgress(kind: .game)) == .played)
        #expect(LogPlanner.primaryAction(for: ItemProgress(kind: .tv)) == .episode(EpisodeRef(season: 1, episode: 1)))
        #expect(
            LogPlanner.primaryAction(for: ItemProgress(kind: .tv, lastEpisode: EpisodeRef(season: 2, episode: 5)))
                == .episode(EpisodeRef(season: 2, episode: 6))
        )
        #expect(LogPlanner.primaryAction(for: ItemProgress(kind: .book, currentPage: 10, pageCount: 300)) == .pages(25))
        #expect(LogPlanner.primaryAction(for: ItemProgress(kind: .book, currentPage: 300, pageCount: 300)) == .finish)
    }

    @Test("Button titles read naturally")
    func titles() {
        #expect(PrimaryAction.episode(EpisodeRef(season: 2, episode: 6)).title(for: .tv) == "Watched S2 E6")
        #expect(PrimaryAction.episode(EpisodeRef(season: 1, episode: 12)).title(for: .podcast) == "Played Ep 12")
        #expect(PrimaryAction.pages(25).title(for: .book) == "+25 pages")
    }

    @Test("Adding pages stops at the last page")
    func pageCap() {
        #expect(LogPlanner.page(after: ItemProgress(kind: .book, currentPage: 260, pageCount: 272), adding: 25) == 272)
        #expect(LogPlanner.page(after: ItemProgress(kind: .book), adding: 25) == 25)
        #expect(LogPlanner.fractionRead(ItemProgress(kind: .book, currentPage: 136, pageCount: 272)) == 0.5)
    }

    @Test("Reading speed turns pages into minutes")
    func readingSpeed() {
        #expect(ReadingSpeed.defaultBook.minutes(forPages: 40) == 60)
        #expect(ReadingSpeed.defaultComic.minutes(forPages: 60) == 30)
        #expect(ReadingSpeed.defaultBook.minutes(forPages: 0) == 0)
    }

    @Test("Service linking stops at the first rung that answers")
    func serviceLadder() {
        let netflix = UUID(), disney = UUID(), cancelled = UUID()
        let active: Set<UUID> = [netflix, disney]
        #expect(ServiceLinker.resolve(existing: disney, providerMatches: [netflix], lastUsedForKind: netflix, activeServiceIDs: active) == .existing(disney))
        #expect(ServiceLinker.resolve(existing: nil, providerMatches: [netflix], lastUsedForKind: disney, activeServiceIDs: active) == .provider(netflix))
        #expect(ServiceLinker.resolve(existing: nil, providerMatches: [netflix, disney], lastUsedForKind: disney, activeServiceIDs: active) == .lastUsed(disney))
        #expect(ServiceLinker.resolve(existing: cancelled, providerMatches: [], lastUsedForKind: cancelled, activeServiceIDs: active) == .ask)
    }

    @Test("Provider names match loosely")
    func providerNames() {
        #expect(ServiceLinker.matches(providerName: "Netflix basic with Ads", serviceName: "Netflix"))
        #expect(ServiceLinker.matches(providerName: "Disney Plus", serviceName: "Disney+"))
        #expect(ServiceLinker.matches(providerName: "Apple TV+", serviceName: "Netflix") == false)
        #expect(ServiceLinker.matches(providerName: "Apple TV+", serviceName: "apple tv"))
    }

    @Test("The rating dial maps the arc to half stars")
    func dial() {
        let geometry = DialGeometry(size: CGSize(width: 220, height: 120), lineWidth: 20)
        #expect(geometry.rating(at: geometry.point(at: 0)) == 0.5)
        #expect(geometry.rating(at: geometry.point(at: 1)) == 5)
        #expect(geometry.rating(at: geometry.point(at: 0.45)) == 2.5)
        #expect(geometry.rating(at: geometry.point(at: 0.78)) == 4)
        // Dragging below the arc's ends still counts as the nearest end.
        #expect(geometry.rating(at: CGPoint(x: 400, y: 200)) == 5)
    }
}

extension ItemProgress {
    init(kind: MediaKind, lastEpisode: EpisodeRef? = nil, currentPage: Int? = nil, pageCount: Int? = nil) {
        self.init(kind: kind, lastEpisode: lastEpisode, currentPage: currentPage, pageCount: pageCount, lastLoggedAt: nil)
    }
}
