import Foundation
import Testing
@testable import EntertainmentValue

@Suite("Podcast RSS")
struct PodcastFeedTests {
    @Test("Summary cleanup preserves malformed text and handles unmatched brackets linearly")
    func summaryCleanup() throws {
        let malformed = String(repeating: "<", count: 40_000)
        let cases = [
            ("<p>Hello<br />world</p>&lt;literal&gt; &amp; end", "Hello\nworld\n<literal> & end"),
            ("before <> after <unfinished", "before <> after <unfinished"),
            ("before <<tag>after", "before after"),
            (malformed, malformed),
        ]
        for (input, expected) in cases {
            let xml = "<rss><channel><title>Show</title><description><![CDATA[\(input)]]></description><item><guid>1</guid><title>Episode</title><description><![CDATA[\(input)]]></description></item></channel></rss>"
            let feed = try PodcastFeedParser().parse(Data(xml.utf8))
            #expect(feed.summary == expected)
            #expect(feed.episodes.first?.summary == expected)
        }
    }

    @Test("RSS parser maps episode progress metadata")
    func parseRSS() throws {
        let data = try podcastFixture(named: "podcast-feed", extension: "xml")
        let feed = try PodcastFeedParser().parse(data)

        #expect(feed.title == "The Example Show")
        #expect(feed.author == "Example Studio")
        #expect(feed.languageCode == "en-SG")
        #expect(feed.episodes.count == 1)

        let episode = try #require(feed.episodes.first)
        #expect(episode.id == "episode-42")
        #expect(episode.title == "Small Histories")
        #expect(episode.summary == "Notes from the week.")
        #expect(episode.durationSeconds == 3723)
        #expect(episode.seasonNumber == 3)
        #expect(episode.episodeNumber == 42)
        #expect(episode.isExplicit == false)
    }

    @Test("RSS refresh sends conditional headers and handles not modified")
    func conditionalRefresh() async throws {
        let client = FeedFixtureHTTPClient(
            response: HTTPResponse(
                data: Data(),
                statusCode: 304,
                headers: ["ETag": "new-tag"]
            )
        )
        let feedClient = RSSPodcastFeedClient(httpClient: client)
        let result = try await feedClient.refresh(
            PodcastFeedRefreshRequest(
                feedURL: URL(string: "https://private.example.com/feed/token")!,
                eTag: "old-tag",
                lastModified: "Sat, 20 Jun 2026 09:00:00 GMT"
            )
        )

        guard case let .notModified(eTag, lastModified) = result else {
            Issue.record("Expected an unchanged feed")
            return
        }
        #expect(eTag == "new-tag")
        #expect(lastModified == "Sat, 20 Jun 2026 09:00:00 GMT")

        let request = try #require(await client.lastRequest)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "old-tag")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Sat, 20 Jun 2026 09:00:00 GMT")
    }

    @Test("RSS refresh refuses a file URL before networking")
    func refusesFileFeed() async {
        let client = FeedFixtureHTTPClient(response: HTTPResponse(data: Data(), statusCode: 200))
        let feedClient = RSSPodcastFeedClient(httpClient: client)
        await #expect(throws: RemoteHTTPURLError.invalid) {
            try await feedClient.refresh(
                PodcastFeedRefreshRequest(feedURL: URL(string: "file:///tmp/feed.xml")!)
            )
        }
        #expect(await client.lastRequest == nil)
    }
}

private actor FeedFixtureHTTPClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse {
        lastRequest = request
        return try response.validated(using: statusPolicy)
    }
}

private func podcastFixture(named name: String, extension fileExtension: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures", directoryHint: .isDirectory)
    return try Data(contentsOf: directory.appendingPathComponent(name).appendingPathExtension(fileExtension))
}
