import Foundation

enum AppLimits {
    enum MoreMenus {
        static let limit: Int = 20
    }

    enum GlobalActivity {
        static let limit: Int = 25
        static let previewLimit: Int = 20
    }

    enum GlobalCommits {
        static let limit: Int = 25
        static let previewLimit: Int = 5
    }

    enum RepoActivity {
        static let limit: Int = 25
        static let previewLimit: Int = 5
    }

    enum RecentLists {
        static let limit: Int = 20
        static let previewLimit: Int = 5
        static let cacheTTL: TimeInterval = 90
        static let cacheEntries: Int = 128
        static let loadTimeout: TimeInterval = 12
        static let issueLabelChipLimit: Int = 6
    }

    enum GitHubReferenceMonitor {
        static let minimumBareDigits = 1
        static let queryLimit = 8
        static let cacheLookupLimit = 20
        static let liveLookupLimit = 80
    }

    enum RepoCommits {
        static let previewLimit: Int = 5
        static let moreLimit: Int = 25
        static let totalLimit: Int = previewLimit + moreLimit
    }

    enum Changelog {
        static let maxCharacters: Int = 4000
        static let maxLines: Int = 80
        static let cacheTTL: TimeInterval = 10 * 60
        static let cacheEntries: Int = 128
    }

    enum LocalRepo {
        static let mainMenuDirtyFileLimit: Int = 3
        static let submenuDirtyFileLimit: Int = 10
        static let discoveryCacheTTL: TimeInterval = 10 * 60
        static let statusCacheTTL: TimeInterval = 2 * 60
        static let snapshotConcurrencyLimit: Int = 6
    }

    enum Autocomplete {
        static let addRepoRecentLimit: Int = 10
        static let settingsSearchLimit: Int = 10
    }
}
