import SwiftUI
import AppKit

@MainActor final class Workspace: ObservableObject {
    @Published var saved = SavedWorkspace()
    @Published var trees: [String: [Worktree]] = [:]
    @Published var selected: Worktree?
    @Published var error: String?
    @Published var busy = false
    @Published var status = ""
    @Published var diff = ""
    @Published var pullRequest = ""
    @Published var showArchived = false
    @Published var palette = false
    var sessions: [UUID: Session] = [:]
    @AppStorage("baseRef") var baseRef = "HEAD"
    @AppStorage("fetchBeforeCreate") var fetchBeforeCreate = false
    @AppStorage("fontSize") var fontSize = 13.0
    @AppStorage("persistentTerminals") var persistent = true
    @AppStorage("appearance") var appearance = "dark"
    @AppStorage("githubEnabled") var githubEnabled = false
    @Published private(set) var workspaceStorageBlocked = false
    private var refreshing = false
    private var closingPaneTabs = Set<UUID>()
    private let verificationPath = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"]
    init() {
        if let path = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"] {
            let stateURL = URL(fileURLWithPath: path + "/grove-test-state.json")
            if let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(SavedWorkspace.self, from: data) { saved = state }
            else {
                saved.roots = [path]
                let marker = path + "/grove-terminal-marker"
                let command = "printf 'interactive-terminal-ready' > " + Shell.quote(marker) + "; printf '%s' $PPID > " + Shell.quote(path + "/shell-pid") + "; printf '%s' \"${STY-}\" > " + Shell.quote(path + "/screen-env") + "; printf '%s' \"${TMUX-}\" > " + Shell.quote(path + "/tmux-env")
                saved.tabs[path] = [TabRecord(name: "Verification", panes: [PaneRecord(command: command)])]
            }
            return
        }
        do {
            if let loaded = try WorkspacePersistence.load() {
                saved = loaded.state
                if loaded.recoveredBackup { error = "Your previous workspace backup was restored. Unreadable metadata was preserved locally for recovery." }
            } else { saved.roots = UserDefaults.standard.stringArray(forKey: "repositories") ?? [] }
        } catch {
            workspaceStorageBlocked = true
            self.error = "Workspace recovery is needed: \(error.localizedDescription) Your saved metadata has not been overwritten. Use Settings to reset workspace metadata only if you want to start fresh."
        }
    }
    var roots: [String] { saved.roots }
    var usePersistentTerminals: Bool { verificationPath != nil || persistent }
    func save() {
        if let path = verificationPath {
            do { try JSONEncoder().encode(saved).write(to: URL(fileURLWithPath: path + "/grove-test-state.json"), options: .atomic) }
            catch { self.error = error.localizedDescription }
            return
        }
        guard !workspaceStorageBlocked else { return }
        do { try WorkspacePersistence.save(saved) }
        catch { self.error = error.localizedDescription }
    }
    func isFolder(_ root: String) -> Bool { !(FileManager.default.fileExists(atPath: root + "/.git")) }
    func root(for tree: Worktree) -> String? { roots.first { trees[$0]?.contains(where: { $0.path == tree.path }) == true } }
    func open() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Add folder or repository"
        if panel.runModal() == .OK, let url = panel.url { Task { await add(url.path) } }
    }
    func add(_ path: String) async {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { error = "Choose an existing directory: \(path)"; return }
        let root = (try? await Task.detached { try Git.run(["rev-parse", "--show-toplevel"], at: path).trimmingCharacters(in: .whitespacesAndNewlines) }.value) ?? URL(fileURLWithPath: path).standardizedFileURL.path
        if !saved.roots.contains(root) { saved.roots.append(root); save() }
        await reload()
        if let first = trees[root]?.first { select(first) }
    }
    func select(_ tree: Worktree) {
        selected = tree; saved.selected = tree.path; status = ""; diff = ""; pullRequest = ""
        if saved.tabs[tree.path]?.isEmpty != false { saved.tabs[tree.path] = [TabRecord()] }
        save(); Task { await refreshChanges() }
    }
    func session(_ record: PaneRecord) -> Session {
        if let found = sessions[record.id] { return found }
        let session = Session(record); sessions[record.id] = session; return session
    }
    func addTab(command: String? = nil, name: String = "Terminal", scriptID: UUID? = nil) {
        guard let path = selected?.path else { return }
        guard (saved.tabs[path]?.count ?? 0) < 64 else { error = "This workspace has reached its 64-tab limit."; return }
        var tab = TabRecord(name: name, panes: [PaneRecord(title: name, command: command)])
        tab.scriptID = scriptID
        tab.panes[0].environment = scriptEnvironment(scriptID: scriptID, tabID: tab.id)
        saved.tabs[path, default: []].append(tab)
        saved.activeTabs = saved.activeTabs ?? [:]; saved.activeTabs?[path] = tab.id; save()
    }
    func split(tab: UUID, vertical: Bool) {
        guard let path = selected?.path, let index = saved.tabs[path]?.firstIndex(where: { $0.id == tab }) else { return }
        let tab = saved.tabs[path]![index]
        guard tab.panes.count < 64 else { error = "This tab has reached its 64-pane limit."; return }
        guard let lastPane = tab.panes.last else { error = "This tab has no terminal panes."; return }
        let focused = tab.panes.first { guard let view = sessions[$0.id]?.view else { return false }; return view.window?.firstResponder === view }?.id ?? lastPane.id
        let newPane = PaneRecord()
        let currentLayout = tab.layout ?? tab.panes.dropFirst().reduce(SplitNode.pane(tab.panes[0].id)) { .split(vertical: tab.vertical, first: $0, second: .pane($1.id)) }
        var candidate = saved
        candidate.tabs[path]![index].layout = currentLayout.inserting(newPane.id, after: focused, vertical: vertical)
        candidate.tabs[path]![index].panes.append(newPane)
        do { try candidate.validate(); saved = candidate; save() }
        catch { self.error = error.localizedDescription }
    }
    func closePane(_ paneID: UUID, in tabID: UUID, at path: String) async {
        guard !closingPaneTabs.contains(tabID),
              let tab = saved.tabs[path]?.first(where: { $0.id == tabID }),
              tab.removingPane(paneID) != nil else { return }
        closingPaneTabs.insert(tabID); defer { closingPaneTabs.remove(tabID) }
        do { try await endSession(paneID) }
        catch { self.error = "Could not close this split: \(error.localizedDescription)"; return }
        // Re-read after cleanup: another action may have changed this tab while awaiting.
        guard let index = saved.tabs[path]?.firstIndex(where: { $0.id == tabID }),
              let remaining = saved.tabs[path]![index].removingPane(paneID) else { return }
        saved.tabs[path]![index] = remaining
        sessions.removeValue(forKey: paneID)
        save()
    }
    func closeTab(_ tab: TabRecord) async {
        guard let path = selected?.path else { return }
        do {
            for pane in tab.panes { try await endSession(pane.id) }
        } catch { self.error = "Could not end this tab's sessions: \(error.localizedDescription)"; return }
        for pane in tab.panes { sessions.removeValue(forKey: pane.id) }
        saved.tabs[path]?.removeAll { $0.id == tab.id }
        if saved.tabs[path]?.isEmpty != false { saved.tabs[path] = [TabRecord()] }
        saved.activeTabs?[path] = saved.tabs[path]?.last?.id
        save()
    }
    func pin(_ tree: Worktree) { if !saved.pinned.insert(tree.path).inserted { saved.pinned.remove(tree.path) }; save() }
    func archive(_ tree: Worktree) { if !saved.archived.insert(tree.path).inserted { saved.archived.remove(tree.path) }; save() }
    func visibleTrees(_ root: String) -> [Worktree] {
        (trees[root] ?? []).filter { showArchived || !saved.archived.contains($0.path) }.sorted {
            if saved.pinned.contains($0.path) != saved.pinned.contains($1.path) { return saved.pinned.contains($0.path) }
            return $0.branch.localizedStandardCompare($1.branch) == .orderedAscending
        }
    }
    func reload() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        for root in roots {
            do { trees[root] = try await Task.detached { try Git.list(at: root) }.value }
            catch {
                if isFolder(root) && FileManager.default.fileExists(atPath: root) { trees[root] = [Worktree(path: root, branch: URL(fileURLWithPath: root).lastPathComponent)] }
                else { self.error = error.localizedDescription }
            }
        }
        if selected == nil || !trees.values.flatMap({ $0 }).contains(where: { $0.path == selected?.path }) {
            let all = roots.flatMap { trees[$0] ?? [] }
            if let first = all.first(where: { $0.path == saved.selected }) ?? all.first { select(first) }
            else { selected = nil }
        } else if let current = selected, let refreshed = trees.values.flatMap({ $0 }).first(where: { $0.path == current.path }), refreshed != current {
            selected = refreshed
        }
    }
    func refreshChanges() async {
        guard let tree = selected, let root = root(for: tree), !isFolder(root) else { return }
        do {
            let result = try await Task.detached {
                let status = try Git.run(["status", "--short"], at: tree.path)
                let diff = (try? Git.run(["diff", "--no-ext-diff", "--no-color", "HEAD", "--"], at: tree.path)) ?? "No commits yet."
                return (status, diff)
            }.value
            guard selected == tree else { return }; status = result.0; diff = result.1
        } catch { self.error = error.localizedDescription }
    }
    func refreshPR() async {
        guard githubEnabled, let path = selected?.path else { return }
        do {
            let output = try await Task.detached { try Shell.run("gh", ["pr", "view", "--json", "number,title,state,url,mergeable,statusCheckRollup"], at: path) }.value
            guard selected?.path == path else { return }; pullRequest = output
        } catch { pullRequest = error.localizedDescription }
    }
    func create(_ branch: String) async {
        guard let tree = selected, let root = root(for: tree), !isFolder(root) else { error = "Select a Git repository first."; return }
        busy = true; defer { busy = false }
        do {
            let ref = baseRef, fetch = fetchBeforeCreate
            let path = try await Task.detached {
                if fetch { _ = try Git.run(["fetch", "--prune"], at: root) }
                return try Git.create(branch: branch, at: root, baseRef: ref)
            }.value
            await reload()
            if let tree = trees[root]?.first(where: { $0.path == path }) { select(tree) }
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ tree: Worktree) async {
        guard let root = root(for: tree) else { return }
        do {
            _ = try await Task.detached { try Git.remove(tree, at: root) }.value
            for tab in saved.tabs[tree.path] ?? [] { for pane in tab.panes { sessions[pane.id]?.detach(); sessions.removeValue(forKey: pane.id) } }
            saved.tabs.removeValue(forKey: tree.path); saved.activeTabs?.removeValue(forKey: tree.path); saved.pinned.remove(tree.path); saved.archived.remove(tree.path); save()
            await reload()
        } catch { self.error = error.localizedDescription }
    }
    func rename(_ tree: Worktree, branch: String) async {
        do { try await Task.detached { try Git.rename(branch, at: tree.path) }.value; await reload(); if let changed = trees.values.flatMap({ $0 }).first(where: { $0.path == tree.path }) { select(changed) } }
        catch { self.error = error.localizedDescription }
    }
    func clone(_ url: String, to parent: URL) async {
        guard url.hasPrefix("https://") || url.hasPrefix("git@") || url.hasPrefix("ssh://") else { error = "Use an HTTPS or SSH Git URL."; return }
        busy = true; defer { busy = false }
        let destination = parent.appendingPathComponent("grove-clone-" + UUID().uuidString.prefix(8))
        do {
            _ = try await Task.detached { try Shell.run("git", ["clone", "--", url, destination.path], at: parent.path) }.value
            await add(destination.path)
        } catch { self.error = error.localizedDescription }
    }
    func handle(_ url: URL) {
        guard url.scheme == "grove", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let values = Dictionary((parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        Task {
            await reload()
            while refreshing {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
            if url.host != "open", let path = values["path"] {
                guard let tree = trees.values.flatMap({ $0 }).first(where: { $0.path == path }) else { error = "That worktree is not in this workspace."; return }
                select(tree)
            }
            switch url.host {
            case "open": if let path = values["path"] { await add(path) }
            case "new-tab": addTab()
            case "split": if let path = selected?.path {
                let tabs = saved.tabs[path] ?? []
                if let tab = tabs.first(where: { $0.id == saved.activeTabs?[path] }) ?? tabs.last { split(tab: tab.id, vertical: values["direction"] == "vertical") }
            }
            case "new-worktree": if let branch = values["branch"] { await create(branch) }
            case "select": break
            default: error = "Unknown Grove URL action."
            }
        }
    }
    func resetWorkspaceMetadata() {
        for session in sessions.values { session.detach() }
        sessions.removeAll(); saved = SavedWorkspace(); selected = nil; trees = [:]
        WorkspacePersistence.reset(); workspaceStorageBlocked = false; save()
    }
    func endSession(_ id: UUID) async throws {
        let name = "grove-" + id.uuidString
        try await Task.detached { try PersistentTerminal.end(name: name) }.value
        if sessions[id] == nil, let record = saved.tabs.values.flatMap({ $0 }).flatMap({ $0.panes }).first(where: { $0.id == id }) {
            sessions[id] = Session(record)
        }
        sessions[id]?.end()
    }
    func endSessionsAndQuit() {
        let ids = saved.tabs.values.flatMap { $0 }.flatMap { $0.panes }.map(\.id)
        Task {
            do { for id in ids { try await endSession(id) }; NSApp.terminate(nil) }
            catch { self.error = "Some terminal sessions could not be ended: \(error.localizedDescription)" }
        }
    }
    func renameTab(_ id: UUID, name: String) {
        guard let path = selected?.path, let index = saved.tabs[path]?.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        saved.tabs[path]![index].name = name; save()
    }
    func moveTab(_ id: UUID, offset: Int) {
        guard let path = selected?.path, let index = saved.tabs[path]?.firstIndex(where: { $0.id == id }), saved.tabs[path]!.indices.contains(index + offset) else { return }
        saved.tabs[path]!.swapAt(index, index + offset); save()
    }
    func terminal() { addTab() }
}

enum Shell {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func run(_ executable: String, _ args: [String], at path: String, allowFailure: Bool = false) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env; process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard allowFailure || process.terminationStatus == 0 else { throw CommandError(message: output) }; return output
    }
}
