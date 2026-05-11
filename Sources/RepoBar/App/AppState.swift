import Algorithms
import Foundation
import Observation
import RepoBarCore

// MARK: - AppState container

@MainActor
@Observable
final class AppState {
    var session = Session()
    let auth = OAuthCoordinator()
    let patAuth = PATAuthenticator()
    let github = GitHubClient()
    let refreshScheduler = RefreshScheduler()
    let settingsStore = SettingsStore()
    let localRepoManager = LocalRepoManager()
    let menuRefreshInterval: TimeInterval = 30
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    var menuRefreshTask: Task<Void, Never>?
    private var gitHubReferenceMonitor: GitHubReferenceMonitor?
    private var gitHubReferenceResolutionID = UUID()
    var refreshTaskToken = UUID()
    let hydrateConcurrencyLimit = 4
    var prefetchTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 300
    let menuRefreshDebounceInterval: TimeInterval = 1
    var lastMenuRefreshRequest: Date?

    // Default GitHub App values for convenience login from the main window.
    let defaultClientID = RepoBarAuthDefaults.clientID
    let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    let defaultLoopbackPort = RepoBarAuthDefaults.loopbackPort
    let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init() {
        self.session.settings = self.settingsStore.load()
        self.reloadRateLimitCacheSummary()
        RepoBarLogging.bootstrapIfNeeded()
        RepoBarLogging.configure(
            verbosity: self.session.settings.loggingVerbosity,
            fileLoggingEnabled: self.session.settings.fileLoggingEnabled
        )
        let storedOAuthTokens = self.auth.loadTokens()
        let storedPAT = self.patAuth.loadPAT()
        self.session.hasStoredTokens = (storedOAuthTokens != nil) || (storedPAT != nil)
        let inferredAuthMethod: AuthMethod = storedPAT != nil ? .pat : .oauth
        if self.session.settings.authMethod != inferredAuthMethod {
            self.session.settings.authMethod = inferredAuthMethod
            self.settingsStore.save(self.session.settings)
        }
        // Capture tokenStore separately for Sendable compliance
        let tokenStore = TokenStore.shared
        Task {
            await self.github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
                guard let self else { return nil }

                let authMethod = await MainActor.run { self.session.settings.authMethod }
                if authMethod == .pat {
                    if let pat = try? tokenStore.loadPAT() {
                        return OAuthTokens(accessToken: pat, refreshToken: "", expiresAt: nil)
                    }
                }
                return try? await self.auth.refreshIfNeeded()
            }
        }
        self.tokenRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if self.session.settings.authMethod == .oauth, self.auth.loadTokens() != nil {
                    _ = try? await self.auth.refreshIfNeeded()
                }
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
            }
        }
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            self?.requestRefresh()
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.refreshRateLimitDisplayState()
        }
        self.updateGitHubReferenceMonitor()
    }

    struct GlobalActivityResult {
        let events: [ActivityEvent]
        let commits: [RepoCommitSummary]
        let error: String?
        let commitError: String?
    }

    func diagnostics() async -> DiagnosticsSummary {
        await self.refreshRateLimitDisplayState()
        return self.session.rateLimitDiagnostics
    }

    func refreshRateLimitDisplayState() async {
        _ = try? await self.github.refreshRateLimitResources()
        let diagnostics = await self.github.diagnostics()
        let cacheSummary = try? RepoBarPersistentCache.summary(limit: 100)
        self.session.rateLimitReset = await self.github.rateLimitReset()
        self.session.rateLimitDiagnostics = diagnostics
        self.session.rateLimitCacheSummary = cacheSummary
        NotificationCenter.default.post(name: .menuDiagnosticsDidChange, object: nil)
    }

    func reloadRateLimitCacheSummary(limit: Int = 100) {
        self.session.rateLimitCacheSummary = try? RepoBarPersistentCache.summary(limit: limit)
    }

    func clearCaches() async {
        await self.github.clearCache()
        ContributionCacheStore.clear()
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    func updateGitHubReferenceMonitor() {
        guard self.session.settings.gitHubReferenceMonitor.enabled else {
            Task { await DiagnosticsLogger.shared.message("GitHub reference monitor disabled") }
            self.gitHubReferenceMonitor?.stop()
            self.gitHubReferenceMonitor = nil
            self.setGitHubReferenceMatch(nil)
            return
        }

        if self.gitHubReferenceMonitor == nil {
            Task { await DiagnosticsLogger.shared.message("GitHub reference monitor created") }
            self.gitHubReferenceMonitor = GitHubReferenceMonitor(
                onPasteboardWithoutReference: { [weak self] in
                    await self?.clearGitHubReference()
                },
                onReferences: { [weak self] queries, text in
                    await self?.resolveGitHubReferences(queries, sourceText: text)
                }
            )
        }
        Task { await DiagnosticsLogger.shared.message("GitHub reference monitor started mode=clipboard-only") }
        self.gitHubReferenceMonitor?.start()
    }

    private func clearGitHubReference() async {
        guard self.session.settings.gitHubReferenceMonitor.enabled else { return }

        self.gitHubReferenceResolutionID = UUID()
        self.setGitHubReferenceMatches([])
    }

    private func resolveGitHubReferences(_ queries: [GitHubReferenceQuery], sourceText: String) async {
        guard self.session.settings.gitHubReferenceMonitor.enabled else { return }

        let resolutionID = UUID()
        self.gitHubReferenceResolutionID = resolutionID
        let scopedQueries = await self.queries(queries, applyingLocalRepositoryContextFrom: sourceText)
        guard self.gitHubReferenceResolutionID == resolutionID else { return }

        let limitedQueries = Array(scopedQueries.prefix(AppLimits.GitHubReferenceMonitor.queryLimit))
        let repositories = self.githubReferenceCandidateRepositories()
        let github = self.github
        var matchesByIndex: [Int: GitHubReferenceMatch] = [:]
        var seen: Set<URL> = []

        let indexedQueries = Array(limitedQueries.enumerated())
        for chunk in indexedQueries.chunks(ofCount: AppLimits.GitHubReferenceMonitor.resolutionConcurrencyLimit) {
            await withTaskGroup(of: (Int, GitHubReferenceMatch?).self) { group in
                for (index, query) in chunk {
                    group.addTask {
                        let match = await Self.resolveGitHubReferenceMatch(
                            query: query,
                            repositories: repositories,
                            github: github
                        )
                        return (index, match)
                    }
                }

                for await (index, match) in group {
                    guard self.gitHubReferenceResolutionID == resolutionID else {
                        group.cancelAll()
                        return
                    }
                    guard let match, seen.insert(match.url).inserted else { continue }

                    matchesByIndex[index] = match
                    let orderedMatches = matchesByIndex.keys.sorted().compactMap { matchesByIndex[$0] }
                    self.setGitHubReferenceMatches(orderedMatches)
                }
            }

            guard self.gitHubReferenceResolutionID == resolutionID else { return }
        }

        if matchesByIndex.isEmpty {
            self.setGitHubReferenceMatches([])
        }
    }

    private func queries(
        _ queries: [GitHubReferenceQuery],
        applyingLocalRepositoryContextFrom text: String
    ) async -> [GitHubReferenceQuery] {
        guard queries.contains(where: { $0.repositoryFullName == nil }) else { return queries }

        let repositoryFullName = await GitHubReferenceLocalContext.repositoryFullName(
            in: text,
            localRepoIndex: self.session.localRepoIndex
        )
        guard let repositoryFullName else {
            return await GitHubReferenceLocalContext.queries(
                queries,
                applyingLocalRepositoryContextFrom: self.session.localRepoIndex
            )
        }

        return GitHubReferenceTranslator.queries(
            from: text,
            minimumBareDigits: AppLimits.GitHubReferenceMonitor.minimumBareDigits,
            repositoryContextOverride: repositoryFullName
        )
    }

    private nonisolated static func resolveGitHubReferenceMatch(
        query: GitHubReferenceQuery,
        repositories: [Repository],
        github: GitHubClient
    ) async -> GitHubReferenceMatch? {
        let candidateRepositories = if let repositoryFullName = query.repositoryFullName {
            repositories.filter { $0.fullName.caseInsensitiveCompare(repositoryFullName) == .orderedSame }
        } else if let repositoryName = query.repositoryName {
            repositories.filter { $0.name.caseInsensitiveCompare(repositoryName) == .orderedSame }
        } else {
            repositories
        }
        guard candidateRepositories.isEmpty == false else {
            return await github.liveReferenceMatch(query: query)
        }

        let cachedMatches = await github.cachedReferenceMatches(
            query: query,
            repositories: candidateRepositories,
            limit: AppLimits.GitHubReferenceMonitor.cacheLookupLimit
        )
        if let match = GitHubReferenceMatch.newestCreated(in: cachedMatches) {
            return match
        }

        let liveMatch = await github.liveReferenceMatch(
            query: query,
            repositories: Array(candidateRepositories.prefix(AppLimits.GitHubReferenceMonitor.liveLookupLimit))
        )
        if let liveMatch {
            return liveMatch
        }

        guard query.repositoryFullName == nil else { return nil }

        return await github.liveReferenceMatch(query: query)
    }

    private func githubReferenceCandidateRepositories() -> [Repository] {
        let sources = [
            self.session.accessibleRepositories,
            self.session.repositories,
            self.session.menuSnapshot?.repositories ?? []
        ]
        let repositories = sources.first(where: { $0.isEmpty == false }) ?? []
        var seen: Set<String> = []
        return repositories.filter { repo in
            guard repo.viewerCanRead else { return false }

            return seen.insert(repo.fullName.lowercased()).inserted
        }
    }

    private func setGitHubReferenceMatch(_ match: GitHubReferenceMatch?) {
        self.setGitHubReferenceMatches(match.map { [$0] } ?? [])
    }

    private func setGitHubReferenceMatches(_ matches: [GitHubReferenceMatch]) {
        let primaryMatch = GitHubReferenceMatch.newestCreated(in: matches)
        guard self.session.gitHubReferenceMatches != matches || self.session.gitHubReferenceMatch != primaryMatch else { return }

        self.session.gitHubReferenceMatches = matches
        self.session.gitHubReferenceMatch = primaryMatch
        NotificationCenter.default.post(name: .gitHubReferenceMatchDidChange, object: nil)
    }
}
