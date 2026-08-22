import Foundation
import Testing
@testable import EntertainmentValue

@Suite("Remote HTTP URLs")
struct RemoteHTTPURLTests {
    @Test("HTTP and HTTPS URLs with a host are accepted")
    func acceptsHTTPURLs() {
        #expect(RemoteHTTPURL.parse("https://example.com/feed.xml")?.host() == "example.com")
        #expect(RemoteHTTPURL.parse("http://192.168.1.10:8000/rss")?.host() == "192.168.1.10")
        #expect(RemoteHTTPURL.parse("HTTPS://covers.example/a.jpg") != nil)
        #expect(RemoteHTTPURL.parse("  https://covers.example/a.jpg  ")?.path == "/a.jpg")
    }

    @Test("Schemes that are not HTTP are rejected")
    func rejectsNonHTTPSchemes() {
        #expect(RemoteHTTPURL.parse("file:///tmp/secret.png") == nil)
        #expect(RemoteHTTPURL.parse("data:image/png;base64,aaaa") == nil)
        #expect(RemoteHTTPURL.parse("javascript:alert(1)") == nil)
        #expect(RemoteHTTPURL.parse("ftp://example.com/cover.jpg") == nil)
        #expect(RemoteHTTPURL.parse("feed://example.com/rss") == nil)
        #expect(RemoteHTTPURL.parse("/just/a/path") == nil)
        #expect(RemoteHTTPURL.parse("example.com/feed") == nil)
        #expect(RemoteHTTPURL.parse("") == nil)
        #expect(RemoteHTTPURL.parse("https://") == nil)
    }

    @Test("Public parses reject embedded credentials")
    func publicParseRejectsUserInfo() {
        let secret = URL(string: "https://user:pass@cdn.example/cover.jpg")!
        #expect(RemoteHTTPURL.parse(secret) == secret)
        #expect(RemoteHTTPURL.parsePublic(secret) == nil)
        #expect(RemoteHTTPURL.parsePublic("https://cdn.example/cover.jpg")?.host() == "cdn.example")
    }

    @Test("Provider URL parsing uses the public HTTP rule")
    func metadataURLUsesPublicRule() {
        #expect(metadataURL("https://image.tmdb.org/t/p/w500/x.jpg")?.host() == "image.tmdb.org")
        #expect(metadataURL("file:///tmp/cover.jpg") == nil)
        #expect(metadataURL("https://user:pass@cdn.example/x.jpg") == nil)
    }

    @Test("Feed URL parsing allows userinfo and rejects other schemes")
    func metadataFeedURLUsesFeedRule() {
        #expect(metadataFeedURL("https://user:pass@feeds.example/show.xml")?.host() == "feeds.example")
        #expect(metadataFeedURL("https://feeds.example/show.xml")?.host() == "feeds.example")
        #expect(metadataFeedURL("file:///tmp/feed.xml") == nil)
    }
}
