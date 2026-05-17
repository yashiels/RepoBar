import AppKit

extension StatusBarMenuManager {
    func preloadGitHubReferenceMenuPreviews(_ menu: NSMenu) {
        var remaining = min(
            AppLimits.GitHubReferenceMonitor.menuWebPreviewPreloadLimit,
            max(1, self.appState.session.gitHubReferenceMatches.count)
        )
        self.preloadGitHubReferenceMenuPreviews(in: menu, remaining: &remaining)
    }

    private func preloadGitHubReferenceMenuPreviews(in menu: NSMenu, remaining: inout Int) {
        guard remaining > 0 else { return }

        for item in menu.items {
            if let browserView = item.view as? GitHubReferenceBrowserMenuItemView {
                browserView.preload()
                remaining -= 1
                if remaining <= 0 { return }
            }
            if let submenu = item.submenu {
                self.preloadGitHubReferenceMenuPreviews(in: submenu, remaining: &remaining)
                if remaining <= 0 { return }
            }
        }
    }

    func unloadGitHubReferenceMenuPreviews(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? GitHubReferenceBrowserMenuItemView)?.unload()
            if let submenu = item.submenu {
                self.unloadGitHubReferenceMenuPreviews(submenu)
            }
        }
    }
}
