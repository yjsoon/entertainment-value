import Foundation
import Observation

/// Long-lived services shared through the environment.
@Observable
final class AppServices {
    let metadata: MetadataServiceBundle
    let artwork: (any ArtworkLoading)?

    init(metadata: MetadataServiceBundle, artwork: (any ArtworkLoading)?) {
        self.metadata = metadata
        self.artwork = artwork
    }

    static func live() -> AppServices {
        let artwork: ArtworkRepository? = try? ArtworkRepository(location: ArtworkCacheLocation.applicationSupport())
        return AppServices(metadata: MetadataServiceFactory.live(), artwork: artwork)
    }
}
