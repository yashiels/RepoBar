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
    let accessibilityPermission = AccessibilityPermissionManager()
    let menuRefreshInterval: TimeInterval = 30
    var refreshTask: Task<Void, Never>?
    var localProjectsTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private var accessibilityPermissionTask: Task<Void, Never>?
    var menuRefreshTask: Task<Void, Never>?
    private var keyboardIssueMonitor: KeyboardIssueMonitor?
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
        self.accessibilityPermissionTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if self.accessibilityPermission.refresh() {
                    self.updateKeyboardIssueMonitor()
                }
            }
        }
        self.updateKeyboardIssueMonitor()
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

    func updateKeyboardIssueMonitor() {
        guard self.session.settings.issueNumberMonitor.enabled else {
            Task { await DiagnosticsLogger.shared.message("keyboard reference monitor disabled") }
            self.keyboardIssueMonitor?.stop()
            self.keyboardIssueMonitor = nil
            self.setKeyboardIssueMatch(nil)
            return
        }

        if self.keyboardIssueMonitor == nil {
            Task { await DiagnosticsLogger.shared.message("keyboard reference monitor created") }
            self.keyboardIssueMonitor = KeyboardIssueMonitor { [weak self] query in
                await self?.resolveTypedGitHubReference(query)
            }
        }
        let includeKeyboardEvents = self.accessibilityPermission.isTrusted
        let mode = includeKeyboardEvents ? "keyboard+clipboard" : "clipboard-only"
        Task { await DiagnosticsLogger.shared.message("GitHub reference monitor started mode=\(mode)") }
        self.keyboardIssueMonitor?.start(includeKeyboardEvents: includeKeyboardEvents)
    }

    private func resolveTypedGitHubReference(_ query: GitHubReferenceQuery) async {
        guard self.session.settings.issueNumberMonitor.enabled else { return }

        let repositories = self.githubReferenceCandidateRepositories()
        let candidateRepositories = if let repositoryFullName = query.repositoryFullName {
            repositories.filter { $0.fullName.caseInsensitiveCompare(repositoryFullName) == .orderedSame }
        } else {
            repositories
        }
        guard candidateRepositories.isEmpty == false else {
            self.setKeyboardIssueMatch(await self.github.liveReferenceMatch(query: query))
            return
        }

        let cachedMatches = await self.github.cachedReferenceMatches(
            query: query,
            repositories: candidateRepositories,
            limit: AppLimits.IssueNumberMonitor.cacheLookupLimit
        )
        if let match = GitHubReferenceMatch.newestCreated(in: cachedMatches) {
            self.setKeyboardIssueMatch(match)
            return
        }

        let liveMatch = await self.github.liveReferenceMatch(
            query: query,
            repositories: Array(candidateRepositories.prefix(AppLimits.IssueNumberMonitor.liveLookupLimit))
        )
        if let liveMatch {
            self.setKeyboardIssueMatch(liveMatch)
            return
        }

        self.setKeyboardIssueMatch(await self.github.liveReferenceMatch(query: query))
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

    private func setKeyboardIssueMatch(_ match: GitHubReferenceMatch?) {
        guard self.session.keyboardIssueMatch != match else { return }

        self.session.keyboardIssueMatch = match
        NotificationCenter.default.post(name: .keyboardIssueMatchDidChange, object: nil)
    }
}
