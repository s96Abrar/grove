import XCTest
import Combine
@testable import Grove

final class RegressionTests: XCTestCase {
    @MainActor private func fixture() throws -> (Workspace, Worktree, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-review-" + UUID().uuidString)
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        _ = try Git.run(["init", "-b", "main"], at: repo.path)
        _ = try Git.run(["-c", "user.name=Check", "-c", "user.email=check@example.test", "commit", "--allow-empty", "-m", "initial"], at: repo.path)
        let root = try Git.run(["rev-parse", "--show-toplevel"], at: repo.path).trimmingCharacters(in: .whitespacesAndNewlines)
        let path = try Git.create(branch: "task", at: root)
        let tree = Worktree(path: path, branch: "task")
        let model = Workspace(verificationPath: base.path)
        model.saved = SavedWorkspace(roots: [root], tabs: [path: [TabRecord(panes: [PaneRecord(command: "echo do-not-replay")])]])
        model.trees = [root: [Worktree(path: root, branch: "main"), tree]]
        model.selected = tree
        return (model, tree, base)
    }

    @MainActor func testDirtyAndMainRemovalKeepSessions() async throws {
        let (model, tree, _) = try fixture()
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        let session = model.session(pane)
        try "preserve".write(toFile: tree.path + "/untracked", atomically: true, encoding: .utf8)
        await model.remove(tree)
        XCTAssertTrue(model.sessions[pane.id] === session)
        XCTAssertEqual(session.state, "Starting")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tree.path))
        let main = model.trees[model.roots[0]]![0]
        model.saved.tabs[main.path] = [TabRecord()]
        let mainPane = model.saved.tabs[main.path]![0].panes[0]
        let mainSession = model.session(mainPane)
        await model.remove(main)
        XCTAssertTrue(model.sessions[mainPane.id] === mainSession)
        XCTAssertEqual(mainSession.state, "Starting")
    }

    @MainActor func testLockedRemovalKeepsSession() async throws {
        let (model, tree, _) = try fixture()
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        let session = model.session(pane)
        _ = try Git.run(["worktree", "lock", tree.path], at: model.roots[0])
        await model.remove(tree)
        XCTAssertTrue(model.sessions[pane.id] === session)
        XCTAssertEqual(session.state, "Starting")
        XCTAssertTrue(model.error?.contains("locked") == true)
    }

    @MainActor func testFailureAfterTeardownRetainsEndedSession() async throws {
        let (model, tree, _) = try fixture()
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        let session = model.session(pane)
        // Reproduce a checkout becoming dirty between preflight and final Git removal.
        let subscription = session.$state.sink { state in
            if state == "Ended" { try? "keep".write(toFile: tree.path + "/changed-during-teardown", atomically: true, encoding: .utf8) }
        }
        await model.remove(tree)
        withExtendedLifetime(subscription) {}
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.saved.tabs[tree.path])
        XCTAssertTrue(model.session(pane) === session, "A redraw must not create a fresh session/startup command")
        XCTAssertEqual(session.state, "Ended")
    }

    @MainActor func testSuccessfulRemovalEndsOnlyOwnedSession() async throws {
        let (model, tree, _) = try fixture()
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        let otherID = UUID()
        guard let tmux = PersistentTerminal.tmux else { throw XCTSkip("tmux is required") }
        func command(_ arguments: [String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = ["-L", "grove", "-f", PersistentTerminal.configuration] + arguments
            process.environment = PersistentTerminal.environment(ProcessInfo.processInfo.environment)
            process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); return process.terminationStatus
        }
        let target = "grove-" + pane.id.uuidString, sibling = "grove-" + otherID.uuidString
        XCTAssertEqual(try command(["new-session", "-d", "-s", target, "/bin/sleep 60"]), 0)
        XCTAssertEqual(try command(["new-session", "-d", "-s", sibling, "/bin/sleep 60"]), 0)
        defer { try? PersistentTerminal.end(name: target); try? PersistentTerminal.end(name: sibling) }
        await model.remove(tree)
        XCTAssertNil(model.error)
        XCTAssertNil(model.saved.tabs[tree.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.path))
        XCTAssertNotEqual(try command(["has-session", "-t", "=" + target]), 0)
        XCTAssertEqual(try command(["has-session", "-t", "=" + sibling]), 0)
    }

    @MainActor func testRemovalBlocksConcurrentPaneCreation() async throws {
        let (model, tree, base) = try fixture()
        let root = model.roots[0], tab = model.saved.tabs[tree.path]![0]
        let session = model.session(tab.panes[0])
        try "tracked".write(toFile: tree.path + "/tracked", atomically: true, encoding: .utf8)
        _ = try Git.run(["add", "tracked"], at: tree.path)
        _ = try Git.run(["-c", "user.name=Check", "-c", "user.email=check@example.test", "commit", "-m", "tracked"], at: tree.path)
        let block = base.appendingPathComponent("block"), entered = base.appendingPathComponent("entered"), release = base.appendingPathComponent("release")
        let hook = base.appendingPathComponent("fsmonitor")
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = "#!/bin/sh\nif [ -f " + quote(block.path) + " ]; then /usr/bin/touch " + quote(entered.path) + "; while [ ! -f " + quote(release.path) + " ]; do /bin/sleep .02; done; fi\nprintf 'token\\000'\n"
        try script.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        _ = try Git.run(["config", "core.fsmonitor", hook.path], at: root)
        _ = try Git.run(["config", "core.fsmonitorHookVersion", "2"], at: root)
        let subscription = session.$state.sink { state in
            if state == "Ended" { try? Data().write(to: block) }
        }
        let removal = Task { @MainActor in await model.remove(tree) }
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: entered.path), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        defer { try? Data().write(to: release) }
        guard FileManager.default.fileExists(atPath: entered.path) else {
            try Data().write(to: release); await removal.value
            return XCTFail("Git final-validation fixture never reached its barrier")
        }
        XCTAssertTrue(model.isRemoving(tree.path))
        await model.closeTab(tab, at: tree.path)
        model.addTab(); model.split(tab: tab.id, vertical: true)
        XCTAssertEqual(model.saved.tabs[tree.path]?.map(\.id), [tab.id])
        XCTAssertEqual(model.saved.tabs[tree.path]?.first?.panes.count, 1)
        let main = Worktree(path: root, branch: "main")
        model.selected = main; model.select(tree)
        XCTAssertEqual(model.selected, main)
        try Data().write(to: release)
        await removal.value
        withExtendedLifetime(subscription) {}
        XCTAssertNil(model.error)
        XCTAssertNil(model.saved.tabs[tree.path])
    }

    func testFailedCreationCleansRegistrationAndKeepsHookCommit() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-hook-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try Git.run(["init", "-b", "main"], at: repo.path)
        _ = try Git.run(["config", "user.name", "Check"], at: repo.path)
        _ = try Git.run(["config", "user.email", "check@example.test"], at: repo.path)
        _ = try Git.run(["commit", "--allow-empty", "-m", "initial"], at: repo.path)
        let unrelated = try Git.create(branch: "temporarily-missing", at: repo.path)
        try FileManager.default.removeItem(atPath: unrelated)
        let hook = repo.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\ngit -c core.hooksPath=/dev/null commit --allow-empty -m hook-created\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        XCTAssertThrowsError(try Git.create(branch: "failure", at: repo.path))
        let roster = try Git.list(at: repo.path)
        XCTAssertEqual(roster.count, 2, "Only the failed checkout registration should be removed")
        XCTAssertTrue(roster.contains { $0.branch == "temporarily-missing" })
        XCTAssertFalse(roster.contains { $0.branch == "failure" })
        XCTAssertEqual(try Git.run(["log", "-1", "--format=%s", "failure"], at: repo.path).trimmingCharacters(in: .whitespacesAndNewlines), "hook-created")
    }

    func testFailedCreationPreservesLockedCheckout() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-locked-hook-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try Git.run(["init", "-b", "main"], at: repo.path)
        _ = try Git.run(["-c", "user.name=Check", "-c", "user.email=check@example.test", "commit", "--allow-empty", "-m", "initial"], at: repo.path)
        let hook = repo.appendingPathComponent(".git/hooks/post-checkout")
        try "#!/bin/sh\ngit worktree lock \"$PWD\"\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        XCTAssertThrowsError(try Git.create(branch: "locked-failure", at: repo.path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("cleanup is incomplete"))
        }
        let failed = try XCTUnwrap(try Git.list(at: repo.path).first { $0.branch == "locked-failure" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.path), "A lock must preserve its checkout")
    }

    @MainActor func testTriageRequiresConsecutiveSamplesAndHonorsToggle() async throws {
        XCTAssertNotEqual(Bundle.main.bundleIdentifier, "local.grove.workspace")
        let oldPreference = UserDefaults.standard.object(forKey: "triageSort")
        defer {
            if let oldPreference { UserDefaults.standard.set(oldPreference, forKey: "triageSort") }
            else { UserDefaults.standard.removeObject(forKey: "triageSort") }
        }
        let (model, tree, _) = try fixture()
        let root = model.roots[0]
        let first = Worktree(path: root + "/a", branch: "aaa")
        model.trees[root] = [first, tree]
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        let session = model.session(pane)
        session.state = "Exited 1"
        model.triageSort = true
        model.recordStatusSnapshot()
        XCTAssertEqual(model.visibleTrees(root).first?.path, first.path)
        model.recordStatusSnapshot()
        XCTAssertEqual(model.visibleTrees(root).first?.path, tree.path)
        session.state = "Shell"
        model.recordStatusSnapshot()
        XCTAssertEqual(model.visibleTrees(root).first?.path, tree.path)
        model.recordStatusSnapshot()
        XCTAssertEqual(model.visibleTrees(root).first?.path, first.path)
        session.state = "Exited 1"; model.recordStatusSnapshot(); model.recordStatusSnapshot()
        model.triageSort = false
        XCTAssertEqual(model.visibleTrees(root).first?.path, first.path)
        model.saved.pinned.insert(first.path); model.triageSort = true
        XCTAssertEqual(model.visibleTrees(root).first?.path, first.path)
    }

    func testDiffPathsAndSplitContextNumbers() throws {
        let raw = """
        diff --git a/image.bin b/image.bin
        index a..b 100644
        Binary files a/image.bin and b/image.bin differ
        diff --git a/empty file b/empty file
        new file mode 100644
        index 0000000..e69de29
        diff --git "a/caf\\303\\251\\tfile" "b/caf\\303\\251\\tfile"
        index a..b 100644
        --- "a/caf\\303\\251\\tfile"
        +++ "b/caf\\303\\251\\tfile"
        @@ -1,2 +1,3 @@
         before
        +inserted
         after
        """
        let files = GitDiffParser.parse(raw)
        XCTAssertEqual(files.map(\.path), ["image.bin", "empty file", "café\tfile"])
        let context = try XCTUnwrap(files.last?.hunks.first?.lines.last)
        XCTAssertEqual(SplitCell(line: context, oldSide: false).lineNumber, 3)
        XCTAssertEqual(SplitCell(line: context, oldSide: true).lineNumber, 2)
    }
    func testRealGitDiffPathsAndMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-diff-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Git.run(["init", "-b", "main"], at: root.path)
        let names = ["binary b/data.bin", "café\tquoted\".txt", "mode file.txt", "text with spaces.txt"]
        for name in names {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.hasSuffix(".bin") ? [0, 1] : Array("before\n".utf8)).write(to: url)
        }
        _ = try Git.run(["add", "."], at: root.path)
        _ = try Git.run(["-c", "user.name=Check", "-c", "user.email=check@example.test", "commit", "-m", "files"], at: root.path)
        try Data([0, 2]).write(to: root.appendingPathComponent(names[0]))
        try "after space change\n".write(to: root.appendingPathComponent(names[3]), atomically: true, encoding: .utf8)
        try "after".write(to: root.appendingPathComponent(names[1]), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent(names[2]).path)
        try Data().write(to: root.appendingPathComponent("empty file"))
        _ = try Git.run(["add", "."], at: root.path)
        let patch = try Git.run(["-c", "core.quotePath=true", "diff", "--no-ext-diff", "--no-color", "HEAD", "--"], at: root.path)
        let files = GitDiffParser.parse(patch)
        XCTAssertEqual(Set(files.map(\.path)), Set(names + ["empty file"]))
        XCTAssertTrue(files.first { $0.path == names[0] }?.binary == true)
        XCTAssertTrue(files.flatMap(\.hunks).flatMap(\.lines).contains { $0.kind == .meta && $0.text == "\\ No newline at end of file" })
        XCTAssertTrue(files.first { $0.path == "empty file" }?.newFile == true)
        XCTAssertEqual(files.first { $0.path == "mode file.txt" }?.metadata, ["old mode 100644", "new mode 100755"])
    }

    @MainActor func testThemeHonorsAccessibility() {
        for preference in [(true, false), (false, true)] {
            let theme = AppTheme.resolved(tier: .highPerformance, animationsEnabled: true,
                scheme: .light, reduceTransparency: preference.0, reduceMotion: preference.1)
            XCTAssertNil(theme.material)
            XCTAssertFalse(theme.animationsEnabled)
        }
    }

    /// `grove://` URLs can come from any web page or app: adding an unknown
    /// folder or creating a worktree must wait for confirmation.
    @MainActor func testURLActionsWaitForConfirmation() async throws {
        let (model, tree, base) = try fixture()
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        var components = URLComponents(string: "grove://open")!
        components.queryItems = [URLQueryItem(name: "path", value: outside.path)]
        await model.handleURL(components.url!)
        XCTAssertEqual(model.pendingURLAction, .open(path: outside.standardizedFileURL.path))
        XCTAssertFalse(model.roots.contains(outside.standardizedFileURL.path))
        model.pendingURLAction = nil

        // A worktree already in the workspace is selected without a prompt.
        components.queryItems = [URLQueryItem(name: "path", value: tree.path)]
        await model.handleURL(components.url!)
        XCTAssertNil(model.pendingURLAction)

        var create = URLComponents(string: "grove://new-worktree")!
        create.queryItems = [URLQueryItem(name: "path", value: tree.path), URLQueryItem(name: "branch", value: "from-link")]
        await model.handleURL(create.url!)
        XCTAssertEqual(model.pendingURLAction, .newWorktree(branch: "from-link", worktreePath: tree.path))
        let root = model.roots[0]
        XCTAssertFalse(try Git.list(at: root).contains { $0.branch == "from-link" })

        await model.confirmURLAction(model.pendingURLAction)
        XCTAssertNil(model.pendingURLAction)
        XCTAssertTrue(try Git.list(at: root).contains { $0.branch == "from-link" })
    }

    /// Setup scripts open their own tab in a newly created worktree; other
    /// script kinds, empty commands and other repositories' scripts do not.
    @MainActor func testSetupScriptsRunInNewWorktreeOnly() async throws {
        let (model, _, _) = try fixture()
        let root = model.roots[0]
        let setup = ScriptRecord(name: "Install", command: "echo install", root: root, kind: "setup")
        let global = ScriptRecord(name: "Global setup", command: "echo global", kind: "setup")
        let empty = ScriptRecord(name: "Empty", command: "  ", kind: "setup")
        let elsewhere = ScriptRecord(name: "Elsewhere", command: "echo no", root: "/elsewhere", kind: "setup")
        let run = ScriptRecord(name: "Run", command: "echo run", root: root, kind: "run")
        model.saved.scripts = [global, setup, empty, elsewhere, run]
        XCTAssertEqual(model.setupScripts(for: root).map(\.id), [setup.id, global.id])

        await model.create("with-setup")
        let created = try XCTUnwrap(model.selected)
        XCTAssertEqual(created.branch, "with-setup")
        let tabs = model.saved.tabs[created.path] ?? []
        XCTAssertEqual(tabs.compactMap(\.scriptID), [setup.id, global.id])
        XCTAssertEqual(tabs.last?.panes.first?.command, "echo global")
        XCTAssertEqual(model.saved.activeTabs?[created.path], tabs.last?.id)
        XCTAssertNil(model.error)
    }

    /// Removing a worktree can also delete its branch, but only when Git
    /// considers it merged; a branch with unmerged commits is kept.
    @MainActor func testRemoveCanDeleteMergedBranchOnly() async throws {
        let (model, tree, _) = try fixture()
        let root = model.roots[0]
        await model.remove(tree, deleteBranch: true)
        XCTAssertNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.path))
        XCTAssertThrowsError(try Git.run(["rev-parse", "--verify", "refs/heads/task"], at: root))

        let path = try Git.create(branch: "unmerged", at: root)
        _ = try Git.run(["-c", "user.name=Check", "-c", "user.email=check@example.test", "commit", "--allow-empty", "-m", "work"], at: path)
        let unmerged = Worktree(path: path, branch: "unmerged")
        model.trees = [root: [Worktree(path: root, branch: "main"), unmerged]]
        await model.remove(unmerged, deleteBranch: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertNoThrow(try Git.run(["rev-parse", "--verify", "refs/heads/unmerged"], at: root))
        XCTAssertTrue(model.error?.contains("was kept") == true)
    }

    /// File browser markers come from porcelain status, including renames
    /// (which carry an extra original-path field) and untracked files.
    func testFileBrowserStatusMarkers() throws {
        let parsed = FileBrowser.parseStatus(" M Sources/a.swift\0?? notes.txt\0R  new.swift\0old.swift\0UU both.txt\0A  docs/new.md\0")
        XCTAssertEqual(parsed, ["Sources/a.swift": " M", "notes.txt": "??", "new.swift": "R ", "both.txt": "UU", "docs/new.md": "A "])
        XCTAssertEqual(FileBrowser.marker(code: " M").symbol, "M")
        XCTAssertEqual(FileBrowser.marker(code: "??").symbol, "U")
        XCTAssertEqual(FileBrowser.marker(code: "R ").symbol, "R")
        XCTAssertEqual(FileBrowser.marker(code: "UU").symbol, "!")
        XCTAssertEqual(FileBrowser.marker(code: "A ").symbol, "A")
        XCTAssertEqual(FileBrowser.marker(code: " D").symbol, "D")

        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("grove-status-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("dir"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo) }
        _ = try Git.run(["init", "-b", "main"], at: repo.path)
        try "x".write(to: repo.appendingPathComponent("dir/new file.txt"), atomically: true, encoding: .utf8)
        let real = FileBrowser.parseStatus(try Git.run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: repo.path))
        XCTAssertEqual(real, ["dir/new file.txt": "??"])
        let top = try Git.run(["rev-parse", "--show-toplevel"], at: repo.path).trimmingCharacters(in: .whitespacesAndNewlines)
        let index = FileBrowser.StatusIndex(top: top, paths: real)
        XCTAssertEqual(index.lookup(URL(fileURLWithPath: top + "/dir/new file.txt"), root: top).code, "??")
        XCTAssertTrue(index.lookup(URL(fileURLWithPath: top + "/dir"), root: top).folder)
        XCTAssertFalse(index.lookup(URL(fileURLWithPath: top), root: top).folder)
        // The listing may use the unresolved /var spelling of a /private/var repository.
        XCTAssertTrue(index.lookup(repo.appendingPathComponent("dir"), root: repo.path).folder)
    }

    /// Fetch-before-create can be cancelled while the remote never answers;
    /// no worktree or branch is created and the helper process is stopped.
    @MainActor func testFetchBeforeCreateCanBeCancelled() async throws {
        let (model, _, _) = try fixture()
        let root = model.roots[0]
        _ = try Git.run(["config", "protocol.ext.allow", "always"], at: root)
        // Never answers. Like git-remote-https, the helper (git remote-ext) is a
        // direct child of fetch; its own child does not hold Grove's output pipe.
        _ = try Git.run(["remote", "add", "origin", "ext::sh -c exec% sleep% 30% 2>/dev/null"], at: root)
        let started = Date()
        let creating = Task { await model.create("never-created", fetchFirst: true) }
        while model.fetchInProgress == nil && Date().timeIntervalSince(started) < 5 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.fetchInProgress, "never-created")
        try await Task.sleep(for: .milliseconds(300))
        model.cancelFetch()
        await creating.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
        XCTAssertNil(model.fetchInProgress)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.transientNotice, "Fetch cancelled. No worktree was created.")
        XCTAssertFalse(try Git.list(at: root).contains { $0.branch == "never-created" })
    }

    /// "Remove from Grove" forgets one repository's metadata and sessions but
    /// never touches files, branches or worktrees on disk.
    @MainActor func testRemoveRootForgetsMetadataButKeepsFiles() async throws {
        let (model, tree, _) = try fixture()
        let root = model.roots[0]
        let pane = model.saved.tabs[tree.path]![0].panes[0]
        _ = model.session(pane)
        model.saved.pinned = [tree.path]
        model.saved.scripts = [ScriptRecord(name: "Repo", command: "true", root: root), ScriptRecord(name: "Global", command: "true")]
        model.saved.roots.append("/tmp/grove-other-root")
        await model.removeRoot(root)
        XCTAssertEqual(model.roots, ["/tmp/grove-other-root"])
        XCTAssertNil(model.saved.tabs[tree.path])
        XCTAssertNil(model.sessions[pane.id])
        XCTAssertTrue(model.saved.pinned.isEmpty)
        XCTAssertEqual(model.saved.scripts.map(\.name), ["Global"])
        XCTAssertNil(model.trees[root])
        XCTAssertNotEqual(model.selected?.path, tree.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tree.path))
        XCTAssertTrue(try Git.list(at: root).contains { $0.path == tree.path })
    }

    /// Clone Cancel terminates the running command, including a cancel that
    /// arrives before the process has started.
    func testProcessHandleCancelsCommand() async throws {
        let running = ProcessHandle()
        let started = Date()
        let task = Task.detached { try Shell.run("sleep", ["30"], at: NSTemporaryDirectory(), handle: running) }
        try await Task.sleep(for: .milliseconds(300))
        running.cancel()
        do { _ = try await task.value; XCTFail("A cancelled command reported success") } catch {}
        XCTAssertTrue(running.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)

        let early = ProcessHandle()
        early.cancel()
        let earlyStart = Date()
        XCTAssertThrowsError(try Shell.run("sleep", ["30"], at: NSTemporaryDirectory(), handle: early))
        XCTAssertLessThan(Date().timeIntervalSince(earlyStart), 10)
    }

    /// Inline validation and friendly error text share their rules with the
    /// operations they guard.
    func testInputValidationAndErrorExplanations() {
        XCTAssertNil(Git.branchNameProblem(""))
        XCTAssertNil(Git.branchNameProblem("feature/new-idea_2"))
        XCTAssertNotNil(Git.branchNameProblem("-oops"))
        XCTAssertNotNil(Git.branchNameProblem("has space"))
        XCTAssertNotNil(Git.branchNameProblem("feature//double"))
        XCTAssertNotNil(Git.branchNameProblem("trailing/"))
        XCTAssertNotNil(Git.branchNameProblem(String(repeating: "a", count: 101)))
        XCTAssertNil(Workspace.cloneURLProblem(""))
        XCTAssertNil(Workspace.cloneURLProblem("https://example.com/repo.git"))
        XCTAssertNil(Workspace.cloneURLProblem("git@example.com:team/repo.git"))
        XCTAssertNotNil(Workspace.cloneURLProblem("file:///tmp/repo"))
        XCTAssertNotNil(Workspace.cloneURLProblem("https://example.com/my repo.git"))

        let offline = ErrorExplainer.explain("fatal: unable to access 'https://example.com/': Could not resolve host: example.com")
        XCTAssertTrue(offline.hasPrefix("Grove couldn't reach the server."))
        XCTAssertTrue(offline.contains("Could not resolve host: example.com"))
        XCTAssertTrue(ErrorExplainer.explain("ls: Operation not permitted").contains("Privacy & Security"))
        XCTAssertTrue(ErrorExplainer.explain("To get started with GitHub CLI, please run:  gh auth login").contains("gh auth login"))
        XCTAssertEqual(ErrorExplainer.explain("This worktree is locked."), "This worktree is locked.")
    }

    /// Files checked out with Git have no quarantine, so the file browser must
    /// ask before opening anything that can run code.
    func testFileBrowserFlagsCodeButNotDocuments() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("grove-files-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        func file(_ name: String, executable: Bool = false) throws -> URL {
            let url = base.appendingPathComponent(name)
            try "content".write(to: url, atomically: true, encoding: .utf8)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
            return url
        }
        XCTAssertTrue(FileBrowser.mayRunCode(try file("run.command")))
        XCTAssertTrue(FileBrowser.mayRunCode(try file("Setup.PKG")))
        XCTAssertTrue(FileBrowser.mayRunCode(try file("build", executable: true)))
        XCTAssertFalse(FileBrowser.mayRunCode(try file("README.md")))
        XCTAssertFalse(FileBrowser.mayRunCode(try file("main.swift")))
        XCTAssertFalse(FileBrowser.mayRunCode(base))
    }

}
