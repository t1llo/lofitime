import Darwin
import Foundation

/// Authentication stays with gh (including its Keychain integration); tokens never enter app storage.
public struct GitHubCLI: GitHubAPI {
    private let executable: URL?
    private let timeout: TimeInterval

    public init(executable: URL? = nil, timeout: TimeInterval = 45) {
        self.executable = executable
        self.timeout = timeout
    }

    public func request(_ method: String, endpoint: String, body: Data?) async throws -> GitHubResponse {
        try Task.checkCancellation()
        guard let executable = executable ?? Self.findExecutable() else { throw GitHubSyncError.cliMissing }
        var arguments = ["api", "--hostname", "github.com", "--include", "--method", method,
                         "-H", "Accept: application/vnd.github+json", "-H", "X-GitHub-Api-Version: 2022-11-28", endpoint]
        if body != nil { arguments += ["--input", "-"] }
        let command = Command(executable: executable, arguments: arguments, input: body, timeout: timeout)
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try command.run()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            command.stop(cancelled: true)
        }
        try Task.checkCancellation()
        return try Self.parse(output.stdout, stderr: output.stderr)
    }

    private static func findExecutable() -> URL? {
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let paths = environmentPaths + ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("gh") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func parse(_ data: Data, stderr: Data) throws -> GitHubResponse {
        // gh --include writes the status and headers to stdout even for non-2xx HTTP responses.
        var remaining = data
        while true {
            let delimiter = remaining.range(of: Data("\r\n\r\n".utf8)) ?? remaining.range(of: Data("\n\n".utf8))
            guard let delimiter,
                  let header = String(data: remaining[..<delimiter.lowerBound], encoding: .utf8),
                  let firstLine = header.components(separatedBy: .newlines).first,
                  firstLine.hasPrefix("HTTP/"), let status = Int(firstLine.split(separator: " ").dropFirst().first ?? "") else {
                let error = String(data: stderr, encoding: .utf8) ?? ""
                if error.contains("gh auth login") || error.contains("not logged into") { throw GitHubSyncError.signIn }
                throw GitHubSyncError.unavailable
            }
            remaining = Data(remaining[delimiter.upperBound...])
            if (100..<200).contains(status) { continue }
            return GitHubResponse(status: status, body: remaining)
        }
    }

    private struct Output { let stdout: Data; let stderr: Data }

    /// Blocking process work runs off the main actor. Files avoid pipe-buffer deadlocks with large histories.
    private final class Command: @unchecked Sendable {
        private let lock = NSLock()
        private let executable: URL
        private let arguments: [String]
        private let input: Data?
        private let timeout: TimeInterval
        private var process: Process?
        private var cancelled = false
        private var timedOut = false

        init(executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) {
            self.executable = executable
            self.arguments = arguments
            self.input = input
            self.timeout = timeout
        }

        func stop(cancelled: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if cancelled { self.cancelled = true } else { timedOut = true }
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        func run() throws -> Output {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lofitime-sync-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let inputURL = directory.appendingPathComponent("input")
            let outputURL = directory.appendingPathComponent("output")
            let errorURL = directory.appendingPathComponent("error")
            for (url, data) in [(inputURL, input ?? Data()), (outputURL, Data()), (errorURL, Data())] {
                guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                    throw GitHubSyncError.unavailable
                }
            }
            let stdin = try FileHandle(forReadingFrom: inputURL)
            defer { try? stdin.close() }
            let stdout = try FileHandle(forWritingTo: outputURL)
            defer { try? stdout.close() }
            let stderr = try FileHandle(forWritingTo: errorURL)
            defer { try? stderr.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            var environment = ProcessInfo.processInfo.environment
            environment["GH_PROMPT_DISABLED"] = "1"
            environment["GH_NO_UPDATE_NOTIFIER"] = "1"
            environment["GH_NO_EXTENSION_UPDATE_NOTIFIER"] = "1"
            environment["GH_PAGER"] = "cat"
            environment["NO_COLOR"] = "1"
            environment.removeValue(forKey: "GH_DEBUG")
            process.environment = environment

            lock.lock()
            if cancelled { lock.unlock(); throw CancellationError() }
            self.process = process
            do { try process.run() }
            catch { self.process = nil; lock.unlock(); throw GitHubSyncError.cliMissing }
            lock.unlock()
            let deadline = DispatchWorkItem { [weak self] in self?.stop(cancelled: false) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
            process.waitUntilExit()
            deadline.cancel()
            lock.lock()
            self.process = nil
            let wasCancelled = cancelled
            let wasTimedOut = timedOut
            lock.unlock()
            if wasCancelled { throw CancellationError() }
            if wasTimedOut { throw GitHubSyncError.timedOut }
            for url in [outputURL, errorURL] {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 32 * 1_024 * 1_024 else { throw GitHubSyncError.archiveTooLarge }
            }
            return Output(stdout: try Data(contentsOf: outputURL), stderr: try Data(contentsOf: errorURL))
        }
    }
}
