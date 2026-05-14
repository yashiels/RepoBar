import AppKit
import RepoBarCore
import SwiftUI

extension StatusBarMenuBuilder {
    func paddedSeparator() -> NSMenuItem {
        self.viewItem(for: MenuPaddedSeparatorView(), enabled: false)
    }

    func repoCardSeparator() -> NSMenuItem {
        self.viewItem(for: RepoCardSeparatorRowView(), enabled: false)
    }

    func repoMenuItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        let card = RepoMenuCardView(
            repo: repo,
            isPinned: isPinned,
            showHeatmap: self.appState.session.settings.heatmap.display == .inline,
            heatmapRange: self.appState.session.heatmapRange,
            accentTone: self.appState.session.settings.appearance.accentTone,
            showDirtyFiles: self.appState.session.settings.localProjects.showDirtyFilesInMenu,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        let submenu = self.repoSubmenu(for: repo, isPinned: isPinned)
        if let cached = self.repoMenuItemCache[repo.id] {
            // Remove from current menu if attached (prevents crash when reusing cached items)
            cached.menu?.removeItem(cached)
            self.menuItemFactory.updateItem(cached, with: card, highlightable: true, showsSubmenuIndicator: true)
            cached.isEnabled = true
            cached.submenu = submenu
            cached.target = self.target
            cached.action = #selector(self.target.menuItemNoOp(_:))
            return cached
        }
        let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
        self.repoMenuItemCache[repo.id] = item
        return item
    }

    func repoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let changelogPresentation = self.target.cachedChangelogPresentation(
            fullName: repo.title,
            releaseTag: repo.source.latestRelease?.tag
        )
        let changelogHeadline = self.target.cachedChangelogHeadline(fullName: repo.title)
        let signature = RepoSubmenuSignature(
            repo: repo,
            settings: self.appState.session.settings,
            heatmapRange: self.appState.session.heatmapRange,
            recentCounts: RepoRecentCountSignature(
                commits: self.target.cachedRecentCommitCount(fullName: repo.title),
                commitsDigest: self.target.cachedRecentCommitDigest(fullName: repo.title)
            ),
            changelogPresentation: changelogPresentation,
            changelogHeadline: changelogHeadline,
            isPinned: isPinned
        )
        if let cached = self.repoSubmenuCache[repo.id], cached.signature == signature {
            return cached.menu
        }
        let menu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
        self.repoSubmenuCache[repo.id] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        return menu
    }

    func repoFullName(for menu: NSMenu) -> String? {
        self.repoSubmenuCache.first(where: { $0.value.menu === menu })?.key
    }

    func updateChangelogRow(fullName: String, releaseTag: String?) {
        guard let cached = self.repoSubmenuCache[fullName] else { return }
        guard let item = cached.menu.items.first(where: {
            guard let identifier = $0.representedObject as? RepoSubmenuRowIdentifier else { return false }

            return identifier.fullName == fullName && identifier.kind == .changelog
        }) else { return }

        let presentation = self.target.cachedChangelogPresentation(fullName: fullName, releaseTag: releaseTag)
        let headline = self.target.cachedChangelogHeadline(fullName: fullName)
        let title = headline == nil ? (presentation?.title ?? "Changelog") : "Changelog"
        let badgeText = headline ?? presentation?.badgeText
        let detailText = headline == nil ? presentation?.detailText : nil
        let row = RecentListSubmenuRowView(
            title: title,
            systemImage: "doc.text",
            badgeText: badgeText,
            detailText: detailText
        )
        self.menuItemFactory.updateItem(item, with: row, highlightable: true, showsSubmenuIndicator: true)
        self.refreshMenuViewHeights(in: cached.menu)
        cached.menu.update()
    }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func infoMessageItem(_ title: String) -> NSMenuItem {
        let view = MenuInfoTextRowView(text: title, lineLimit: 5)
        return self.viewItem(for: view, enabled: false)
    }

    func rateLimitSectionHeaderItem(_ title: String) -> NSMenuItem {
        self.viewItem(for: RateLimitSectionHeaderView(title: title), enabled: false)
    }

    func rateLimitResourceItem(_ row: RateLimitDisplayRow) -> NSMenuItem {
        self.viewItem(for: RateLimitResourceRowView(row: row), enabled: false)
    }

    func rateLimitsMenuItem(now: Date = Date()) -> NSMenuItem {
        let item = NSMenuItem(title: "GitHub API Status", action: nil, keyEquivalent: "")
        item.image = self.cachedSystemImage(named: "speedometer")
        item.submenu = self.rateLimitsSubmenu(now: now)
        return item
    }

    func rateLimitsStatusMenuItem(now: Date = Date()) -> NSMenuItem {
        let state = self.appState.session.rateLimitDisplayState
        let view = RateLimitStatusRowView(
            summary: state.compactSummary(now: now),
            isLimited: state.isLimited(now: now)
        )
        return self.viewItem(
            for: view,
            enabled: true,
            highlightable: true,
            submenu: self.rateLimitsSubmenu(state: state, now: now)
        )
    }

    private func rateLimitsSubmenu(now: Date = Date()) -> NSMenu {
        self.rateLimitsSubmenu(state: self.appState.session.rateLimitDisplayState, now: now)
    }

    private func rateLimitsSubmenu(state: RateLimitDisplayState, now: Date) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target

        let sections = state.sections(now: now)
        for (index, section) in sections.enumerated() {
            if index > 0 {
                submenu.addItem(.separator())
            }
            if let title = section.title {
                submenu.addItem(self.rateLimitSectionHeaderItem(title))
            }
            for row in section.resourceRows {
                submenu.addItem(self.rateLimitResourceItem(row))
            }
        }

        return submenu
    }

    // MARK: - Actions & Runners

    func actionsLimitsStatusMenuItem(now: Date = Date()) -> NSMenuItem {
        let session = self.appState.session
        let summary = Self.actionsCompactSummary(session: session)
        let hasRunners = session.actionsOrgSnapshots.contains { $0.runners?.onlineCount ?? 0 > 0 }
        let view = ActionsLimitsStatusRowView(summary: summary, hasRunners: hasRunners)
        return self.viewItem(
            for: view,
            enabled: true,
            highlightable: true,
            submenu: self.actionsLimitsSubmenu(session: session, now: now)
        )
    }

    private func actionsLimitsSubmenu(session: Session, now _: Date) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target

        let snapshots = session.actionsOrgSnapshots
        let showOrgHeaders = snapshots.count > 1

        for (index, snapshot) in snapshots.enumerated() {
            let tier = snapshot.planTier

            if index > 0 {
                submenu.addItem(.separator())
            }

            if showOrgHeaders {
                submenu.addItem(self.viewItem(
                    for: ActionsOrgHeaderView(org: snapshot.org, isOrg: snapshot.isOrg),
                    enabled: false
                ))
            }

            submenu.addItem(self.viewItem(
                for: ActionsSectionHeaderView(title: "\(tier.label) Plan"),
                enabled: false
            ))

            if let used = snapshot.minutesUsed, let included = snapshot.minutesIncluded {
                submenu.addItem(self.viewItem(
                    for: ActionsMinutesRowView(minutesUsed: used, minutesIncluded: included),
                    enabled: false
                ))
            }

            if let queueStatus = snapshot.queueStatus {
                submenu.addItem(self.viewItem(
                    for: ActionsQueueRowView(queueStatus: queueStatus, planTier: tier),
                    enabled: false
                ))
            }

            if let cache = snapshot.cacheUsage {
                submenu.addItem(self.viewItem(
                    for: ActionsCacheUsageRowView(cacheUsage: cache),
                    enabled: false
                ))
            }

            if let retention = snapshot.artifactRetention {
                submenu.addItem(self.viewItem(
                    for: ArtifactRetentionRowView(retention: retention),
                    enabled: false
                ))
            }

            if let runners = snapshot.runners, runners.totalCount > 0 || runners.isRepositorySampled {
                submenu.addItem(self.viewItem(
                    for: ActionsRunnerFleetRowView(runners: runners),
                    enabled: false
                ))

                for runner in runners.runners.prefix(10) {
                    submenu.addItem(self.viewItem(
                        for: ActionsRunnerRowView(runner: runner),
                        enabled: false
                    ))
                }
                if runners.totalCount > 10 {
                    submenu.addItem(self.infoItem("… and \(runners.totalCount - 10) more"))
                }
            }

            let hasPartialRunnerOrQueueScan = snapshot.runners?.isRepositorySampled == true || snapshot.queueStatus?.isRepositorySampled == true
            if !snapshot.hasRunners, !snapshot.hasActiveJobs, !hasPartialRunnerOrQueueScan {
                submenu.addItem(self.infoItem("No active runners or jobs"))
            }
        }

        if snapshots.isEmpty {
            submenu.addItem(self.infoItem(session.account.isLoggedIn ? "Loading owners…" : "No owners found"))
        }

        return submenu
    }

    private static func actionsCompactSummary(session: Session) -> String {
        let snapshots = session.actionsOrgSnapshots
        let totalRunners = snapshots.compactMap(\.runners).reduce(0) { $0 + $1.totalCount }
        let onlineRunners = snapshots.compactMap(\.runners).reduce(0) { $0 + $1.onlineCount }
        let activeJobs = snapshots.compactMap(\.queueStatus).reduce(0) { $0 + $1.totalActiveCount }
        let orgCount = snapshots.count(where: \.isOrg)

        var parts: [String] = []
        if totalRunners > 0 {
            parts.append("\(onlineRunners)/\(totalRunners) runners")
        }
        if activeJobs > 0 {
            parts.append("\(activeJobs) jobs active")
        }
        if parts.isEmpty {
            if snapshots.isEmpty, session.account.isLoggedIn {
                parts.append("Loading owners")
            } else if orgCount > 0 {
                let ownerCount = snapshots.count
                parts.append("\(ownerCount) owner\(ownerCount == 1 ? "" : "s")")
            } else {
                parts.append("Personal account")
            }
        }
        return parts.joined(separator: " · ")
    }

    func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        represented: Any? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self.target
        if let represented { item.representedObject = represented }
        if let systemImage, let image = self.cachedSystemImage(named: systemImage) {
            item.image = image
        }
        return item
    }

    func cachedSystemImage(named name: String) -> NSImage? {
        let key = "\(name)|\(self.isLightAppearance ? "light" : "dark")"
        if let cached = self.systemImageCache[key] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }

        image.size = NSSize(width: 14, height: 14)
        if name == "eye.slash", self.isLightAppearance {
            let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            let tinted = image.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            if let tinted {
                self.systemImageCache[key] = tinted
                return tinted
            }
        }
        image.isTemplate = true
        self.systemImageCache[key] = image
        return image
    }

    func viewItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        self.menuItemFactory.makeItem(
            for: content,
            enabled: enabled,
            highlightable: highlightable,
            showsSubmenuIndicator: submenu != nil,
            submenu: submenu,
            target: submenu != nil ? self.target : nil,
            action: submenu != nil ? #selector(self.target.menuItemNoOp(_:)) : nil
        )
    }
}
