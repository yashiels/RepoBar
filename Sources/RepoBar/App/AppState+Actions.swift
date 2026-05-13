import Foundation
import RepoBarCore

extension AppState {
    func refreshActionsLimitsState() async {
        let settings = self.session.settings.actions
        guard settings.showActionsInMenu else { return }
        guard case let .loggedIn(user) = self.session.account else { return }

        let github = self.github
        let repos = self.session.repositories
        let authMethod = self.session.settings.authMethod

        let userTier = user.detectedPlanTier ?? settings.planTier
        await MainActor.run { self.session.actionsPlanTier = userTier }

        let apiOrgs = (authMethod == .pat) ? ((try? await github.userOrganizations()) ?? []) : []

        var owners: [(name: String, isOrg: Bool)] = [(name: user.username, isOrg: false)]
        var seen = Set<String>([user.username.lowercased()])

        if !apiOrgs.isEmpty {
            for org in apiOrgs {
                if seen.insert(org.lowercased()).inserted {
                    owners.append((name: org, isOrg: true))
                }
            }
        } else {
            let repoOwners = Self.repoOwners(from: repos, excludingUsername: user.username)
            for repoOwner in repoOwners {
                guard seen.insert(repoOwner.lowercased()).inserted else { continue }
                if (try? await github.organizationPlan(org: repoOwner)) != nil {
                    owners.append((name: repoOwner, isOrg: true))
                }
            }
        }

        var snapshots: [ActionsOrgSnapshot] = []
        for owner in owners {
            let ownerRepos = repos.filter { $0.owner.lowercased() == owner.name.lowercased() }
            let runners = await Self.fetchRunners(github: github, owner: owner.name, repos: ownerRepos)
            let queue = await Self.fetchQueueStatus(github: github, repos: ownerRepos)

            var ownerTier = userTier
            if owner.isOrg {
                if let orgPlanName = try? await github.organizationPlan(org: owner.name),
                   let detected = UserIdentity.planTier(from: orgPlanName) {
                    ownerTier = detected
                }
            }

            let billingUsage = try? await github.actionsBillingUsage(owner: owner.name, isOrg: owner.isOrg)
            let minutesUsed = billingUsage.map { Int($0.minutesUsedInCurrentMonth().rounded()) }
            let minutesIncluded = ownerTier.includedMinutesPerMonth
            let cacheUsage = owner.isOrg ? (try? await github.actionsCacheUsage(org: owner.name)) : nil
            let artifactRetention = owner.isOrg ? (try? await github.artifactRetentionPolicy(org: owner.name)) : nil

            snapshots.append(ActionsOrgSnapshot(
                org: owner.name,
                runners: runners,
                queueStatus: queue,
                planTier: ownerTier,
                isOrg: owner.isOrg,
                minutesUsed: minutesUsed,
                minutesIncluded: minutesIncluded,
                cacheUsage: cacheUsage,
                artifactRetention: artifactRetention
            ))
        }

        await MainActor.run {
            self.session.actionsOrgSnapshots = snapshots
        }
    }

    private static func repoOwners(from repos: [Repository], excludingUsername username: String) -> [String] {
        var seen = Set<String>([username.lowercased()])
        var result: [String] = []
        for repo in repos {
            if seen.insert(repo.owner.lowercased()).inserted {
                result.append(repo.owner)
            }
        }
        return result
    }

    private static func fetchRunners(
        github: GitHubClient,
        owner: String,
        repos: [Repository]
    ) async -> ActionsRunnerInfo? {
        if let orgRunners = try? await github.selfHostedRunners(owner: owner) {
            return orgRunners
        }
        guard let first = repos.first else { return nil }
        return try? await github.selfHostedRunners(owner: first.owner, repo: first.name)
    }

    private static func fetchQueueStatus(
        github: GitHubClient,
        repos: [Repository]
    ) async -> ActionsQueueStatus? {
        guard !repos.isEmpty else { return nil }
        var totalInProgress = 0
        var totalQueued = 0
        var allRuns: [ActiveWorkflowRun] = []
        let now = Date()

        let sample = repos.prefix(5)
        for repo in sample {
            guard let status = try? await github.actionsQueueStatus(owner: repo.owner, name: repo.name) else {
                continue
            }
            totalInProgress += status.inProgressCount
            totalQueued += status.queuedCount
            allRuns.append(contentsOf: status.runs)
        }

        guard totalInProgress > 0 || totalQueued > 0 else { return nil }
        return ActionsQueueStatus(
            inProgressCount: totalInProgress,
            queuedCount: totalQueued,
            runs: allRuns,
            fetchedAt: now
        )
    }
}
