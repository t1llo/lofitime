import Foundation
import LofiMenCore

public struct GitHubResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol GitHubAPI: Sendable {
    func request(_ method: String, endpoint: String, body: Data?) async throws -> GitHubResponse
}

public struct GitHubSyncConnection: Codable, Equatable, Sendable {
    public let repository: String
    public let repositoryID: Int64
    public let account: String
}

public struct GitHubSyncClient: Sendable {
    public static let fileName = "lofitime-sessions.json"
    private let api: any GitHubAPI

    public init(api: any GitHubAPI = GitHubCLI()) { self.api = api }

    public static func validRepositoryName(_ name: String) -> Bool {
        name.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z"#, options: .regularExpression) != nil
    }

    public static func repository(from input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.contains("://") {
            guard let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "github.com", url.user == nil, url.password == nil,
                  url.port == nil || url.port == 443, url.query == nil, url.fragment == nil else {
                throw GitHubSyncError.invalidRepositoryLink
            }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].range(of: #"\A[A-Za-z0-9][A-Za-z0-9-]{0,38}\z"#, options: .regularExpression) != nil,
              validRepositoryName(String(parts[1])) else { throw GitHubSyncError.invalidRepositoryLink }
        return value
    }

    public func create(name: String) async throws -> GitHubSyncConnection {
        guard Self.validRepositoryName(name) else { throw GitHubSyncError.invalidName }
        let account = try await currentAccount()
        let fullName = "\(account)/\(name)"
        let response = try await api.request("POST", endpoint: "user/repos", body: JSONEncoder().encode(NewRepository(name: name)))
        if response.status == 422 { throw GitHubSyncError.repositoryExists }
        let repository: Repository = try decode(response)
        try repository.validate(expectedName: fullName)
        return GitHubSyncConnection(repository: repository.full_name, repositoryID: repository.id, account: account)
    }

    /// Connecting never creates a repository. Collaborators can connect using their own CLI login.
    public func connect(repository input: String) async throws -> GitHubSyncConnection {
        let fullName = try Self.repository(from: input)
        let account = try await currentAccount()
        let repository: Repository = try decode(await api.request("GET", endpoint: "repos/\(fullName)", body: nil))
        try repository.validate(expectedName: fullName)
        let connection = GitHubSyncConnection(repository: repository.full_name, repositoryID: repository.id, account: account)
        if try await readArchive(connection, branch: repository.default_branch) == nil {
            // Only initialize an empty repository, never add personal history to an unrelated project.
            let root = try await api.request("GET", endpoint: "repos/\(connection.repository)/contents", body: nil)
            if root.status != 404 {
                let files: [RootEntry] = try decode(root)
                if !files.isEmpty {
                    // The other Mac may have initialized sync between the two reads.
                    guard files.contains(where: { $0.name == Self.fileName }),
                          try await readArchive(connection, branch: repository.default_branch) != nil else {
                        throw GitHubSyncError.unrelatedRepository
                    }
                }
            }
        }
        return connection
    }

    public func synchronize(_ connection: GitHubSyncConnection, records: [SessionRecord]) async throws -> [SessionRecord] {
        let account = try await currentAccount()
        guard account.lowercased() == connection.account.lowercased() else { throw GitHubSyncError.accountChanged }
        var merged = try SessionSyncArchive.merge(records, [])
        for _ in 0..<4 {
            try Task.checkCancellation()
            // Recheck identity and privacy on every attempt, including conflict retries.
            let repository: Repository = try decode(await api.request("GET", endpoint: "repos/\(connection.repository)", body: nil))
            try repository.validate(expectedName: connection.repository)
            guard repository.id == connection.repositoryID else { throw GitHubSyncError.repositoryChanged }
            let remote = try await readArchive(connection, branch: repository.default_branch)
            merged = try SessionSyncArchive.merge(merged, remote?.archive.records ?? [])
            if let remote, merged == remote.archive.records { return merged }

            let archive = try SessionSyncArchive(records: merged).encoded()
            guard archive.count <= Self.maximumArchiveSize else { throw GitHubSyncError.archiveTooLarge }
            let update = UpdateFile(message: "Sync Lofitime focus sessions", content: archive.base64EncodedString(),
                                    sha: remote?.sha, branch: repository.default_branch)
            try Task.checkCancellation()
            let response = try await api.request("PUT", endpoint: "repos/\(connection.repository)/contents/\(Self.fileName)",
                                                 body: JSONEncoder().encode(update))
            if response.status == 409 || response.status == 422 {
                // Reload and merge again; never force-push over the other computer's sessions.
                continue
            }
            try check(response)
            return merged
        }
        throw GitHubSyncError.concurrentUpdate
    }

    private static let maximumArchiveSize = 20 * 1_024 * 1_024

    private func currentAccount() async throws -> String {
        let user: User = try decode(await api.request("GET", endpoint: "user", body: nil))
        guard user.login.range(of: #"\A[A-Za-z0-9][A-Za-z0-9-]*\z"#, options: .regularExpression) != nil else {
            throw GitHubSyncError.invalidResponse
        }
        return user.login
    }

    private func readArchive(_ connection: GitHubSyncConnection, branch: String) async throws -> RemoteArchive? {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "ref", value: branch)]
        let encodedQuery = (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        let endpoint = "repos/\(connection.repository)/contents/\(Self.fileName)?\(encodedQuery)"
        let response = try await api.request("GET", endpoint: endpoint, body: nil)
        if response.status == 404 { return nil }
        let file: ContentFile = try decode(response)
        guard file.type == "file", file.sha.range(of: #"\A[0-9a-f]{40,64}\z"#, options: .regularExpression) != nil else {
            throw GitHubSyncError.invalidResponse
        }
        guard file.size <= Self.maximumArchiveSize else { throw GitHubSyncError.archiveTooLarge }
        let content: String
        if file.encoding == "base64", let inline = file.content {
            content = inline
        } else {
            // The Contents API omits inline content above 1 MB. Fetch this exact revision.
            let blob: Blob = try decode(await api.request("GET", endpoint: "repos/\(connection.repository)/git/blobs/\(file.sha)", body: nil))
            guard blob.encoding == "base64" else { throw GitHubSyncError.invalidResponse }
            content = blob.content
        }
        let compact = content.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: compact), data.count <= Self.maximumArchiveSize else {
            throw GitHubSyncError.invalidResponse
        }
        return RemoteArchive(sha: file.sha, archive: try SessionSyncArchive.decode(data))
    }

    private func decode<T: Decodable>(_ response: GitHubResponse) throws -> T {
        try check(response)
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw GitHubSyncError.invalidResponse }
    }

    private func check(_ response: GitHubResponse) throws {
        switch response.status {
        case 200..<300: return
        case 401: throw GitHubSyncError.signIn
        case 403: throw GitHubSyncError.permission
        case 404: throw GitHubSyncError.notFound
        case 429: throw GitHubSyncError.rateLimited
        default: throw GitHubSyncError.unavailable
        }
    }

    private struct User: Decodable { let login: String }
    private struct RootEntry: Decodable { let name: String }
    private struct Repository: Decodable {
        let id: Int64
        let full_name: String
        let `private`: Bool
        let default_branch: String
        let archived: Bool
        let permissions: Permissions?

        struct Permissions: Decodable { let push: Bool }

        func validate(expectedName: String) throws {
            guard `private` else { throw GitHubSyncError.publicRepository }
            guard full_name.lowercased() == expectedName.lowercased() else { throw GitHubSyncError.repositoryChanged }
            guard !archived else { throw GitHubSyncError.archivedRepository }
            guard permissions?.push != false else { throw GitHubSyncError.permission }
        }
    }
    private struct NewRepository: Encodable {
        let name: String
        let `private` = true
        let description = "Private focus history for Lofitime sync"
        let auto_init = false
    }
    private struct ContentFile: Decodable {
        let type: String
        let sha: String
        let size: Int
        let encoding: String?
        let content: String?
    }
    private struct Blob: Decodable { let encoding: String; let content: String }
    private struct UpdateFile: Encodable {
        let message: String
        let content: String
        let sha: String?
        let branch: String
    }
    private struct RemoteArchive { let sha: String; let archive: SessionSyncArchive }
}

public enum GitHubSyncError: LocalizedError {
    case cliMissing, signIn, invalidName, invalidRepositoryLink, repositoryExists, publicRepository, archivedRepository, unrelatedRepository
    case accountChanged, repositoryChanged, notFound, permission, rateLimited, unavailable
    case invalidResponse, archiveTooLarge, concurrentUpdate, timedOut

    public var errorDescription: String? {
        switch self {
        case .cliMissing: "Install the GitHub CLI, then sign in with gh auth login to connect."
        case .signIn: "Sign in to github.com with gh auth login, then try again."
        case .invalidName: "Use a repository name starting with a letter or number, followed by letters, numbers, dots, hyphens, or underscores (up to 100 characters)."
        case .invalidRepositoryLink: "Paste a GitHub repository link, such as https://github.com/username/lofitime-sync."
        case .repositoryExists: "This repository already exists. Choose Connect to sync and paste its GitHub link."
        case .publicRepository: "This repository is public. Choose a private repository to sync your focus history."
        case .archivedRepository: "This repository is archived. Unarchive it on GitHub to resume syncing."
        case .unrelatedRepository: "This repository already contains other files. Choose an empty repository or an existing Lofitime sync repository."
        case .accountChanged: "The active GitHub account changed. Switch back with gh auth switch, or disconnect and connect again."
        case .repositoryChanged: "The repository was renamed or replaced. Disconnect and connect again to choose your sync repository."
        case .notFound: "The sync repository could not be found. Check your GitHub login and repository access."
        case .permission: "GitHub denied access or is limiting requests. Check repository permissions; for a CLI login, use gh auth refresh -h github.com -s repo."
        case .rateLimited: "GitHub is limiting requests. Lofitime will try again automatically."
        case .unavailable: "Could not reach GitHub. Your history is saved locally and will sync when GitHub is available."
        case .invalidResponse: "GitHub returned an unexpected response. Your local history is safe; try syncing again."
        case .archiveTooLarge: "This sync file is too large to process. Your local history is safe."
        case .concurrentUpdate: "Another Mac is updating the history. Lofitime will merge it on the next sync."
        case .timedOut: "GitHub took too long to respond. Your history is saved locally; Lofitime will try again."
        }
    }
}
