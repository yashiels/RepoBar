@testable import RepoBar
@testable import RepoBarCore
import Testing

struct ActionsOwnerSelectionTests {
    @Test @MainActor
    func `uses explicit owner filter when configured`() {
        let repos = [
            Self.repo(owner: "openclaw", name: "openclaw"),
            Self.repo(owner: "steipete", name: "RepoBar")
        ]

        let owners = AppState.actionsOwners(
            username: "steipete",
            repositories: repos,
            monitoredOwners: [" objcio ", "steipete", "OBJCiO"]
        )

        #expect(owners.map(\.name) == ["objcio", "steipete"])
        #expect(owners.map(\.isOrg) == [true, false])
    }

    @Test @MainActor
    func `uses repository owners when owner filter is empty`() {
        let repos = [
            Self.repo(owner: "openclaw", name: "clawsweeper"),
            Self.repo(owner: "OpenClaw", name: "crabpot"),
            Self.repo(owner: "steipete", name: "RepoBar")
        ]

        let owners = AppState.actionsOwners(
            username: "steipete",
            repositories: repos,
            monitoredOwners: []
        )

        #expect(owners.map(\.name) == ["steipete", "openclaw"])
        #expect(owners.map(\.isOrg) == [false, true])
    }

    private static func repo(owner: String, name: String) -> Repository {
        Repository(
            id: "\(owner)/\(name)",
            name: name,
            owner: owner,
            sortOrder: 0,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: []
        )
    }
}
