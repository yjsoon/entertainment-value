import Foundation

nonisolated enum RemoteHTTPURL {
    static func parse(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return parse(url)
    }

    static func parse(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(),
              !host.isEmpty
        else { return nil }
        return url
    }

    /// Artwork and public source links must not carry embedded credentials.
    /// Those would land in the shared URL cache.
    static func parsePublic(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return parsePublic(url)
    }

    static func parsePublic(_ url: URL) -> URL? {
        guard let url = parse(url), url.user == nil, url.password == nil else { return nil }
        return url
    }
}

nonisolated enum RemoteHTTPURLError: Error, Equatable, LocalizedError {
    case invalid

    var errorDescription: String? {
        "Use an HTTP or HTTPS address with a host."
    }
}
