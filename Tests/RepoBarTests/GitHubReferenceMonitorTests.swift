import Foundation
@testable import RepoBarCore
import Testing

@MainActor
struct GitHubReferenceMonitorTests {
    @Test
    func `bare numbers and issue prefixes become issue queries`() {
        #expect(GitHubReferenceTranslator.query(from: "73655") == .issueNumber(73655))
        #expect(GitHubReferenceTranslator.query(from: "7") == .issueNumber(7))
        #expect(GitHubReferenceTranslator.query(from: "#7") == .issueNumber(7))
        #expect(GitHubReferenceTranslator.query(from: "gh-42") == .issueNumber(42))
        #expect(GitHubReferenceTranslator.query(from: " #78096. ") == .issueNumber(78096))
        #expect(GitHubReferenceTranslator.query(from: "a73655") == nil)
    }

    @Test
    func `commit hashes become commit queries`() {
        #expect(GitHubReferenceTranslator.query(from: "4992546") == .commitHash("4992546"))
        #expect(GitHubReferenceTranslator.query(from: " - bare short SHA: 4992546") == .commitHash("4992546"))
        #expect(GitHubReferenceTranslator.query(from: "ffd212ca43") == .commitHash("ffd212ca43"))
        #expect(
            GitHubReferenceTranslator.query(from: "d04517cefff3af339f560a8e388cacc3898e6562") ==
                .commitHash("d04517cefff3af339f560a8e388cacc3898e6562")
        )
        #expect(GitHubReferenceTranslator.query(from: "1234567") == .commitHash("1234567"))
        #expect(GitHubReferenceTranslator.query(from: "abcdef") == nil)
    }

    @Test
    func `owner repo issue shorthand becomes repository scoped issue query`() {
        #expect(
            GitHubReferenceTranslator.query(from: "steipete/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
        #expect(
            GitHubReferenceTranslator.query(from: "openclaw/clawsweeper#57") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/clawsweeper", number: 57)
        )
        #expect(
            GitHubReferenceTranslator.query(from: " steipete/summarize#215. ") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
        #expect(
            GitHubReferenceTranslator.query(from: "  - scoped issue shorthand: steipete/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
    }

    @Test
    func `repo name issue shorthand becomes repository name scoped issue query`() {
        #expect(
            GitHubReferenceTranslator.query(from: "discrawl#64") ==
                .repositoryNameIssueNumber(repositoryName: "discrawl", number: 64)
        )
        #expect(
            GitHubReferenceTranslator.query(from: " Discrawl#64. ") ==
                .repositoryNameIssueNumber(repositoryName: "discrawl", number: 64)
        )
    }

    @Test
    func `chained owner repo issue shorthand becomes multiple repository scoped issue queries`() {
        #expect(
            GitHubReferenceTranslator.queries(from: "openclaw/crabbox#70/#71") == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 70),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 71)
            ]
        )
        #expect(
            GitHubReferenceTranslator.queries(from: "make - openclaw/crabbox#70/#71: work") == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 70),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 71)
            ]
        )
    }

    @Test
    func `ranged owner repo issue shorthand becomes repository scoped issue series`() {
        #expect(
            GitHubReferenceTranslator.queries(from: "openclaw/crabbox#66-#69") == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 66),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 67),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 68),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 69)
            ]
        )
        #expect(
            GitHubReferenceTranslator.queries(from: "also make openclaw/crabbox#66-#69 work (series)") == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 66),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 67),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 68),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 69)
            ]
        )
        #expect(
            GitHubReferenceTranslator.queries(from: "openclaw/crabbox#66-69") == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 66),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 67),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 68),
                .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 69)
            ]
        )
    }

    @Test
    func `github issue and pr urls become repository scoped issue queries`() {
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/issues/73655") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 73655)
        )
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/pull/123") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 123)
        )
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/issues/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 1_234_567)
        )
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/pull/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 1_234_567)
        )
    }

    @Test
    func `github commit urls become repository scoped commit queries`() {
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/commit/ffd212ca43abcdef") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "ffd212ca43abcdef")
        )
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/commits/ffd212ca43") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "ffd212ca43")
        )
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/openclaw/pull/57843/changes/d04517cefff3af339f560a8e388cacc3898e6562") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "d04517cefff3af339f560a8e388cacc3898e6562")
        )
    }

    @Test
    func `github actions run urls become repository scoped workflow run queries`() {
        #expect(
            GitHubReferenceTranslator.query(from: "https://github.com/openclaw/songsee/actions/runs/25620622163") ==
                .repositoryWorkflowRun(repositoryFullName: "openclaw/songsee", runID: 25_620_622_163)
        )
    }

    @Test
    func `multiple bare issue references inherit repository context`() {
        let text = """
        Found 5 more in openclaw/gogcli after clean main pull.

        1. #569 release/bottle codesigning
        2. #568 local self-sign PR
        3. #567 Win11 access_denied
        4. #338 Workspace invalid_rapt
        5. #468 Google Meet PR
        """
        #expect(
            GitHubReferenceTranslator.queries(from: text) == [
                .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 569),
                .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 568),
                .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 567),
                .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 338),
                .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 468)
            ]
        )
    }

    @Test
    func `multiple grouped issue references use line scoped repository context`() {
        let text = """
            - openclaw/discrawl: #61, #62, #63
            - openclaw/acpx: #294, #295, #296, #297, #303
            - openclaw/openclaw.ai: #132, #133, #134
            - steipete/oracle: #188
            - openclaw/spogo: #26
            - openclaw/gitcrawl: #14
        """
        #expect(GitHubReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "openclaw/discrawl", number: 61),
            .repositoryIssueNumber(repositoryFullName: "openclaw/discrawl", number: 62),
            .repositoryIssueNumber(repositoryFullName: "openclaw/discrawl", number: 63),
            .repositoryIssueNumber(repositoryFullName: "openclaw/acpx", number: 294),
            .repositoryIssueNumber(repositoryFullName: "openclaw/acpx", number: 295),
            .repositoryIssueNumber(repositoryFullName: "openclaw/acpx", number: 296),
            .repositoryIssueNumber(repositoryFullName: "openclaw/acpx", number: 297),
            .repositoryIssueNumber(repositoryFullName: "openclaw/acpx", number: 303),
            .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw.ai", number: 132),
            .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw.ai", number: 133),
            .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw.ai", number: 134),
            .repositoryIssueNumber(repositoryFullName: "steipete/oracle", number: 188),
            .repositoryIssueNumber(repositoryFullName: "openclaw/spogo", number: 26),
            .repositoryIssueNumber(repositoryFullName: "openclaw/gitcrawl", number: 14)
        ])
    }

    @Test
    func `multiple parser ignores slash words that are not repository context`() {
        let text = """
        Found items in openclaw/gogcli.

        1. #569 release/bottle codesigning
        2. #568 local self-sign PR
        """
        #expect(GitHubReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 569),
            .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 568)
        ])
    }

    @Test
    func `multiple parser ignores ordered list numbers`() {
        let text = """
        1. #10 first
        2. #11 second
        """
        #expect(GitHubReferenceTranslator.queries(from: text) == [.issueNumber(10), .issueNumber(11)])
    }

    @Test
    func `multiple parser dedupes references after inheriting scoped context`() {
        let text = "openclaw/gogcli#569 #569 https://github.com/openclaw/gogcli/issues/569"
        #expect(GitHubReferenceTranslator.queries(from: text) == [
            .repositoryIssueNumber(repositoryFullName: "openclaw/gogcli", number: 569)
        ])
    }

    @Test
    func `local path candidates trim prompt separators`() {
        let text = "gpt-5.5 high fast · ~/Projects/crabbox · -"
        #expect(GitHubReferenceLocalContext.localPathCandidates(in: text) == ["~/Projects/crabbox"])
    }

    @Test
    func `remote urls become github repository full names`() {
        #expect(
            GitHubReferenceLocalContext.gitHubRepositoryFullName(
                fromRemoteURL: "https://github.com/openclaw/crabbox.git"
            ) == "openclaw/crabbox"
        )
        #expect(
            GitHubReferenceLocalContext.gitHubRepositoryFullName(
                fromRemoteURL: "git@github.com:openclaw/crabbox.git"
            ) == "openclaw/crabbox"
        )
    }

    @Test
    func `bare references inherit local repository context`() async {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/crabbox"),
            name: "crabbox",
            fullName: "openclaw/crabbox",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [status])
        let text = """
        - PRs:
            - #61 feat: add checkpoint ledger store
            - #60 docs: sharpen agent workspace positioning

        gpt-5.5 high fast · /tmp/crabbox · -
        """
        let repositoryFullName = await GitHubReferenceLocalContext.repositoryFullName(in: text, localRepoIndex: index)
        let queries: [GitHubReferenceQuery] = GitHubReferenceLocalContext.queries(
            GitHubReferenceTranslator.queries(from: text),
            applyingRepositoryFullName: repositoryFullName
        )
        let expected: [GitHubReferenceQuery] = [
            .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 61),
            .repositoryIssueNumber(repositoryFullName: "openclaw/crabbox", number: 60)
        ]
        #expect(queries == expected)
    }

    @Test
    func `bare commit references inherit unique local commit context`() async throws {
        let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }

        try runGit(["init"], in: repoURL)
        try runGit(["config", "user.email", "repobar-tests@example.com"], in: repoURL)
        try runGit(["config", "user.name", "RepoBar Tests"], in: repoURL)
        try "hello\n".write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "init"], in: repoURL)
        let sha = try runGit(["rev-parse", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let shortSHA = String(sha.prefix(7))

        let status = LocalRepoStatus(
            path: repoURL,
            name: "RepoBar",
            fullName: "steipete/RepoBar",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let queries = await GitHubReferenceLocalContext.queries(
            [.commitHash(shortSHA)],
            applyingLocalRepositoryContextFrom: LocalRepoIndex(statuses: [status])
        )

        #expect(queries == [.repositoryCommitHash(repositoryFullName: "steipete/RepoBar", hash: shortSHA)])
    }

    @Test
    func `repo name issue references inherit unique local repository context`() async {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/discrawl"),
            name: "discrawl",
            fullName: "openclaw/discrawl",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )

        let queries = await GitHubReferenceLocalContext.queries(
            [.repositoryNameIssueNumber(repositoryName: "discrawl", number: 64)],
            applyingLocalRepositoryContextFrom: LocalRepoIndex(statuses: [status])
        )

        #expect(queries == [.repositoryIssueNumber(repositoryFullName: "openclaw/discrawl", number: 64)])
    }

    @Test
    func `local repository context beats prose slash words`() {
        let text = """
        - #2124 header avatar controls
        - #2128 content container constraints
        - #908 upload page validation errors hidden. Likely fix: surface validationError inline/toast on publish/upload forms.
        - #937 clawhub update --all false local changes.
        - #951 onlycrabs.ai README mismatch.

        Skipped: #2126 too large, #1110 conflicts + API/CLI feature, #1712 stats/accounting touches telemetry semantics.

        gpt-5.5 high fast · ~/Projects/clawhub · Context 67% left
        """
        let queries = GitHubReferenceTranslator.queries(
            from: text,
            repositoryContextOverride: "openclaw/clawhub"
        )
        #expect(queries.map(\.displayText) == [
            "openclaw/clawhub#2124",
            "openclaw/clawhub#2128",
            "openclaw/clawhub#908",
            "openclaw/clawhub#937",
            "openclaw/clawhub#951",
            "openclaw/clawhub#2126",
            "openclaw/clawhub#1110",
            "openclaw/clawhub#1712"
        ])
    }
}

@discardableResult
private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus != 0 {
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8) ?? "git failed"
        throw NSError(domain: "GitHubReferenceMonitorTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
    }
    return String(data: data, encoding: .utf8) ?? ""
}
