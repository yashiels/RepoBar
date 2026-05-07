import Foundation

public enum GitHubReferenceKind: String, Sendable, Hashable {
    case issue
    case pullRequest
    case commit

    public var label: String {
        switch self {
        case .issue: "Issue"
        case .pullRequest: "Pull Request"
        case .commit: "Commit"
        }
    }
}

public enum GitHubReferenceState: String, Sendable, Hashable {
    case open
    case closed

    public var label: String {
        switch self {
        case .open: "Open"
        case .closed: "Closed"
        }
    }
}

public enum GitHubReferenceQuery: Sendable, Hashable {
    case issueNumber(Int)
    case repositoryIssueNumber(repositoryFullName: String, number: Int)
    case commitHash(String)
    case repositoryCommitHash(repositoryFullName: String, hash: String)

    public var displayText: String {
        switch self {
        case let .issueNumber(number): "#\(number)"
        case let .repositoryIssueNumber(repositoryFullName, number): "\(repositoryFullName)#\(number)"
        case let .commitHash(hash): String(hash.prefix(10))
        case let .repositoryCommitHash(repositoryFullName, hash): "\(repositoryFullName)@\(hash.prefix(10))"
        }
    }

    public var repositoryFullName: String? {
        switch self {
        case .issueNumber, .commitHash:
            nil
        case let .repositoryIssueNumber(repositoryFullName, _),
             let .repositoryCommitHash(repositoryFullName, _):
            repositoryFullName
        }
    }

    public var repositoryOwnerAndName: (owner: String, name: String)? {
        guard let repositoryFullName else { return nil }

        let parts = repositoryFullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else {
            return nil
        }
        return (parts[0], parts[1])
    }
}

public struct GitHubReferenceMatch: Sendable, Hashable {
    public let query: GitHubReferenceQuery
    public let title: String
    public let url: URL
    public let repositoryFullName: String
    public let kind: GitHubReferenceKind
    public let state: GitHubReferenceState?
    public let createdAt: Date?
    public let updatedAt: Date

    public init(
        query: GitHubReferenceQuery,
        title: String,
        url: URL,
        repositoryFullName: String,
        kind: GitHubReferenceKind,
        state: GitHubReferenceState?,
        createdAt: Date?,
        updatedAt: Date
    ) {
        self.query = query
        self.title = title
        self.url = url
        self.repositoryFullName = repositoryFullName
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func newestCreated(in matches: [GitHubReferenceMatch]) -> GitHubReferenceMatch? {
        matches.max { lhs, rhs in
            let lhsDate = lhs.createdAt ?? lhs.updatedAt
            let rhsDate = rhs.createdAt ?? rhs.updatedAt
            if lhsDate == rhsDate {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhsDate < rhsDate
        }
    }
}
