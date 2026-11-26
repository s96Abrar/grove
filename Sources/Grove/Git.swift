import Foundation

struct Worktree: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let branch: String
}

struct CommandError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Git {
    static func run(_ args: [String], at path: String) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + args
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw CommandError(message: output) }
        return output
    }

    static func list(at path: String) throws -> [Worktree] {
        let output = try run(["worktree", "list", "--porcelain", "-z"], at: path)
        var result: [Worktree] = [], current: String?, branch = "detached HEAD"
        for field in output.components(separatedBy: "\0") {
            if field.hasPrefix("worktree ") {
                if let current { result.append(Worktree(path: current, branch: branch)) }
                current = String(field.dropFirst(9)); branch = "detached HEAD"
            } else if field.hasPrefix("branch refs/heads/") { branch = String(field.dropFirst(18)) }
        }
        if let current { result.append(Worktree(path: current, branch: branch)) }
        return result
    }

    static func validateRemoval(_ tree: Worktree, at root: String) throws {
        guard tree.path != root else { throw CommandError(message: "The main checkout cannot be removed.") }
        let fields = try run(["worktree", "list", "--porcelain", "-z"], at: root).components(separatedBy: "\0")
        var currentPath = "", firstPath: String?, registered = false
        for field in fields {
            if field.hasPrefix("worktree ") {
                currentPath = String(field.dropFirst(9))
                if firstPath == nil { firstPath = currentPath }
                if currentPath == tree.path { registered = true }
            } else if currentPath == tree.path && (field == "locked" || field.hasPrefix("locked ")) {
                throw CommandError(message: "This worktree is locked. Unlock it in Git before removing it.")
            }
        }
        guard registered else { throw CommandError(message: "This worktree is no longer registered in the repository.") }
        guard tree.path != firstPath else { throw CommandError(message: "The main checkout cannot be removed.") }
        guard try run(["status", "--porcelain", "--untracked-files=all", "--ignored"], at: tree.path).isEmpty else { throw CommandError(message: "This worktree has uncommitted files. Commit or move them before removing it.") }
    }
    static func remove(_ tree: Worktree, at root: String) throws {
        try validateRemoval(tree, at: root)
        _ = try run(["worktree", "remove", "--", tree.path], at: root)
    }
    static func rename(_ branch: String, at path: String) throws {
        _ = try run(["check-ref-format", "--branch", branch], at: path)
        _ = try run(["branch", "-m", "--", branch], at: path)
    }
    /// Why a new branch name is not accepted, or nil when it is (an empty
    /// name is "not finished yet", not an error). Shared by the inline
    /// validation in the UI and by `create`.
    static func branchNameProblem(_ branch: String) -> String? {
        if branch.isEmpty { return nil }
        if branch.count > 100 { return "Use at most 100 characters." }
        if branch.hasPrefix("-") { return "A branch name cannot start with a hyphen." }
        if branch.range(of: #"^[A-Za-z0-9][A-Za-z0-9_/-]*$"#, options: .regularExpression) == nil {
            return "Use letters, numbers, slashes, underscores or hyphens, starting with a letter or number."
        }
        if branch.contains("//") || branch.hasSuffix("/") { return "Slashes must separate non-empty parts." }
        return nil
    }
    static func create(branch: String, at root: String, baseRef: String = "HEAD") throws -> String {
        guard !branch.isEmpty, branchNameProblem(branch) == nil else {
            throw CommandError(message: branchNameProblem(branch) ?? "Enter a branch name.")
        }
        _ = try run(["check-ref-format", "--branch", branch], at: root)
        guard !baseRef.hasPrefix("-"), !baseRef.isEmpty else { throw CommandError(message: "Choose a valid base reference.") }
        let commit = try run(["rev-parse", "--verify", baseRef + "^{commit}"], at: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = URL(fileURLWithPath: root).deletingLastPathComponent()
            .appendingPathComponent(".grove-worktrees").appendingPathComponent(URL(fileURLWithPath: root).lastPathComponent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + branch.replacingOccurrences(of: "/", with: "-")).path
        guard !FileManager.default.fileExists(atPath: destination) else { throw CommandError(message: "The new checkout destination already exists.") }
        do { _ = try run(["worktree", "add", "-b", branch, destination, commit], at: root) }
        catch {
            let failure = error.localizedDescription
            do {
                // Use Git's exact registered-checkout removal, which respects locks.
                // A broad prune could erase unrelated temporarily missing checkouts.
                let physical = URL(fileURLWithPath: destination).resolvingSymlinksInPath().path
                let registered = try list(at: root).contains {
                    URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == physical
                }
                if registered {
                    _ = try run(["worktree", "remove", "--force", "--", destination], at: root)
                } else if FileManager.default.fileExists(atPath: destination) {
                    try FileManager.default.removeItem(atPath: destination)
                }
            } catch {
                throw CommandError(message: failure + "\nCheckout cleanup is incomplete: " + error.localizedDescription)
            }
            // A post-checkout hook may have made commits: never delete that branch.
            throw CommandError(message: failure + "\nThe failed checkout was cleaned up. Any created branch was kept; inspect it before retrying.")
        }
        return try run(["rev-parse", "--show-toplevel"], at: destination).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
