import AppKit
@testable import RepoBar
@testable import RepoBarCore
import Testing

@MainActor
struct GitHubReferenceMonitorTests {
    @Test
    func `bare numbers and issue prefixes become issue queries`() {
        #expect(GitHubReferenceMonitor.query(from: "73655") == .issueNumber(73655))
        #expect(GitHubReferenceMonitor.query(from: "7") == .issueNumber(7))
        #expect(GitHubReferenceMonitor.query(from: "#7") == .issueNumber(7))
        #expect(GitHubReferenceMonitor.query(from: "gh-42") == .issueNumber(42))
        #expect(GitHubReferenceMonitor.query(from: " #78096. ") == .issueNumber(78096))
        #expect(GitHubReferenceMonitor.query(from: "a73655") == nil)
    }

    @Test
    func `commit hashes become commit queries`() {
        #expect(GitHubReferenceMonitor.query(from: "4992546") == .commitHash("4992546"))
        #expect(GitHubReferenceMonitor.query(from: " - bare short SHA: 4992546") == .commitHash("4992546"))
        #expect(GitHubReferenceMonitor.query(from: "ffd212ca43") == .commitHash("ffd212ca43"))
        #expect(
            GitHubReferenceMonitor.query(from: "d04517cefff3af339f560a8e388cacc3898e6562") ==
                .commitHash("d04517cefff3af339f560a8e388cacc3898e6562")
        )
        #expect(GitHubReferenceMonitor.query(from: "1234567") == .commitHash("1234567"))
        #expect(GitHubReferenceMonitor.query(from: "abcdef") == nil)
    }

    @Test
    func `owner repo issue shorthand becomes repository scoped issue query`() {
        #expect(
            GitHubReferenceMonitor.query(from: "steipete/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
        #expect(
            GitHubReferenceMonitor.query(from: "openclaw/clawsweeper#57") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/clawsweeper", number: 57)
        )
        #expect(
            GitHubReferenceMonitor.query(from: " steipete/summarize#215. ") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
        #expect(
            GitHubReferenceMonitor.query(from: "  - scoped issue shorthand: steipete/summarize#215") ==
                .repositoryIssueNumber(repositoryFullName: "steipete/summarize", number: 215)
        )
    }

    @Test
    func `github issue and pr urls become repository scoped issue queries`() {
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/issues/73655") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 73655)
        )
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/pull/123") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 123)
        )
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/issues/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 1_234_567)
        )
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/pull/1234567") ==
                .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 1_234_567)
        )
    }

    @Test
    func `github commit urls become repository scoped commit queries`() {
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/commit/ffd212ca43abcdef") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "ffd212ca43abcdef")
        )
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/commits/ffd212ca43") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "ffd212ca43")
        )
        #expect(
            GitHubReferenceMonitor.query(from: "https://github.com/openclaw/openclaw/pull/57843/changes/d04517cefff3af339f560a8e388cacc3898e6562") ==
                .repositoryCommitHash(repositoryFullName: "openclaw/openclaw", hash: "d04517cefff3af339f560a8e388cacc3898e6562")
        )
    }

    @Test
    func `pasteboard polling reports copied github references`() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RepoBarTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let stream = AsyncStream<GitHubReferenceQuery> { continuation in
            let monitor = GitHubReferenceMonitor(pasteboard: pasteboard) { query in
                continuation.yield(query)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in monitor.stop() }
            }
            monitor.start()
        }

        pasteboard.clearContents()
        pasteboard.setString("https://github.com/openclaw/openclaw/issues/76162", forType: .string)

        let query = try await self.nextQuery(from: stream)
        #expect(query == .repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 76162))
        pasteboard.clearContents()
    }

    @Test
    func `pasteboard polling clears copied non references`() async throws {
        enum Event: Equatable, Sendable {
            case clear
            case query(GitHubReferenceQuery)
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RepoBarTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let stream = AsyncStream<Event> { continuation in
            let monitor = GitHubReferenceMonitor(
                pasteboard: pasteboard,
                onPasteboardWithoutReference: {
                    continuation.yield(.clear)
                },
                onReference: { query in
                    continuation.yield(.query(query))
                }
            )
            continuation.onTermination = { _ in
                Task { @MainActor in monitor.stop() }
            }
            monitor.start()
        }

        pasteboard.clearContents()
        pasteboard.setString("https://github.com/openclaw/openclaw/issues/76162", forType: .string)
        #expect(
            try await self.nextValue(from: stream) ==
                .query(.repositoryIssueNumber(repositoryFullName: "openclaw/openclaw", number: 76162))
        )

        pasteboard.clearContents()
        pasteboard.setString("no github reference here", forType: .string)
        #expect(try await self.nextValue(from: stream) == .clear)
        pasteboard.clearContents()
    }

    private func nextQuery(from stream: AsyncStream<GitHubReferenceQuery>) async throws -> GitHubReferenceQuery {
        try await self.nextValue(from: stream)
    }

    private func nextValue<Value: Sendable>(from stream: AsyncStream<Value>) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                for await value in stream {
                    return value
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw CancellationError()
            }
            let value = try await #require(group.next())
            group.cancelAll()
            return value
        }
    }
}
