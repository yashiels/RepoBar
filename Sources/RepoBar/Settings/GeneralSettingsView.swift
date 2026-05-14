import AppKit
import RepoBarCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var monitoredOwnersDraft = ""

    private var normalizedCurrentUsername: String? {
        guard case let .loggedIn(user) = self.session.account else { return nil }

        return user.username.lowercased()
    }

    private var showOnlyMyRepos: Bool {
        guard let username = self.normalizedCurrentUsername else { return false }

        return OwnerFilter.normalize(self.session.settings.repoList.ownerFilter) == [username]
    }

    private var visibleOwnerCandidates: [String] {
        var owners = self.session.repositories.map(\.owner)
        if case let .loggedIn(user) = self.session.account {
            owners.append(user.username)
        }
        return OwnerFilter.normalize(owners)
    }

    private var selectedMonitoredOwners: [String] {
        OwnerFilter.normalize(self.session.settings.monitoredOwners)
    }

    private func toggleShowOnlyMyRepos(_ enabled: Bool) {
        guard let username = self.normalizedCurrentUsername else { return }

        self.session.settings.repoList.ownerFilter = enabled ? [username] : []

        self.appState.persistSettings()
        self.appState.requestRefresh(cancelInFlight: true)
    }

    private func updateMonitoredOwners(from rawValue: String) {
        let owners = Self.parseOwners(rawValue)
        self.session.settings.monitoredOwners = owners
        self.monitoredOwnersDraft = owners.joined(separator: ", ")
        self.monitoredOwnersChanged()
    }

    private func useVisibleOwners() {
        self.session.settings.monitoredOwners = self.visibleOwnerCandidates
        self.monitoredOwnersDraft = self.visibleOwnerCandidates.joined(separator: ", ")
        self.monitoredOwnersChanged()
    }

    private func clearMonitoredOwners() {
        self.session.settings.monitoredOwners = []
        self.monitoredOwnersDraft = ""
        self.monitoredOwnersChanged()
    }

    private func removeMonitoredOwner(_ owner: String) {
        let normalized = owner.lowercased()
        self.session.settings.monitoredOwners = self.selectedMonitoredOwners.filter { $0 != normalized }
        self.monitoredOwnersDraft = self.selectedMonitoredOwners.joined(separator: ", ")
        self.monitoredOwnersChanged()
    }

    private func monitoredOwnersChanged() {
        self.appState.persistSettings()
        if !self.session.settings.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits) {
            self.session.actionsOrgSnapshots = []
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private static func parseOwners(_ rawValue: String) -> [String] {
        OwnerFilter.normalize(rawValue.split { separator in
            separator == "," || separator == " " || separator == "\n" || separator == "\t"
        }.map(String.init))
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    Toggle("Launch at login", isOn: self.$session.settings.launchAtLogin)
                        .onChange(of: self.session.settings.launchAtLogin) { _, value in
                            LaunchAtLoginHelper.set(enabled: value)
                            self.appState.persistSettings()
                        }
                } footer: {
                    Text("Automatically opens RepoBar when you start your Mac.")
                }

                Section {
                    Toggle("Show contribution header", isOn: self.$session.settings.appearance.showContributionHeader)
                        .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                            self.appState.persistSettings()
                        }
                    Picker("Activity feed", selection: self.$session.settings.appearance.activityScope) {
                        ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .onChange(of: self.session.settings.appearance.activityScope) { _, _ in
                        self.appState.persistSettings()
                        self.appState.requestRefresh()
                    }
                    Picker("Repository heatmap", selection: self.$session.settings.heatmap.display) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(display.label).tag(display)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.display) { _, _ in
                        self.appState.persistSettings()
                    }
                    Picker("Heatmap window", selection: self.$session.settings.heatmap.span) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(span.label).tag(span)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.span) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateHeatmapRange(now: Date())
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Repository heatmaps show recent commit activity for each repository.")
                }

                Section {
                    Picker("Repositories shown", selection: self.$session.settings.repoList.displayLimit) {
                        ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Menu sort", selection: self.$session.settings.repoList.menuSortKey) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(sortKey.settingsLabel).tag(sortKey)
                        }
                    }
                    .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                        self.appState.persistSettings()
                    }
                    Toggle("Include forked repositories", isOn: self.$session.settings.repoList.showForks)
                        .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle("Include archived repositories", isOn: self.$session.settings.repoList.showArchived)
                        .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle("Show only my repositories", isOn: Binding(
                        get: { self.showOnlyMyRepos },
                        set: { self.toggleShowOnlyMyRepos($0) }
                    ))
                    .disabled(self.normalizedCurrentUsername == nil)
                } header: {
                    Text("Repositories")
                } footer: {
                    Text("Filters apply to repo lists and search. 'Show only my repositories' hides repos owned by organizations and other users.")
                }

                Section {
                    LabeledContent("Owners") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Auto from visible repositories", text: self.$monitoredOwnersDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { self.updateMonitoredOwners(from: self.monitoredOwnersDraft) }
                                Button("Apply") { self.updateMonitoredOwners(from: self.monitoredOwnersDraft) }
                                Button("Visible") { self.useVisibleOwners() }
                                    .disabled(self.visibleOwnerCandidates.isEmpty)
                                Button("Auto") { self.clearMonitoredOwners() }
                                    .disabled(self.selectedMonitoredOwners.isEmpty)
                            }

                            if !self.selectedMonitoredOwners.isEmpty {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)],
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    ForEach(self.selectedMonitoredOwners, id: \.self) { owner in
                                        Button {
                                            self.removeMonitoredOwner(owner)
                                        } label: {
                                            Label(owner, systemImage: "xmark.circle")
                                                .lineLimit(1)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Monitored Owners")
                } footer: {
                    Text(
                        "Empty owners means personal account plus owners in the visible repository list. "
                            + "Use comma-separated owner names to pin RepoBar to specific owners."
                    )
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Quit RepoBar") { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            self.monitoredOwnersDraft = self.selectedMonitoredOwners.joined(separator: ", ")
        }
    }
}
