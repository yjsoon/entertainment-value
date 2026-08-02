import Foundation

nonisolated struct OpenLibraryMetadataProvider: MetadataProvider {
    let id = MetadataProviderID.openLibrary
    let supportedMediaTypes: Set<MetadataMediaType> = [.book, .comic]
    let attribution: MetadataAttribution? = MetadataAttribution(
        label: "Data from Open Library",
        notice: nil,
        url: URL(string: "https://openlibrary.org")!
    )
    let availability = MetadataProviderAvailability.available

    private let httpClient: any HTTPClient
    private let applicationName: String
    private let contactEmail: String?

    init(
        httpClient: any HTTPClient,
        applicationName: String,
        contactEmail: String?
    ) {
        self.httpClient = httpClient
        self.applicationName = applicationName.metadataNilIfBlank ?? "WhatFun"
        if let contactEmail = contactEmail?.metadataNilIfBlank,
           !contactEmail.hasPrefix("YOUR_")
        {
            self.contactEmail = contactEmail
        } else {
            self.contactEmail = nil
        }
    }

    func featured(_ request: MetadataDiscoveryRequest) async throws -> MetadataSearchPage {
        try validate(request, availability: availability)
        var queryItems = [
            URLQueryItem(name: "q", value: "trending_z_score:{0 TO *]"),
            URLQueryItem(name: "sort", value: "trending"),
            URLQueryItem(name: "page", value: String(request.page)),
            URLQueryItem(name: "limit", value: String(request.limit)),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,subject"
            ),
        ]
        if request.mediaType == .comic {
            queryItems.append(URLQueryItem(name: "subject", value: "comics"))
        }
        if let languageCode = request.languageCode?.metadataNilIfBlank {
            queryItems.append(URLQueryItem(name: "lang", value: languageCode))
        }

        return try await loadPage(
            queryItems: queryItems,
            mediaType: request.mediaType,
            page: request.page,
            limit: request.limit
        )
    }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage {
        try validate(request)
        var queryItems = [
            URLQueryItem(name: "q", value: request.trimmedQuery),
            URLQueryItem(name: "page", value: String(request.page)),
            URLQueryItem(name: "limit", value: String(request.limit)),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,subject"
            ),
        ]
        if request.mediaType == .comic {
            // Open Library is intentionally shared by books and comics. This
            // favors series and collected editions rather than issue-level data.
            queryItems.append(URLQueryItem(name: "subject", value: "comics"))
        }
        if let languageCode = request.languageCode?.metadataNilIfBlank {
            queryItems.append(URLQueryItem(name: "lang", value: languageCode))
        }

        return try await loadPage(
            queryItems: queryItems,
            mediaType: request.mediaType,
            page: request.page,
            limit: request.limit,
            relevanceQuery: request.trimmedQuery
        )
    }

    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails {
        try validateOwnership(of: result)
        let workID = result.id.externalID
            .replacingOccurrences(of: "/works/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let response = try await httpClient.send(
            makeRequest(path: "/works/\(workID).json", queryItems: [])
        )
        let payload = try decode(OpenLibraryWorkResponse.self, from: response.data)
        let coverID = payload.covers?.first
        let allGenres = payload.subjects ?? result.genres
        let genres = Array(allGenres[0 ..< min(20, allGenres.count)]).metadataDeduplicated
        let enrichedResult = MetadataSearchResult(
            id: result.id,
            mediaType: result.mediaType,
            title: payload.title?.metadataNilIfBlank ?? result.title,
            subtitle: result.subtitle,
            creators: result.creators,
            overview: payload.description?.value.metadataNilIfBlank ?? result.overview,
            releaseYear: result.releaseYear,
            coverImageURL: coverID.flatMap { coverURL(id: $0, size: "L") } ?? result.coverImageURL,
            thumbnailImageURL: coverID.flatMap { coverURL(id: $0, size: "M") } ?? result.thumbnailImageURL,
            sourceURL: URL(string: "https://openlibrary.org/works/\(workID)"),
            feedURL: nil,
            genres: genres,
            pageCount: result.pageCount,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )

        var facts = [MetadataFact]()
        if let pages = result.pageCount {
            facts.append(MetadataFact(label: "Pages", value: String(pages)))
        }

        return MetadataItemDetails(
            result: enrichedResult,
            websiteURL: enrichedResult.sourceURL,
            facts: facts,
            artworkURLs: [enrichedResult.coverImageURL].compactMap(\.self)
        )
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openlibrary.org"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw MetadataProviderError.invalidRequest(provider: id)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let identity = contactEmail.map { "\(applicationName)/1.0 (mailto:\($0))" }
            ?? "\(applicationName)/1.0"
        request.setValue(identity, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func loadPage(
        queryItems: [URLQueryItem],
        mediaType: MetadataMediaType,
        page: Int,
        limit: Int,
        relevanceQuery: String? = nil
    ) async throws -> MetadataSearchPage {
        let response = try await httpClient.send(
            makeRequest(path: "/search.json", queryItems: queryItems)
        )
        let payload = try decode(OpenLibrarySearchResponse.self, from: response.data)
        let mappedResults = payload.docs.compactMap { makeResult(from: $0, mediaType: mediaType) }
        if let relevanceQuery {
            let results = OpenLibrarySearchRelevance.ranked(
                mappedResults,
                for: relevanceQuery
            )
            return MetadataSearchPage(
                results: results,
                page: page,
                totalPages: nil,
                totalResults: nil
            )
        }

        let totalPages = max(1, Int(ceil(Double(payload.numFound) / Double(limit))))
        return MetadataSearchPage(
            results: mappedResults,
            page: page,
            totalPages: totalPages,
            totalResults: payload.numFound
        )
    }

    private func makeResult(
        from document: OpenLibrarySearchDocument,
        mediaType: MetadataMediaType
    ) -> MetadataSearchResult? {
        guard let key = document.key?.metadataNilIfBlank,
              let title = document.title?.metadataNilIfBlank
        else { return nil }
        let workID = key.replacingOccurrences(of: "/works/", with: "")
        return MetadataSearchResult(
            id: MetadataResultID(provider: id, externalID: workID),
            mediaType: mediaType,
            title: title,
            subtitle: nil,
            creators: (document.authorName ?? []).metadataDeduplicated,
            overview: nil,
            releaseYear: document.firstPublishYear,
            coverImageURL: document.coverID.flatMap { coverURL(id: $0, size: "L") },
            thumbnailImageURL: document.coverID.flatMap { coverURL(id: $0, size: "M") },
            sourceURL: URL(string: "https://openlibrary.org/works/\(workID)"),
            feedURL: nil,
            genres: limitedSubjects(document.subjects ?? []),
            pageCount: document.pageCount,
            durationMinutes: nil,
            seasonCount: nil,
            episodeCount: nil,
            platformNames: []
        )
    }

    private func coverURL(id: Int, size: String) -> URL? {
        URL(string: "https://covers.openlibrary.org/b/id/\(id)-\(size).jpg")
    }

    private func limitedSubjects(_ subjects: [String]) -> [String] {
        Array(subjects[0 ..< min(20, subjects.count)]).metadataDeduplicated
    }
}

nonisolated enum OpenLibrarySearchRelevance {
    static func ranked(
        _ results: [MetadataSearchResult],
        for query: String
    ) -> [MetadataSearchResult] {
        var matches = [(rank: Int, index: Int, result: MetadataSearchResult)]()
        for (index, result) in results.enumerated() {
            guard let resultRank = rank(result, for: query) else { continue }
            matches.append((rank: resultRank, index: index, result: result))
        }
        matches.sort { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
        }
        return matches.map(\.result)
    }

    static func preferredCreator(
        in result: MetadataSearchResult,
        for query: String
    ) -> String? {
        var best: (rank: Int, creator: String)?
        for creator in result.creators {
            guard let creatorRank = rank(title: result.title, creators: [creator], for: query) else {
                continue
            }
            if best == nil || creatorRank < best!.rank {
                best = (rank: creatorRank, creator: creator)
            }
        }
        return best?.creator ?? result.creators.first
    }

    private static func rank(_ result: MetadataSearchResult, for query: String) -> Int? {
        rank(title: result.title, creators: result.creators, for: query)
    }

    private static func rank(title: String, creators: [String], for query: String) -> Int? {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return nil }
        let titleTokens = tokens(title)
        let creatorTokens = creators.map(tokens)
        let individualFields = [titleTokens] + creatorTokens

        if individualFields.contains(queryTokens) { return 0 }
        if individualFields.contains(where: { containsContiguous(queryTokens, in: $0) }) { return 1 }
        if individualFields.contains(where: { contains(queryTokens, in: $0) }) { return 2 }
        if creatorTokens.contains(where: { isMixedMatch(queryTokens, title: titleTokens, creator: $0) }) {
            return 3
        }
        if individualFields.contains(where: { contains(queryTokens, in: $0, allowPrefixes: true) }) {
            return 4
        }
        if creatorTokens.contains(where: {
            isMixedMatch(queryTokens, title: titleTokens, creator: $0, allowPrefixes: true)
        }) {
            return 5
        }
        if queryTokens.count >= 2,
           individualFields.contains(where: { containsWithOneTypo(queryTokens, in: $0) })
        {
            return 6
        }
        return nil
    }

    private static func tokens(_ value: String) -> [String] {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = [String]()
        var token = ""
        for scalar in folded.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                token.unicodeScalars.append(scalar)
            } else if !token.isEmpty {
                result.append(token)
                token = ""
            }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }

    private static func containsContiguous(_ query: [String], in candidate: [String]) -> Bool {
        guard query.count <= candidate.count else { return false }
        return candidate.indices.contains { start in
            let end = start + query.count
            return end <= candidate.count && Array(candidate[start ..< end]) == query
        }
    }

    private static func contains(
        _ query: [String],
        in candidate: [String],
        allowPrefixes: Bool = false
    ) -> Bool {
        guard query.count <= candidate.count else { return false }
        var available = Array(candidate.indices)
        var unmatched = [String]()

        for queryToken in query {
            if let position = available.firstIndex(where: { candidate[$0] == queryToken }) {
                available.remove(at: position)
            } else {
                unmatched.append(queryToken)
            }
        }
        guard allowPrefixes else { return unmatched.isEmpty }
        for queryToken in unmatched.sorted(by: { $0.count > $1.count }) {
            guard queryToken.count >= 2,
                  let position = available.firstIndex(where: { candidate[$0].hasPrefix(queryToken) })
            else { return false }
            available.remove(at: position)
        }
        return true
    }

    private static func isMixedMatch(
        _ query: [String],
        title: [String],
        creator: [String],
        allowPrefixes: Bool = false
    ) -> Bool {
        guard query.contains(where: { tokenMatches($0, in: title, allowPrefixes: allowPrefixes) }),
              query.contains(where: { tokenMatches($0, in: creator, allowPrefixes: allowPrefixes) })
        else { return false }
        return contains(query, in: title + creator, allowPrefixes: allowPrefixes)
    }

    private static func tokenMatches(
        _ queryToken: String,
        in candidate: [String],
        allowPrefixes: Bool
    ) -> Bool {
        candidate.contains(queryToken) ||
            (allowPrefixes && queryToken.count >= 2 && candidate.contains { $0.hasPrefix(queryToken) })
    }

    private static func containsWithOneTypo(_ query: [String], in candidate: [String]) -> Bool {
        guard query.count <= candidate.count else { return false }
        var available = Array(candidate.indices)
        var unmatched = [String]()
        for queryToken in query {
            if let position = available.firstIndex(where: { candidate[$0] == queryToken }) {
                available.remove(at: position)
            } else {
                unmatched.append(queryToken)
            }
        }
        guard unmatched.count == 1, let queryToken = unmatched.first else {
            return false
        }
        return available.contains {
            max(queryToken.count, candidate[$0].count) >= 5 &&
                isOneEditApart(queryToken, candidate[$0])
        }
    }

    private static func isOneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= 1, left != right else { return false }

        if left.count == right.count {
            let differences = left.indices.filter { left[$0] != right[$0] }
            if differences.count == 1 { return true }
            return differences.count == 2 &&
                differences[1] == differences[0] + 1 &&
                left[differences[0]] == right[differences[1]] &&
                left[differences[1]] == right[differences[0]]
        }

        let shorter = left.count < right.count ? left : right
        let longer = left.count < right.count ? right : left
        var shortIndex = 0
        var longIndex = 0
        var skipped = false
        while shortIndex < shorter.count, longIndex < longer.count {
            if shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
                longIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
                longIndex += 1
            }
        }
        return true
    }
}

private nonisolated struct OpenLibrarySearchResponse: Decodable, Sendable {
    let numFound: Int
    let docs: [OpenLibrarySearchDocument]

    enum CodingKeys: String, CodingKey {
        case numFound
        case docs
    }
}

private nonisolated struct OpenLibrarySearchDocument: Decodable, Sendable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverID: Int?
    let pageCount: Int?
    let subjects: [String]?

    enum CodingKeys: String, CodingKey {
        case key, title, subject
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverID = "cover_i"
        case pageCount = "number_of_pages_median"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        authorName = try container.decodeIfPresent([String].self, forKey: .authorName)
        firstPublishYear = try container.decodeIfPresent(Int.self, forKey: .firstPublishYear)
        coverID = try container.decodeIfPresent(Int.self, forKey: .coverID)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        subjects = try container.decodeIfPresent([String].self, forKey: .subject)
    }
}

private nonisolated struct OpenLibraryWorkResponse: Decodable, Sendable {
    let title: String?
    let description: OpenLibraryDescription?
    let subjects: [String]?
    let covers: [Int]?
}

private nonisolated struct OpenLibraryDescription: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            value = string
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }
}
