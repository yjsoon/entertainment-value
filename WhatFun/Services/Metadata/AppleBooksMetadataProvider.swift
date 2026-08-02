import Foundation

nonisolated struct AppleBooksMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.appleBooks
    let supportedMediaTypes: Set<MetadataMediaType> = [.book]
    let attribution: MetadataAttribution? = nil
    let availability = MetadataProviderAvailability.available

    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func featured(_ request: MetadataDiscoveryRequest) async throws -> MetadataSearchPage {
        try validate(request, availability: availability)
        throw MetadataProviderError.invalidRequest(provider: id)
    }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        try validate(request)
        let queryItems = [
            URLQueryItem(name: "term", value: request.trimmedQuery),
            URLQueryItem(name: "media", value: "ebook"),
            URLQueryItem(name: "entity", value: "ebook"),
            URLQueryItem(name: "limit", value: String(request.limit)),
            URLQueryItem(
                name: "country",
                value: request.countryCode?.metadataNilIfBlank ?? "US"
            ),
        ]

        let response = try await httpClient.send(
            makeRequest(path: "/search", queryItems: queryItems)
        )
        let payload = try decode(AppleBooksResponse.self, from: response.data)
        let mapped = payload.results.compactMap(makeResult)
        let results = TitleCreatorSearchRelevance.ranked(mapped, for: request.trimmedQuery)
        return MetadataSearchPage(
            results: results,
            page: 1,
            totalPages: nil,
            totalResults: nil
        )
    }

    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        try validateOwnership(of: result)
        return MetadataItemDetails(
            result: result,
            websiteURL: nil,
            facts: [],
            artworkURLs: [result.coverImageURL].compactMap(\.self)
        )
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeResult(_ item: AppleBooksItem) -> MetadataSearchResult? {
        guard item.kind == "ebook",
              let trackID = item.trackID,
              let title = item.trackName?.metadataNilIfBlank
        else { return nil }
        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: String(trackID)),
            mediaType: .book,
            title: title,
            subtitle: item.artistName?.metadataNilIfBlank,
            creators: creators(from: item),
            overview: nil,
            releaseYear: metadataYear(from: item.releaseDate),
            coverImageURL: artworkURL(item.artworkURL100, size: 600),
            thumbnailImageURL: artworkURL(item.artworkURL100, size: 100),
            sourceURL: nil,
            feedURL: nil,
            genres: (item.genres ?? []).filter { $0 != "Books" }.metadataDeduplicated,
            pageCount: nil,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )
    }

    private func creators(from item: AppleBooksItem) -> [String] {
        guard let byline = item.artistName?.metadataNilIfBlank else { return [] }
        let artistCount = item.artistIDs?.count ?? 0
        if artistCount <= 1 { return [byline] }

        let components = byline
            .replacingOccurrences(of: " & ", with: ",")
            .split(separator: ",")
            .map(String.init)
            .metadataDeduplicated
        return components.count == artistCount ? components : []
    }

    private func artworkURL(_ value: String?, size: Int) -> URL? {
        guard let value = value?.metadataNilIfBlank else { return nil }
        let resized = value
            .replacingOccurrences(of: "/100x100bb.", with: "/\(size)x\(size)bb.")
            .replacingOccurrences(of: "/60x60bb.", with: "/\(size)x\(size)bb.")
        return URL(string: resized)
    }
}

private nonisolated struct AppleBooksResponse: Decodable, Sendable {
    let results: [AppleBooksItem]
}

private nonisolated struct AppleBooksItem: Decodable, Sendable {
    let trackID: Int64?
    let trackName: String?
    let artistName: String?
    let artistIDs: [Int64]?
    let kind: String?
    let releaseDate: String?
    let artworkURL100: String?
    let genres: [String]?

    enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case trackName, artistName, kind, releaseDate, genres
        case artistIDs = "artistIds"
        case artworkURL100 = "artworkUrl100"
    }
}
