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
}
