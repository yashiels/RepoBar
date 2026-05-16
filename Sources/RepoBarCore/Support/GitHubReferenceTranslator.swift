import Foundation

public enum GitHubReferenceTranslator {
    public static let defaultMinimumBareDigits = 1
    private static let maxScannedTextLength = 8000
    private static let maxIssueSeriesCount = 100

    public static func query(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits
    ) -> GitHubReferenceQuery? {
        self.queries(from: rawText, minimumBareDigits: minimumBareDigits).first
    }

    public static func queries(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits,
        repositoryContextOverride: String? = nil
    ) -> [GitHubReferenceQuery] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = self.urlQuery(from: text) {
            return [query]
        }

        if let query = self.tokenQuery(
            from: text,
            minimumBareDigits: minimumBareDigits,
            allowBareIssueNumber: true,
            allowNumericCommitHash: true
        ) {
            return [self.applyingRepositoryContext(repositoryContextOverride, to: query)]
        }

        guard text.count <= Self.maxScannedTextLength else { return [] }

        let tokens = self.referenceTokens(in: text)
        let repositoryContext = repositoryContextOverride
            ?? self.repositoryContext(in: tokens)
            ?? self.listItemRepositoryContext(in: text)
        if tokens.contains(where: { self.urlQuery(from: $0) != nil }) {
            let primaryListQueries = self.primaryListItemQueries(
                in: text,
                repositoryContext: repositoryContext
            )
            if primaryListQueries.count >= 2 {
                return primaryListQueries
            }
        }

        var queries: [GitHubReferenceQuery] = []
        var seen: Set<String> = []
        func append(_ query: GitHubReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        for token in tokens {
            if let query = self.urlQuery(from: token) {
                append(query)
            }
            for query in self.compoundRepositoryIssueQueries(from: token) {
                append(query)
            }
        }

        let groupedQueries = self.groupedRepositoryIssueQueries(in: text)
        let lineScopedQueries = self.lineScopedRepositoryIssueQueries(in: text)
        let scopedIssueNumbers = Set((groupedQueries + lineScopedQueries).compactMap { query in
            if case let .repositoryIssueNumber(_, number) = query {
                return number
            }
            return nil
        })
        for query in groupedQueries {
            append(query)
        }
        for query in lineScopedQueries {
            append(query)
        }

        let allowsNumericCommitHash = self.hasCommitContext(text)
        for token in tokens {
            if let query = self.tokenQuery(
                from: token,
                minimumBareDigits: minimumBareDigits,
                allowBareIssueNumber: false,
                allowNumericCommitHash: allowsNumericCommitHash
            ) {
                if case let .issueNumber(number) = query, scopedIssueNumbers.contains(number) {
                    continue
                }
                append(self.applyingRepositoryContext(repositoryContext, to: query))
            }
        }

        return queries
    }

    private static func primaryListItemQueries(
        in text: String,
        repositoryContext: String?
    ) -> [GitHubReferenceQuery] {
        let allowsNumericCommitHash = self.hasCommitContext(text)
        var queries: [GitHubReferenceQuery] = []
        var seen: Set<String> = []

        func append(_ query: GitHubReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let body = self.listItemBody(in: line),
                  let firstToken = self.referenceTokens(in: body).first
            else { continue }

            if let query = self.urlQuery(from: firstToken) {
                append(query)
                continue
            }

            let compoundQueries = self.compoundRepositoryIssueQueries(from: firstToken)
            if compoundQueries.isEmpty == false {
                compoundQueries.forEach(append)
                continue
            }

            guard let query = self.tokenQuery(
                from: firstToken,
                minimumBareDigits: 1,
                allowBareIssueNumber: false,
                allowNumericCommitHash: allowsNumericCommitHash
            ) else { continue }

            append(self.applyingRepositoryContext(repositoryContext, to: query))
        }

        return queries
    }

    private static func listItemBody(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var digitEnd = trimmed.startIndex
        while digitEnd < trimmed.endIndex, trimmed[digitEnd].isNumber {
            digitEnd = trimmed.index(after: digitEnd)
        }
        guard digitEnd > trimmed.startIndex,
              digitEnd < trimmed.endIndex,
              trimmed[digitEnd] == "." || trimmed[digitEnd] == ")"
        else { return nil }

        let markerEnd = trimmed.index(after: digitEnd)
        guard markerEnd == trimmed.endIndex || trimmed[markerEnd].isWhitespace else { return nil }

        return String(trimmed[markerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func groupedRepositoryIssueQueries(in text: String) -> [GitHubReferenceQuery] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { self.groupedRepositoryIssueQueries(inLine: String($0)) }
    }

    private static func groupedRepositoryIssueQueries(inLine line: String) -> [GitHubReferenceQuery] {
        guard let colon = line.firstIndex(of: ":") else { return [] }

        let prefixTokens = self.referenceTokens(in: String(line[..<colon]))
        guard let repositoryFullName = prefixTokens.last(where: self.isRepositoryFullName) else { return [] }

        return self.referenceTokens(in: String(line[line.index(after: colon)...]))
            .compactMap { token in
                guard let number = self.issueNumber(from: token, minimumBareDigits: 1, allowBareNumber: false) else {
                    return nil
                }

                return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
            }
    }

    private static func lineScopedRepositoryIssueQueries(in text: String) -> [GitHubReferenceQuery] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { self.lineScopedRepositoryIssueQueries(inLine: String($0)) }
    }

    private static func lineScopedRepositoryIssueQueries(inLine line: String) -> [GitHubReferenceQuery] {
        let tokens = self.referenceTokens(in: line)
        guard tokens.count >= 2 else { return [] }

        var queries: [GitHubReferenceQuery] = []
        for index in tokens.indices.dropLast() {
            let repositoryFullName = tokens[index]
            guard self.isRepositoryFullName(repositoryFullName),
                  let number = self.issueNumber(
                      from: tokens[tokens.index(after: index)],
                      minimumBareDigits: 1,
                      allowBareNumber: false
                  )
            else { continue }

            queries.append(.repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number))
        }
        return queries
    }

    private static func tokenQuery(
        from rawToken: String,
        minimumBareDigits: Int,
        allowBareIssueNumber: Bool,
        allowNumericCommitHash: Bool
    ) -> GitHubReferenceQuery? {
        let token = self.normalizedToken(from: rawToken)
        guard token.isEmpty == false else { return nil }

        if let scopedIssue = self.repositoryIssueNumber(from: token) {
            return scopedIssue
        }
        if let namedIssue = self.repositoryNameIssueNumber(from: token) {
            return namedIssue
        }
        if self.isCommitHash(token, allowNumericOnly: allowNumericCommitHash) {
            return .commitHash(token.lowercased())
        }
        if let number = self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: allowBareIssueNumber) {
            return .issueNumber(number)
        }
        return nil
    }

    private static func urlQuery(from rawText: String) -> GitHubReferenceQuery? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased().hasPrefix("http") == true
        else { return nil }

        let host = components.host?.lowercased() ?? ""
        guard host == "github.com" || host.hasSuffix(".github.com") else { return nil }

        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
        guard pathParts.count >= 4 else { return nil }

        let repositoryFullName = "\(pathParts[0])/\(pathParts[1])"
        switch pathParts[2].lowercased() {
        case "issues":
            guard let number = Int(pathParts[3]) else { return nil }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case "pull":
            if let hash = self.commitHash(in: pathParts.dropFirst(4)) {
                return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
            }
            guard let number = Int(pathParts[3]) else { return nil }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case "commit", "commits":
            let hash = pathParts[3].lowercased()
            guard self.isCommitHash(hash, allowNumericOnly: true) else { return nil }

            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        case "actions":
            guard pathParts.count >= 5,
                  pathParts[3].lowercased() == "runs",
                  let runID = Int64(pathParts[4])
            else { return nil }

            return .repositoryWorkflowRun(repositoryFullName: repositoryFullName, runID: runID)
        default:
            guard let hash = self.commitHash(in: pathParts.dropFirst(2)) else { return nil }

            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        }
    }

    private static func commitHash(in pathParts: some Sequence<String>) -> String? {
        pathParts
            .map { $0.lowercased() }
            .first { self.isCommitHash($0, allowNumericOnly: true) }
    }

    private static func issueNumber(from token: String, minimumBareDigits: Int, allowBareNumber: Bool) -> Int? {
        if token.hasPrefix("#") {
            return Int(token.dropFirst())
        }
        if token.lowercased().hasPrefix("gh-") {
            return Int(token.dropFirst(3))
        }
        guard allowBareNumber else { return nil }
        guard token.count >= minimumBareDigits,
              token.allSatisfy(\.isNumber)
        else { return nil }

        return Int(token)
    }

    private static func repositoryIssueNumber(from token: String) -> GitHubReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryFullName(parts[0])
        else { return nil }

        return .repositoryIssueNumber(repositoryFullName: parts[0], number: number)
    }

    private static func repositoryNameIssueNumber(from token: String) -> GitHubReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryName(parts[0])
        else { return nil }

        return .repositoryNameIssueNumber(repositoryName: parts[0], number: number)
    }

    private static func compoundRepositoryIssueQueries(from token: String) -> [GitHubReferenceQuery] {
        let parts = token.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              self.isRepositoryFullName(parts[0]),
              parts[1].contains("/") || parts[1].contains("-")
        else { return [] }

        let numberParts = parts[1]
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard numberParts.isEmpty == false else { return [] }

        var numbers: [Int] = []
        for numberPart in numberParts {
            guard let parsedNumbers = self.issueNumbers(fromSeriesPart: numberPart)
            else { return [] }

            numbers.append(contentsOf: parsedNumbers)
        }
        guard (1 ... Self.maxIssueSeriesCount).contains(numbers.count) else { return [] }

        return numbers.map { .repositoryIssueNumber(repositoryFullName: parts[0], number: $0) }
    }

    private static func issueNumbers(fromSeriesPart rawPart: String) -> [Int]? {
        let part = rawPart.hasPrefix("#") ? String(rawPart.dropFirst()) : rawPart
        guard part.isEmpty == false else { return nil }

        let rangeParts = part
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        if rangeParts.count == 2 {
            guard let start = self.issueSeriesNumber(from: rangeParts[0]),
                  let end = self.issueSeriesNumber(from: rangeParts[1]),
                  start <= end
            else { return nil }

            return Array(start ... end)
        }

        guard let number = self.issueSeriesNumber(from: part) else { return nil }

        return [number]
    }

    private static func issueSeriesNumber(from rawNumber: String) -> Int? {
        let normalized = rawNumber.hasPrefix("#") ? String(rawNumber.dropFirst()) : rawNumber
        guard normalized.isEmpty == false,
              normalized.allSatisfy(\.isNumber)
        else { return nil }

        return Int(normalized)
    }

    private static func isRepositoryFullName(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }

        return parts.allSatisfy { part in
            part.isEmpty == false && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
            }
        }
    }

    private static func isRepositoryName(_ value: String) -> Bool {
        value.isEmpty == false && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }

    private static func repositoryContext(in tokens: [String]) -> String? {
        var repositoryFullNames: [String] = []
        var seen: Set<String> = []

        func append(_ repositoryFullName: String) {
            guard seen.insert(repositoryFullName.lowercased()).inserted else { return }

            repositoryFullNames.append(repositoryFullName)
        }

        for (index, token) in tokens.enumerated() {
            if token.contains("#") == false, self.isRepositoryFullName(token), self.isLikelyRepositoryContextToken(at: index, in: tokens) {
                append(token)
                continue
            }
            if let repositoryFullName = self.urlQuery(from: token)?.repositoryFullName {
                append(repositoryFullName)
                continue
            }
            if let repositoryFullName = self.repositoryIssueNumber(from: token)?.repositoryFullName {
                append(repositoryFullName)
            }
        }

        return repositoryFullNames.count == 1 ? repositoryFullNames[0] : nil
    }

    private static func listItemRepositoryContext(in text: String) -> String? {
        let repositories = text
            .split(whereSeparator: \.isNewline)
            .compactMap { self.listItemBody(in: String($0)) }
            .compactMap { body -> String? in
                let tokens = self.referenceTokens(in: body)
                guard tokens.count == 1,
                      let repositoryFullName = tokens.first,
                      self.isRepositoryFullName(repositoryFullName)
                else { return nil }

                return repositoryFullName
            }

        var uniqueRepositories: [String] = []
        var seen: Set<String> = []
        for repository in repositories {
            guard seen.insert(repository.lowercased()).inserted else { continue }

            uniqueRepositories.append(repository)
        }

        return uniqueRepositories.count == 1 ? uniqueRepositories[0] : nil
    }

    private static func isLikelyRepositoryContextToken(at index: Int, in tokens: [String]) -> Bool {
        guard tokens.indices.contains(index) else { return false }
        guard index > 0 else { return true }

        let previous = tokens[index - 1].lowercased()
        return ["in", "repo", "repository", "from", "for", "on", "inside"].contains(previous)
    }

    private static func applyingRepositoryContext(_ repositoryFullName: String?, to query: GitHubReferenceQuery) -> GitHubReferenceQuery {
        guard let repositoryFullName else { return query }

        switch query {
        case let .issueNumber(number):
            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .repositoryNameIssueNumber(repositoryName, number):
            guard repositoryFullName.split(separator: "/").last?.caseInsensitiveCompare(repositoryName) == .orderedSame else {
                return query
            }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .commitHash(hash):
            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        case .repositoryIssueNumber, .repositoryCommitHash, .repositoryWorkflowRun:
            return query
        }
    }

    private static func normalizedToken(from rawToken: String) -> String {
        rawToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}<>\"'`"))
    }

    private static func referenceTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(self.normalizedToken)
            .filter { $0.isEmpty == false }
    }

    private static func hasCommitContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("sha") || normalized.contains("commit") || normalized.contains("hash")
    }

    private static func dedupeKey(for query: GitHubReferenceQuery) -> String {
        switch query {
        case let .issueNumber(number):
            "issue:\(number)"
        case let .repositoryNameIssueNumber(repositoryName, number):
            "repo-name:\(repositoryName.lowercased())#\(number)"
        case let .repositoryIssueNumber(repositoryFullName, number):
            "repo:\(repositoryFullName.lowercased())#\(number)"
        case let .commitHash(hash):
            "commit:\(hash.lowercased())"
        case let .repositoryCommitHash(repositoryFullName, hash):
            "repo:\(repositoryFullName.lowercased())@\(hash.lowercased())"
        case let .repositoryWorkflowRun(repositoryFullName, runID):
            "repo:\(repositoryFullName.lowercased())/run/\(runID)"
        }
    }

    private static func isCommitHash(_ token: String, allowNumericOnly: Bool) -> Bool {
        guard (7 ... 40).contains(token.count) else { return false }
        guard token.allSatisfy(\.isHexDigit) else { return false }
        guard allowNumericOnly || token.contains(where: \.isLetter) else { return false }

        return true
    }
}
