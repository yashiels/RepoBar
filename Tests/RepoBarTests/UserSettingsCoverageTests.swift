import Foundation
import RepoBarCore
import Testing

struct UserSettingsCoverageTests {
    @Test
    func `labels and seconds cover enum switches`() {
        #expect(LocalProjectsRefreshInterval.oneMinute.seconds == 60)
        #expect(LocalProjectsRefreshInterval.fifteenMinutes.seconds == 900)
        #expect(LocalProjectsRefreshInterval.twoMinutes.label == "2 minutes")
        #expect(LocalProjectsSettings().maxDepth == LocalProjectsConstants.defaultMaxDepth)

        #expect(GhosttyOpenMode.newWindow.label == "New Window")
        #expect(GhosttyOpenMode.tab.label == "Tab")

        #expect(RefreshInterval.oneMinute.seconds == 60)
        #expect(RefreshInterval.fifteenMinutes.seconds == 900)

        #expect(HeatmapDisplay.inline.label == "Inline")
        #expect(HeatmapDisplay.submenu.label == "Submenu")

        #expect(CardDensity.comfortable.label == "Comfortable")
        #expect(CardDensity.compact.label == "Compact")

        #expect(AccentTone.system.label == "System accent")
        #expect(AccentTone.githubGreen.label == "GitHub greens")
        #expect(AppearanceSettings().showRateLimitMeterInMenuBar)
        #expect(GitHubReferenceMonitorSettings().enabled == false)
        #expect(ActionsSettings().showActionsInMenu == false)
        #expect(ActionsSettings().planTier == .free)
        #expect(ActionsSettings().ownerFilter.isEmpty)
        #expect(UserSettings().monitoredOwners.isEmpty)
        #expect(GitHubPlanTier.free.includedMinutesPerMonth == 2000)
        #expect(GitHubPlanTier.enterprise.concurrentJobs == 500)

        #expect(GlobalActivityScope.allActivity.label == "All activity")
        #expect(GlobalActivityScope.myActivity.label == "My activity")

        #expect(GitHubArchiveSettings().preferArchiveWhenRateLimited)
        #expect(GitHubArchiveFormat.discrawlSnapshot.label == "Discrawl snapshot")
    }

    @Test
    func `menu normalization keeps rate limits above filters`() throws {
        var customization = MenuCustomization()
        customization.mainMenuOrder = [
            .loggedOutPrompt,
            .signInAction,
            .contributionHeader,
            .statusBanner,
            .filters,
            .repoList,
            .issueNavigator,
            .preferences,
            .about,
            .restartToUpdate,
            .quit
        ]

        customization.normalize()

        let statusIndex = try #require(customization.mainMenuOrder.firstIndex(of: .statusBanner))
        let rateIndex = try #require(customization.mainMenuOrder.firstIndex(of: .rateLimits))
        let filterIndex = try #require(customization.mainMenuOrder.firstIndex(of: .filters))
        #expect(statusIndex < rateIndex)
        #expect(rateIndex < filterIndex)
    }

    @Test
    func `menu normalization keeps actions after rate limits`() throws {
        var customization = MenuCustomization()
        customization.mainMenuOrder.removeAll { $0 == .actionsLimits }

        customization.normalize()

        let rateIndex = try #require(customization.mainMenuOrder.firstIndex(of: .rateLimits))
        let actionsIndex = try #require(customization.mainMenuOrder.firstIndex(of: .actionsLimits))
        let filterIndex = try #require(customization.mainMenuOrder.firstIndex(of: .filters))
        #expect(rateIndex < actionsIndex)
        #expect(actionsIndex < filterIndex)
    }
}
