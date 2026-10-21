import CoreGraphics
import Foundation
import Testing
@testable import EntertainmentValue

@Suite("Logging rules")
struct DayLoggingTests {
    @Test("Reading progress turns into minutes")
    func readingMinutes() {
        // 10% of a 300-page book is 30 pages, at 40 pages an hour.
        #expect(ReadingMath.minutes(fromPercent: 20, toPercent: 30, pageCount: 300, kind: .book) == 45)
        // Unknown length assumes 300 pages for a book and 150 for a comic.
        #expect(ReadingMath.minutes(fromPercent: nil, toPercent: 10, pageCount: nil, kind: .book) == 45)
        #expect(ReadingMath.minutes(fromPercent: nil, toPercent: 40, pageCount: nil, kind: .comic) == 30)
        // Going backwards counts nothing.
        #expect(ReadingMath.minutes(fromPercent: 50, toPercent: 40, pageCount: 300, kind: .book) == 0)
        #expect(ReadingMath.minutes(fromPage: 40, toPage: 80, kind: .book) == 60)
    }

    @Test("Reading speed turns pages into minutes")
    func readingSpeed() {
        #expect(ReadingSpeed.defaultBook.minutes(forPages: 40) == 60)
        #expect(ReadingSpeed.defaultComic.minutes(forPages: 60) == 30)
        #expect(ReadingSpeed.defaultBook.minutes(forPages: 0) == 0)
    }

    @Test("A day's log reads naturally")
    func details() {
        func text(
            _ kind: MediaKind, _ logKind: LogKind, count: Int = 1, percent: Double? = nil,
            previous: Double? = nil, page: Int? = nil, previousPage: Int? = nil,
            minutes: Double = 60, measured: Bool = false
        ) -> String? {
            LogDetail.text(
                kind: kind, logKind: logKind, count: count, percent: percent, previousPercent: previous,
                page: page, previousPage: previousPage, minutes: minutes, measured: measured
            )
        }
        #expect(text(.tv, .episode, count: 2) == "\u{00D7}2")
        #expect(text(.tv, .finished, count: 1) == "\u{00D7}1, finished")
        #expect(text(.book, .progress, percent: 43, previous: 38) == "38 \u{2192} 43%")
        #expect(text(.book, .progress, percent: 12) == "12%")
        #expect(text(.book, .progress) == "read")
        #expect(text(.comic, .progress, page: 85, previousPage: 40) == "p. 40 \u{2192} 85")
        #expect(text(.book, .finished, percent: 100, previous: 90) == "finished")
        #expect(text(.game, .session, minutes: 90, measured: true) == "1h 30m")
        #expect(text(.game, .session) == nil)
        #expect(text(.film, .finished) == "finished")
    }

    @Test("Durations read like a clock")
    func hours() {
        #expect(45.0.hoursLabel == "45 min")
        #expect(120.0.hoursLabel == "2h")
        #expect(570.0.hoursLabel == "9h 30m")
        #expect(62.0.hoursLabel == "1h")
        #expect(0.0.hoursLabel == "0 min")
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
