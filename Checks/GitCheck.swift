import Foundation
@main struct GitCheck {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-check-\(UUID().uuidString)")
        let repo = base.appendingPathComponent("repo with spaces")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        // All mutations are confined to a fresh temporary repository.
        _ = try Git.run(["init", "-b", "main"], at: repo.path)
        _ = try Git.run(["-c", "user.name=Grove Check", "-c", "user.email=check@example.test", "commit", "--allow-empty", "-m", "initial"], at: repo.path)
        let path = try Git.create(branch: "feature/check", at: repo.path)
        let trees = try Git.list(at: repo.path)
        precondition(trees.count == 2)
        precondition(trees.contains(Worktree(path: path, branch: "feature/check")))
        let file = URL(fileURLWithPath: path).appendingPathComponent("task.txt")
        try "isolated".write(to: file, atomically: true, encoding: .utf8)
        precondition(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("task.txt").path))
        let status = try Git.run(["status", "--short"], at: path)
        precondition(status.contains("task.txt"))
        _ = try Git.run(["add", "task.txt"], at: path)
        let diff = try Git.run(["diff", "HEAD", "--"], at: path)
        precondition(diff.contains("+isolated"))
        do { _ = try Git.create(branch: "../bad", at: repo.path); fatalError("Invalid branch accepted") } catch {}
        do { _ = try Git.create(branch: "feature/check", at: repo.path); fatalError("Duplicate branch accepted") } catch {}
        do { try Git.remove(Worktree(path: repo.path, branch: "main"), at: repo.path); fatalError("Main worktree removal accepted") } catch {}
        do { try Git.remove(Worktree(path: path, branch: "feature/check"), at: repo.path); fatalError("Dirty worktree removal accepted") } catch {}
        try Git.rename("feature/renamed", at: path)
        let renamed = try Git.list(at: repo.path)
        precondition(renamed.contains { $0.branch == "feature/renamed" })
        let cleanPath = try Git.create(branch: "feature/clean", at: repo.path, baseRef: "main")
        try Git.remove(Worktree(path: cleanPath, branch: "feature/clean"), at: repo.path)
        precondition(!FileManager.default.fileExists(atPath: cleanPath))
        let ignoredPath = try Git.create(branch: "feature/ignored", at: repo.path)
        let ignoreFile = URL(fileURLWithPath: ignoredPath).appendingPathComponent(".gitignore")
        try ".env\n".write(to: ignoreFile, atomically: true, encoding: .utf8)
        _ = try Git.run(["add", ".gitignore"], at: ignoredPath)
        _ = try Git.run(["-c", "user.name=Grove Check", "-c", "user.email=check@example.test", "commit", "-m", "ignore local config"], at: ignoredPath)
        let ignoredFile = URL(fileURLWithPath: ignoredPath).appendingPathComponent(".env")
        try "local-only".write(to: ignoredFile, atomically: true, encoding: .utf8)
        do { try Git.remove(Worktree(path: ignoredPath, branch: "feature/ignored"), at: repo.path); fatalError("Ignored files were removed") } catch {}
        precondition(FileManager.default.fileExists(atPath: ignoredFile.path))
        print("PASS: worktree discovery, paths with spaces, branch creation, file isolation, staged diff, invalid/duplicate branches, rename, base ref, dirty/main/ignored-file removal rejection, clean removal")
        print("Fixture: \(base.path)")
    }
}
