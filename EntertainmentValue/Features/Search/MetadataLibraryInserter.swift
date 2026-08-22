import Foundation
import SwiftData

@MainActor
struct MetadataInsertionResult {
    let item: LibraryItem
    let wasInserted: Bool
}

@MainActor
struct MetadataLibraryInserter {
    private let context: ModelContext
    private let credentials: any CredentialStoring

    init(context: ModelContext, credentials: any CredentialStoring) {
        self.context = context
        self.credentials = credentials
    }

    func insert(
        result: MetadataSearchResult,
        details: MetadataItemDetails?,
        attribution: MetadataAttribution?,
        beforeSave: ((LibraryItem) throws -> (() -> Void)?)? = nil,
        at date: Date = .now
    ) async throws -> MetadataInsertionResult {
        let draft = MetadataDomainMapper.makeDraft(
            result: result,
            details: details,
            attribution: attribution
        )

        if let existing = try existingItem(for: draft.duplicateKey) {
            let undoPreparation = try beforeSave?(existing)
            do {
                if beforeSave != nil {
                    try context.save()
                }
            } catch {
                undoPreparation?()
                throw error
            }
            return MetadataInsertionResult(item: existing, wasInserted: false)
        }

        let itemID = UUID()
        let privateCredentialKey = try await storePrivateFeedIfNeeded(
            draft.podcastFeed,
            itemID: itemID
        )
        let item = LibraryItem(
            id: itemID,
            mediaKind: draft.mediaKind,
            title: persistedTitle(for: draft),
            subtitle: draft.subtitle,
            createdAt: date
        )
        item.summary = draft.summary
        item.creatorLine = creatorLine(for: draft)
        item.releaseYear = draft.releaseYear
        item.pageCount = draft.pageCount
        item.runtimeSeconds = draft.runtimeSeconds
        item.status = .planned
        item.metadataLastRefreshedAt = date
        item.updatedAt = date
        context.insert(item)

        var newlyCreatedFacets = [Facet]()
        var newlyCreatedMemberships = [ItemFacetMembership]()
        var undoPreparation: (() -> Void)?
        do {
            attachProviderReference(to: item, draft: draft, at: date)
            attachPodcastFeedReference(
                to: item,
                feed: draft.podcastFeed,
                privateCredentialKey: privateCredentialKey,
                at: date
            )
            attachArtwork(to: item, draft: draft, at: date)
            attachCredits(to: item, names: draft.creators, at: date)
            try attachFacets(
                to: item,
                facets: draft.facets,
                at: date,
                newlyCreatedFacets: &newlyCreatedFacets,
                newlyCreatedMemberships: &newlyCreatedMemberships
            )
            attachCreatedEvent(to: item, at: date)
            undoPreparation = try beforeSave?(item)
            try context.save()
            return MetadataInsertionResult(item: item, wasInserted: true)
        } catch {
            undoPreparation?()
            for membership in newlyCreatedMemberships {
                context.delete(membership)
            }
            context.delete(item)
            for facet in newlyCreatedFacets {
                context.delete(facet)
            }
            if let privateCredentialKey {
                try? await credentials.removeValue(for: privateCredentialKey)
            }
            throw error
        }
    }

    /// Applies provider details after the search result has already been saved.
    /// Scalar fields are only replaced while they still equal the search payload,
    /// so edits made while the request was in flight always win.
    func mergeDetails(
        into item: LibraryItem,
        searchResult: MetadataSearchResult,
        details: MetadataItemDetails,
        attribution: MetadataAttribution?,
        at date: Date = .now
    ) throws {
        // Do not roll unrelated pending UI edits into this background save.
        guard !context.hasChanges, item.trashedAt == nil else { return }

        let baseline = MetadataDomainMapper.makeDraft(
            result: searchResult,
            attribution: attribution
        )
        let enriched = MetadataDomainMapper.makeDraft(
            result: searchResult,
            details: details,
            attribution: attribution
        )
        guard let providerReference = (item.externalReferences ?? []).first(where: {
            baseline.duplicateKey.matches(
                providerRaw: $0.providerRaw,
                recordKindRaw: $0.recordKindRaw,
                externalID: $0.externalID
            )
        }) else { return }

        let baselineTitle = persistedTitle(for: baseline)
        let enrichedTitle = persistedTitle(for: enriched)
        let baselineCreatorLine = creatorLine(for: baseline)
        let enrichedCreatorLine = creatorLine(for: enriched)
        let canMergeCreators = item.creatorLine == baselineCreatorLine

        let relevantMemberships = (item.facetMemberships ?? []).filter {
            $0.facet?.kind == .genre || $0.facet?.kind == .platform
        }
        let baselineFacetKeys = Set(baseline.facets.map(facetKey))
        let currentFacetKeys = Set(relevantMemberships.compactMap { membership in
            membership.facet.map { facetKey(kind: $0.kind, name: $0.name) }
        })
        let canMergeFacets = currentFacetKeys == baselineFacetKeys &&
            relevantMemberships.allSatisfy {
                $0.sourceRaw == RecordSource.metadataProvider.rawValue
            }
        let missingFacets = canMergeFacets
            ? enriched.facets.filter { !currentFacetKeys.contains(facetKey($0)) }
            : []

        do {
            if item.title == baselineTitle, enrichedTitle != baselineTitle {
                let keepSortTitle = item.sortTitle != baselineTitle
                let previousSortTitle = item.sortTitle
                item.setTitle(enrichedTitle)
                if keepSortTitle {
                    item.sortTitle = previousSortTitle
                }
            }
            if item.subtitle == baseline.subtitle, enriched.subtitle != baseline.subtitle {
                item.subtitle = enriched.subtitle
            }
            if item.summary == baseline.summary, enriched.summary != baseline.summary {
                item.summary = enriched.summary
            }
            if canMergeCreators, enrichedCreatorLine != baselineCreatorLine {
                item.creatorLine = enrichedCreatorLine
            }
            if item.releaseYear == baseline.releaseYear,
               enriched.releaseYear != baseline.releaseYear
            {
                item.releaseYear = enriched.releaseYear
            }
            if item.pageCount == baseline.pageCount, enriched.pageCount != baseline.pageCount {
                item.pageCount = enriched.pageCount
            }
            if item.runtimeSeconds == baseline.runtimeSeconds,
               enriched.runtimeSeconds != baseline.runtimeSeconds
            {
                item.runtimeSeconds = enriched.runtimeSeconds
            }

            if canMergeCreators {
                attachCredits(to: item, names: enriched.creators, at: date)
            }
            if !missingFacets.isEmpty {
                var newlyCreatedFacets = [Facet]()
                var newlyCreatedMemberships = [ItemFacetMembership]()
                try attachFacets(
                    to: item,
                    facets: missingFacets,
                    at: date,
                    newlyCreatedFacets: &newlyCreatedFacets,
                    newlyCreatedMemberships: &newlyCreatedMemberships
                )
            }
            mergeArtwork(
                for: item,
                baseline: baseline,
                enriched: enriched,
                at: date
            )

            let baselineSourceURL = baseline.sourceURL?.absoluteString
            let enrichedSourceURL = enriched.sourceURL?.absoluteString
            if providerReference.canonicalURLString == baselineSourceURL,
               enrichedSourceURL != baselineSourceURL
            {
                providerReference.canonicalURLString = enrichedSourceURL
            }
            providerReference.lastFetchedAt = date
            providerReference.attributionText = attribution?.label
            providerReference.attributionURLString = attribution?.url.absoluteString
            providerReference.updatedAt = date
            item.metadataLastRefreshedAt = date
            item.updatedAt = date
            try context.save()
        } catch {
            // The context was clean on entry and this synchronous MainActor
            // transaction cannot interleave with another mutation.
            context.rollback()
            throw error
        }
    }

    private func existingItem(for key: MetadataDuplicateKey) throws -> LibraryItem? {
        let providerRaw = key.providerRaw
        let descriptor = FetchDescriptor<ExternalReference>(
            predicate: #Predicate { reference in
                reference.providerRaw == providerRaw
            }
        )
        return try context.fetch(descriptor)
            .first {
                key.matches(
                    providerRaw: $0.providerRaw,
                    recordKindRaw: $0.recordKindRaw,
                    externalID: $0.externalID
                )
            }?
            .ownerItem
    }

    private func storePrivateFeedIfNeeded(
        _ feed: PodcastFeedDraft?,
        itemID: UUID
    ) async throws -> String? {
        guard let feed, feed.privacy == .privateCredential else { return nil }
        let key = "podcast-feed.\(itemID.uuidString.lowercased())"
        try await credentials.set(feed.url.absoluteString, for: key)
        return key
    }

    private func attachProviderReference(
        to item: LibraryItem,
        draft: MetadataItemDraft,
        at date: Date
    ) {
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: draft.duplicateKey.providerRaw,
            recordKindRaw: draft.duplicateKey.recordKindRaw,
            externalID: draft.duplicateKey.externalID,
            canonicalURLString: draft.sourceURL?.absoluteString,
            createdAt: date
        )
        reference.lastFetchedAt = date
        reference.attributionText = draft.attribution?.label
        reference.attributionURLString = draft.attribution?.url.absoluteString
        context.insert(reference)
        if !(item.externalReferences ?? []).contains(where: { $0.id == reference.id }) {
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }
    }

    private func attachPodcastFeedReference(
        to item: LibraryItem,
        feed: PodcastFeedDraft?,
        privateCredentialKey: String?,
        at date: Date
    ) {
        guard let feed else { return }
        let isPrivate = feed.privacy == .privateCredential
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: MetadataProviderID.rss.rawValue,
            recordKindRaw: "podcastFeed",
            externalID: isPrivate ? "private.\(item.id.uuidString.lowercased())" : feed.opaqueID,
            canonicalURLString: isPrivate ? nil : feed.url.absoluteString,
            createdAt: date
        )
        reference.isActiveFeed = true
        reference.isPrivateFeed = isPrivate
        reference.credentialKeychainID = privateCredentialKey
        context.insert(reference)
        if !(item.externalReferences ?? []).contains(where: { $0.id == reference.id }) {
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }
    }

    private func attachArtwork(
        to item: LibraryItem,
        draft: MetadataItemDraft,
        at date: Date
    ) {
        guard let url = draft.artworkURL else { return }
        let artwork = ArtworkAsset(
            ownerItem: item,
            kind: .providerRemote,
            remoteURLString: url.absoluteString,
            createdAt: date
        )
        artwork.cacheKey = ArtworkRepository.hash(url.absoluteString)
        artwork.providerRaw = draft.provider.rawValue
        artwork.attributionText = draft.attribution?.label
        artwork.attributionURLString = draft.attribution?.url.absoluteString
        if draft.mediaKind == .podcast {
            artwork.aspectRatio = 1
        }
        context.insert(artwork)
        if !(item.artworkAssets ?? []).contains(where: { $0.id == artwork.id }) {
            item.artworkAssets = (item.artworkAssets ?? []) + [artwork]
        }
        item.preferredArtworkID = artwork.id
    }

    private func attachCredits(to item: LibraryItem, names: [String], at date: Date) {
        let existingCredits = item.credits ?? []
        var knownNames = Set(existingCredits.map { LibraryItem.normalize($0.name) })
        let missingNames = names.filter { name in
            knownNames.insert(LibraryItem.normalize(name)).inserted
        }
        let firstSortOrder = (existingCredits.map(\.sortOrder).max() ?? -1) + 1
        let credits = missingNames.enumerated().map { index, name in
            Credit(
                ownerItem: item,
                name: name,
                roleRaw: "creator",
                sortOrder: firstSortOrder + index,
                createdAt: date
            )
        }
        for credit in credits {
            context.insert(credit)
        }
        let missingCredits = credits.filter { credit in
            !(item.credits ?? []).contains(where: { $0.id == credit.id })
        }
        if !missingCredits.isEmpty {
            item.credits = (item.credits ?? []) + missingCredits
        }
    }

    private func attachFacets(
        to item: LibraryItem,
        facets: [MetadataFacetDraft],
        at date: Date,
        newlyCreatedFacets: inout [Facet],
        newlyCreatedMemberships: inout [ItemFacetMembership]
    ) throws {
        var memberships = [ItemFacetMembership]()
        let firstSortOrder = ((item.facetMemberships ?? []).map(\.sortOrder).max() ?? -1) + 1

        for (index, facetDraft) in facets.enumerated() {
            let kindRaw = facetDraft.kind.rawValue
            let normalizedName = LibraryItem.normalize(facetDraft.name)
            var descriptor = FetchDescriptor<Facet>(
                predicate: #Predicate { facet in
                    facet.kindRaw == kindRaw && facet.normalizedName == normalizedName
                }
            )
            descriptor.fetchLimit = 1

            let facet: Facet
            if let existing = try context.fetch(descriptor).first {
                facet = existing
            } else {
                facet = Facet(kind: facetDraft.kind, name: facetDraft.name, createdAt: date)
                context.insert(facet)
                newlyCreatedFacets.append(facet)
            }

            let membership = ItemFacetMembership(
                item: item,
                facet: facet,
                source: .metadataProvider,
                sortOrder: firstSortOrder + index,
                createdAt: date
            )
            context.insert(membership)
            memberships.append(membership)
            newlyCreatedMemberships.append(membership)
            if !(facet.memberships ?? []).contains(where: { $0.id == membership.id }) {
                facet.memberships = (facet.memberships ?? []) + [membership]
            }
        }

        let missingMemberships = memberships.filter { membership in
            !(item.facetMemberships ?? []).contains(where: { $0.id == membership.id })
        }
        if !missingMemberships.isEmpty {
            item.facetMemberships = (item.facetMemberships ?? []) + missingMemberships
        }
    }

    private func mergeArtwork(
        for item: LibraryItem,
        baseline: MetadataItemDraft,
        enriched: MetadataItemDraft,
        at date: Date
    ) {
        let baselineURL = baseline.artworkURL?.absoluteString
        guard let enrichedURL = enriched.artworkURL?.absoluteString,
              enrichedURL != baselineURL
        else { return }

        if let preferredArtworkID = item.preferredArtworkID,
           let artwork = (item.artworkAssets ?? []).first(where: { $0.id == preferredArtworkID })
        {
            guard artwork.kind == .providerRemote,
                  artwork.providerRaw == baseline.provider.rawValue,
                  artwork.remoteURLString == baselineURL
            else { return }
            artwork.remoteURLString = enrichedURL
            artwork.cacheKey = ArtworkRepository.hash(enrichedURL)
            artwork.attributionText = enriched.attribution?.label
            artwork.attributionURLString = enriched.attribution?.url.absoluteString
            artwork.updatedAt = date
        } else if baselineURL == nil {
            attachArtwork(to: item, draft: enriched, at: date)
        }
    }

    private func persistedTitle(for draft: MetadataItemDraft) -> String {
        draft.title.isEmpty ? "Untitled" : draft.title
    }

    private func creatorLine(for draft: MetadataItemDraft) -> String? {
        draft.creators.isEmpty ? nil : draft.creators.joined(separator: ", ")
    }

    private func facetKey(_ draft: MetadataFacetDraft) -> String {
        facetKey(kind: draft.kind, name: draft.name)
    }

    private func facetKey(kind: FacetKind, name: String) -> String {
        "\(kind.rawValue):\(LibraryItem.normalize(name))"
    }

    private func attachCreatedEvent(to item: LibraryItem, at date: Date) {
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .created,
            toStatus: .planned,
            effectiveAt: date,
            source: .metadataProvider
        )
        context.insert(event)
        if !(item.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            item.activityEvents = (item.activityEvents ?? []) + [event]
        }
    }
}
