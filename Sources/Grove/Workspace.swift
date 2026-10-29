import SwiftUI
import AppKit
import UserNotifications

struct ScriptRecord: Codable, Identifiable {
    var id = UUID()
    var name: String
    var command: String
    var root: String? = nil
}
struct SavedWorkspace: Codable {
    var roots: [String] = []
    var tabs: [String: [TabRecord]] = [:]
    var pinned: Set<String> = []
    var archived: Set<String> = []
    var selected: String? = nil
    var scripts: [ScriptRecord] = []
}

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
    @Published var sessions: [UUID: Session] = [:]
    @AppStorage("baseRef") var baseRef = "HEAD"
    @AppStorage("fetchBeforeCreate") var fetchBeforeCreate = false
    @AppStorage("fontSize") var fontSize = 13.0
    @AppStorage("persistentTerminals") var persistent = true
    @AppStorage("appearance") var appearance = "dark"
    @AppStorage("githubEnabled") var githubEnabled = false
    private var refreshing = false
    private let verificationPath = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"]
    init() {
        if let path = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"] {
            let stateURL = URL(fileURLWithPath: path + "/grove-test-state.json")
            if let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(SavedWorkspace.self, from: data) { saved = state }
            else {
                saved.roots = [path]
                let marker = path + "/grove-terminal-marker"
                let command = "printf 'interactive-terminal-ready' > " + Shell.quote(marker) + "; printf '%s' $$ > " + Shell.quote(path + "/shell-pid")
                saved.tabs[path] = [TabRecord(name: "Verification", panes: [PaneRecord(command: command)])]
            }
            return
        }
        if let data = UserDefaults.standard.data(forKey: "workspace.v2"), let state = try? JSONDecoder().decode(SavedWorkspace.self, from: data) { saved = state }
        else { saved.roots = UserDefaults.standard.stringArray(forKey: "repositories") ?? [] }
    }
    var roots: [String] { saved.roots }
    func save() {
        if let path = verificationPath {
            do { try JSONEncoder().encode(saved).write(to: URL(fileURLWithPath: path + "/grove-test-state.json"), options: .atomic) }
            catch { self.error = error.localizedDescription }
            return
        }
        do { UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: "workspace.v2") }
        catch { self.error = error.localizedDescription }
    }
    func isFolder(_ root: String) -> Bool { !(FileManager.default.fileExists(atPath: root + "/.git")) }
    func root(for tree: Worktree) -> String? { roots.first { trees[$0]?.contains(tree) == true } }
    func open() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Add folder or repository"
        if panel.runModal() == .OK, let url = panel.url { Task { await add(url.path) } }
    }
    func add(_ path: String) async {
        guard FileManager.default.fileExists(atPath: path) else { error = "Directory does not exist: \(path)"; return }
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
    func addTab(command: String? = nil, name: String = "Terminal") {
        guard let path = selected?.path else { return }
        saved.tabs[path, default: []].append(TabRecord(name: name, panes: [PaneRecord(title: name, command: command)])); save()
    }
    func split(tab: UUID, vertical: Bool) {
        guard let path = selected?.path, let index = saved.tabs[path]?.firstIndex(where: { $0.id == tab }) else { return }
        let tab = saved.tabs[path]![index]
        let focused = tab.panes.first { guard let view = sessions[$0.id]?.view else { return false }; return view.window?.firstResponder === view }?.id ?? tab.panes.last!.id
        let newPane = PaneRecord()
        let currentLayout = tab.layout ?? tab.panes.dropFirst().reduce(SplitNode.pane(tab.panes[0].id)) { .split(vertical: tab.vertical, first: $0, second: .pane($1.id)) }
        saved.tabs[path]![index].layout = currentLayout.inserting(newPane.id, after: focused, vertical: vertical)
        saved.tabs[path]![index].panes.append(newPane); save()
    }
    func closeTab(_ tab: TabRecord) {
        guard let path = selected?.path else { return }
        for pane in tab.panes { sessions[pane.id]?.detach(); sessions.removeValue(forKey: pane.id) }
        saved.tabs[path]?.removeAll { $0.id == tab.id }
        if saved.tabs[path]?.isEmpty != false { saved.tabs[path] = [TabRecord()] }
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
                if isFolder(root) { trees[root] = [Worktree(path: root, branch: URL(fileURLWithPath: root).lastPathComponent)] }
                else { self.error = error.localizedDescription }
            }
        }
        if selected == nil || !trees.values.flatMap({ $0 }).contains(where: { $0.path == selected?.path }) {
            let all = roots.flatMap { trees[$0] ?? [] }
            if let first = all.first(where: { $0.path == saved.selected }) ?? all.first { select(first) }
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
            saved.tabs.removeValue(forKey: tree.path); saved.pinned.remove(tree.path); saved.archived.remove(tree.path); save()
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
        if url.host != "open", let path = values["path"], let tree = trees.values.flatMap({ $0 }).first(where: { $0.path == path }) { select(tree) }
        switch url.host {
        case "open": if let path = values["path"] { Task { await add(path) } }
        case "new-tab": addTab()
        case "split": if let path = selected?.path, let tab = saved.tabs[path]?.last { split(tab: tab.id, vertical: values["direction"] == "vertical") }
        case "new-worktree": if let branch = values["branch"] { Task { await create(branch) } }
        case "select": if let path = values["path"], let tree = trees.values.flatMap({ $0 }).first(where: { $0.path == path }) { select(tree) }
        default: error = "Unknown Grove URL action."
        }
    }
    func endSessionsAndQuit() {
        let names = saved.tabs.values.flatMap { $0 }.flatMap { $0.panes }.map { "grove-" + $0.id.uuidString }
        Task {
            for name in names { _ = try? await Task.detached { try Shell.run("/usr/bin/screen", ["-S", name, "-X", "quit"], at: "/") }.value }
            NSApp.terminate(nil)
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
    static func run(_ executable: String, _ args: [String], at path: String) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GH_PROMPT_DISABLED"] = "1"
        process.environment = env; process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw CommandError(message: output) }; return output
    }
}
