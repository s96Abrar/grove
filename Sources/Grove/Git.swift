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

    static func remove(_ tree: Worktree, at root: String) throws {
        guard tree.path != root else { throw CommandError(message: "The main checkout cannot be removed.") }
        guard try run(["status", "--porcelain", "--untracked-files=all"], at: tree.path).isEmpty else { throw CommandError(message: "This worktree has uncommitted files. Commit or move them before removing it.") }
        _ = try run(["worktree", "remove", "--", tree.path], at: root)
    }
    static func rename(_ branch: String, at path: String) throws {
        _ = try run(["check-ref-format", "--branch", branch], at: path)
        _ = try run(["branch", "-m", "--", branch], at: path)
    }
    static func create(branch: String, at root: String, baseRef: String = "HEAD") throws -> String {
        guard !branch.isEmpty, branch.count <= 100, !branch.hasPrefix("-"),
              branch.range(of: #"^[A-Za-z0-9][A-Za-z0-9_/-]*$"#, options: .regularExpression) != nil else {
            throw CommandError(message: "Use a branch name with letters, numbers, slashes, underscores or hyphens.")
        }
        _ = try run(["check-ref-format", "--branch", branch], at: root)
        guard !baseRef.hasPrefix("-"), !baseRef.isEmpty else { throw CommandError(message: "Choose a valid base reference.") }
        let commit = try run(["rev-parse", "--verify", baseRef + "^{commit}"], at: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = URL(fileURLWithPath: root).deletingLastPathComponent()
            .appendingPathComponent(".grove-worktrees").appendingPathComponent(URL(fileURLWithPath: root).lastPathComponent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + branch.replacingOccurrences(of: "/", with: "-")).path
        _ = try run(["worktree", "add", "-b", branch, destination, commit], at: root)
        return try run(["rev-parse", "--show-toplevel"], at: destination).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
