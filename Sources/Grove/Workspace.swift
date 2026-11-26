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
    @Published var backgroundError: String?
    @Published var transientNotice: String?
    @Published var showCreateSheet = false
    @Published var diffStats: [String: DiffSummary] = [:]
    /// Transient (never persisted): pane that held terminal focus most recently,
    /// used for deterministic focus restoration after sheets/alerts dismiss.
    @Published private(set) var lastFocusedPaneID: UUID?
    @Published private(set) var focusedPaneID: UUID?
    struct CloseRequest: Equatable { var path: String; var tab: UUID; var pane: UUID? }
    @Published var pendingClose: CloseRequest?
    @Published var pendingRemove: Worktree?
    @Published var pendingRename: Worktree?
    func requestRemove(_ tree: Worktree) { snapshotFocus(); pendingRemove = tree }
    func isRemoving(_ path: String) -> Bool { removingWorktrees.contains(path) }
    func requestRename(_ tree: Worktree) { snapshotFocus(); pendingRename = tree }
    func requestRenameSelected() { guard let tree = selected else { return }; snapshotFocus(); pendingRename = tree }
    var sessions: [UUID: Session] = [:]
    @AppStorage("baseRef") var baseRef = "HEAD"
    @AppStorage("fetchBeforeCreate") var fetchBeforeCreate = false
    @AppStorage("fontSize") var fontSize = 13.0
    @AppStorage("fontName") var fontName = ""
    @AppStorage("persistentTerminals") var persistent = true
    @AppStorage("appearance") var appearance = "dark"
    @AppStorage("githubEnabled") var githubEnabled = false
    @AppStorage("triageSort") var triageSort = true
    @AppStorage("compactSidebar") var compactSidebar = false
    private var reattachedIDs = Set<UUID>()
    private var restoredPaneIDs = Set<UUID>()
    private let launchedAt = Date()
    private var reattachDebounce: Task<Void, Never>?
    @Published private(set) var workspaceStorageBlocked = false
    private var refreshing = false
    /// Window content views currently showing the Changes (diff) pane,
    /// keyed by view-instance id. Multiple windows share this Workspace:
    /// one window closing its pane must not silence diff updates in another.
    private var visibleChangesViews = Set<UUID>()
    var changesViewVisible: Bool { !visibleChangesViews.isEmpty }
    func setChangesViewVisible(_ visible: Bool, id: UUID) {
        if visible { visibleChangesViews.insert(id) } else { visibleChangesViews.remove(id) }
    }
    private var closingPaneTabs = Set<UUID>()
    private var removingWorktrees = Set<String>()
    private let verificationPath: String?
    init(verificationPath: String? = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"]) {
        self.verificationPath = verificationPath
        if let path = verificationPath {
            let stateURL = URL(fileURLWithPath: path + "/grove-test-state.json")
            if let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(SavedWorkspace.self, from: data) {
                saved = state; restoredPaneIDs = Set(state.tabs.values.flatMap { $0 }.flatMap { $0.panes }.map(\.id))
            }
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
                restoredPaneIDs = Set(saved.tabs.values.flatMap { $0 }.flatMap { $0.panes }.map(\.id))
                if loaded.recoveredBackup { error = "Your previous workspace backup was restored. Unreadable metadata was preserved locally for recovery." }
            } else { saved.roots = UserDefaults.standard.stringArray(forKey: "repositories") ?? [] }
        } catch {
            workspaceStorageBlocked = true
            self.error = "Workspace recovery is needed: \(error.localizedDescription) Your saved metadata has not been overwritten. Use Settings to reset workspace metadata only if you want to start fresh."
        }
        // Event-driven terminal-focus tracking: window update notifications fire
        // on user interaction, and the handler is an O(panes) pointer compare
        // that publishes only when the focused pane actually changes.
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.refreshFocusedPane() } }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.refreshFocusedPane() } }
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
        guard !isRemoving(tree.path) else { return }
        selected = tree; saved.selected = tree.path; status = ""; diff = ""; pullRequest = ""
        if saved.tabs[tree.path]?.isEmpty != false { saved.tabs[tree.path] = [TabRecord()] }
        save(); Task { await refreshChanges() }
    }
    func session(_ record: PaneRecord) -> Session {
        if let found = sessions[record.id] { return found }
        let session = Session(record)
        sessions[record.id] = session; return session
    }

    /// Re-derive which pane holds terminal first responder; publish only on change.
    func refreshFocusedPane() {
        var newFocused: UUID?
        for (id, session) in sessions {
            if let view = session.view, let window = view.window, window.firstResponder === view { newFocused = id; break }
        }
        guard newFocused != focusedPaneID else { return }
        focusedPaneID = newFocused
        if let newFocused {
            lastFocusedPaneID = newFocused
            if let session = sessions[newFocused] { noteReattachIfNeeded(session) }
        }
    }

    // MARK: Focus discipline

    /// Record which terminal pane currently holds first responder, if any.
    /// Called before presenting sheets/dialogs so focus can be restored on dismissal.
    func snapshotFocus() {
        for (id, session) in sessions {
            if let view = session.view, let window = view.window, window.firstResponder === view {
                lastFocusedPaneID = id
                return
            }
        }
    }

    // MARK: Keyboard actions

    func activeTab(at path: String) -> TabRecord? {
        let tabs = saved.tabs[path] ?? []
        return tabs.first(where: { $0.id == saved.activeTabs?[path] }) ?? tabs.last
    }

    func closeFocused() {
        guard let path = selected?.path else { return }
        guard let active = activeTab(at: path) else { return }
        let focused = active.panes.first { pane in
            guard let view = sessions[pane.id]?.view, let window = view.window else { return false }
            return window.firstResponder === view
        }?.id ?? active.panes.last?.id
        snapshotFocus()
        pendingClose = CloseRequest(path: path, tab: active.id, pane: active.panes.count > 1 ? focused : nil)
    }

    func cycleTab(offset: Int) {
        guard let path = selected?.path, let tabs = saved.tabs[path], tabs.count > 1 else { return }
        let currentID = saved.activeTabs?[path] ?? tabs.last?.id
        let currentIndex = tabs.firstIndex(where: { $0.id == currentID }) ?? 0
        let next = (currentIndex + offset + tabs.count) % tabs.count
        saved.activeTabs = saved.activeTabs ?? [:]; saved.activeTabs?[path] = tabs[next].id; save()
    }

    func copyWorktreePath() {
        guard let path = selected?.path else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string)
        showNotice("Copied worktree path")
    }

    func copyBranchName() {
        guard let branch = selected?.branch else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(branch, forType: .string)
        showNotice("Copied branch name “\(branch)”")
    }

    private var noticeTask: Task<Void, Never>?
    /// Short confirmation in the notice banner, cleared after a few seconds.
    func showNotice(_ text: String) {
        noticeTask?.cancel()
        transientNotice = text
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.transientNotice == text else { return }
            self.transientNotice = nil
        }
    }

    func jumpToNextAttention() {
        let ordered = roots.flatMap { visibleTrees($0) }
        let attention = ordered.filter { tree in
            saved.tabs[tree.path]?.flatMap(\.panes).contains {
                WorktreeStatus.parse(sessions[$0.id]?.state ?? "") == .failed
            } == true
        }
        guard !attention.isEmpty else { return }
        let currentIndex = selected.flatMap { current in attention.firstIndex(where: { $0.path == current.path }) }
        let next = attention[(currentIndex.map { $0 + 1 } ?? 0) % attention.count]
        select(next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            _ = self?.focusTerminalPane()
        }
    }

    /// Transient saved-pane notice; daemon continuity is verified separately.
    private func noteReattachIfNeeded(_ session: Session) {
        guard session.state == "Shell", recordIsRestored(session.record),
              Date().timeIntervalSince(launchedAt) < 30,
              !reattachedIDs.contains(session.id) else { return }
        reattachedIDs.insert(session.id)
        reattachDebounce?.cancel()
        reattachDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            self.transientNotice = "Restored \(self.reattachedIDs.count) saved terminal pane\(self.reattachedIDs.count == 1 ? "" : "s")"
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.transientNotice = nil
        }
    }

    /// This notice reports restored metadata, not daemon continuity; a saved
    /// pane can start a new shell if its daemon no longer exists.
    private func recordIsRestored(_ record: PaneRecord) -> Bool { restoredPaneIDs.contains(record.id) }

    // MARK: Triage status

    /// Rollup status for a worktree: most attention-worthy pane state wins.
    func status(for path: String) -> WorktreeStatus {
        let panes = saved.tabs[path]?.flatMap(\.panes) ?? []
        guard !panes.isEmpty else { return .idle }
        let statuses = panes.map { WorktreeStatus.parse(sessions[$0.id]?.state ?? "Starting") }
        return statuses.min { $0.sortRank < $1.sortRank } ?? .idle
    }

    /// Commit only status samples observed twice in succession. Published:
    /// sidebar triage icons/sorting read stableStatus, so a change must
    /// invalidate views even when diffStats and trees are unchanged.
    @Published private(set) var lastStatuses: [String: WorktreeStatus] = [:]
    private var previousStatusSamples: [String: WorktreeStatus] = [:]
    func stableStatus(for path: String) -> WorktreeStatus { lastStatuses[path] ?? .idle }

    func recordStatusSnapshot() {
        let sample = Dictionary(uniqueKeysWithValues: saved.tabs.keys.map { ($0, status(for: $0)) })
        var committed = lastStatuses.filter { sample[$0.key] != nil }
        for (path, state) in sample where previousStatusSamples[path] == state { committed[path] = state }
        previousStatusSamples = sample
        // Publish exactly once, and only when the stable statuses changed.
        if lastStatuses != committed { lastStatuses = committed }
    }

    /// Tier-gated batch diff summary poll for visible worktrees.
    func pollDiffStats() async {
        guard !refreshing, !roots.isEmpty else { return }
        refreshing = true; defer { refreshing = false }
        let efficient = PerformanceProfileManager.shared.effectiveTier == .efficient
        let paths = roots.flatMap { visibleTrees($0) }.map(\.path)
        let stats = await Task.detached { () -> [String: DiffSummary] in
            var result: [String: DiffSummary] = [:]
            // Sequential: bounded process spawns, no fan-out.
            for path in paths {
                if Task.isCancelled { break }
                guard let status = try? Git.run(["status", "--porcelain", "-z"], at: path), !status.isEmpty else { continue }
                var additions = 0, deletions = 0, hasLineCounts = false
                if !efficient, let numstat = try? Git.run(["diff", "--numstat", "--no-color", "HEAD", "--"], at: path) {
                    hasLineCounts = true
                    for line in numstat.split(separator: "\n") {
                        let parts = line.split(separator: "\t")
                        if parts.count >= 2, let a = Int(parts[0]), let d = Int(parts[1]) { additions += a; deletions += d }
                    }
                }
                result[path] = DiffSummary(dirty: true, additions: additions, deletions: deletions, hasLineCounts: hasLineCounts)
            }
            return result
        }.value
        if diffStats != stats { diffStats = stats }
        recordStatusSnapshot()
    }

    /// Restore terminal focus to the last focused pane; fall back to the first
    /// pane of the selected worktree's active tab. Guards cover panes that were
    /// removed or closed while a sheet was presented.
    func restoreFocus() {
        DispatchQueue.main.async {
            guard let id = self.lastFocusedPaneID,
                  let session = self.sessions[id],
                  let view = session.view, view.window != nil else {
                self.focusFallbackPane()
                return
            }
            view.window?.makeFirstResponder(view)
        }
    }

    private func focusFallbackPane() {
        guard let path = selected?.path else { return }
        guard let active = activeTab(at: path), let pane = active.panes.first,
              let session = sessions[pane.id], let view = session.view, view.window != nil else { return }
        view.window?.makeFirstResponder(view)
    }

    /// Focus a terminal pane if none currently holds first responder.
    /// Returns the view focused (or already focused), nil if no terminal exists.
    func focusTerminalPane() -> NSView? {
        for session in sessions.values {
            if let view = session.view, let window = view.window, window.firstResponder === view { return view }
        }
        if let id = lastFocusedPaneID, let session = sessions[id], let view = session.view, view.window != nil {
            view.window?.makeFirstResponder(view)
            return view
        }
        guard let path = selected?.path, let active = activeTab(at: path), let pane = active.panes.first,
              let session = sessions[pane.id], let view = session.view, view.window != nil else { return nil }
        view.window?.makeFirstResponder(view)
        return view
    }
    func addTab(command: String? = nil, name: String = "Terminal", scriptID: UUID? = nil) {
        guard let path = selected?.path, !removingWorktrees.contains(path) else { return }
        guard (saved.tabs[path]?.count ?? 0) < 64 else { error = "This workspace has reached its 64-tab limit."; return }
        var tab = TabRecord(name: name, panes: [PaneRecord(title: name, command: command)])
        tab.scriptID = scriptID
        tab.panes[0].environment = scriptEnvironment(scriptID: scriptID, tabID: tab.id)
        saved.tabs[path, default: []].append(tab)
        saved.activeTabs = saved.activeTabs ?? [:]; saved.activeTabs?[path] = tab.id; save()
    }
    func split(tab: UUID, vertical: Bool) {
        guard let path = selected?.path, !removingWorktrees.contains(path), let index = saved.tabs[path]?.firstIndex(where: { $0.id == tab }) else { return }
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
        guard !isRemoving(path), !closingPaneTabs.contains(tabID),
              let tab = saved.tabs[path]?.first(where: { $0.id == tabID }),
              tab.removingPane(paneID) != nil else { return }
        closingPaneTabs.insert(tabID); defer { closingPaneTabs.remove(tabID) }
        do { try await endSession(paneID) }
        catch { self.error = "Could not close this split: \(error.localizedDescription)"; return }
        // Re-read after cleanup: another action may have changed this tab while awaiting.
        guard !isRemoving(path), let index = saved.tabs[path]?.firstIndex(where: { $0.id == tabID }),
              let remaining = saved.tabs[path]![index].removingPane(paneID) else { return }
        saved.tabs[path]![index] = remaining
        sessions.removeValue(forKey: paneID)
        save()
    }
    func closeTab(_ tab: TabRecord, at origin: String? = nil) async {
        guard let path = origin ?? selected?.path, !isRemoving(path), !closingPaneTabs.contains(tab.id),
              saved.tabs[path]?.contains(where: { $0.id == tab.id }) == true else { return }
        closingPaneTabs.insert(tab.id); defer { closingPaneTabs.remove(tab.id) }
        do {
            for pane in tab.panes { try await endSession(pane.id) }
        } catch { self.error = "Could not end this tab's sessions: \(error.localizedDescription)"; return }
        guard !isRemoving(path) else { return }
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
            if triageSort {
                let left = stableStatus(for: $0.path).sortRank, right = stableStatus(for: $1.path).sortRank
                if left != right { return left < right }
            }
            return $0.branch.localizedStandardCompare($1.branch) == .orderedAscending
        }
    }
    func reload() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        for root in roots {
            do {
                // Publish only on actual change: unconditional reassignment
                // fires objectWillChange and re-renders every observing view
                // on every poll tick, even for an idle workspace.
                let listed = try await Task.detached { try Git.list(at: root) }.value
                if trees[root] != listed { trees[root] = listed }
            }
            catch {
                if isFolder(root) && FileManager.default.fileExists(atPath: root) { trees[root] = [Worktree(path: root, branch: URL(fileURLWithPath: root).lastPathComponent)] }
                else { backgroundError = "Background repository refresh failed: \(error.localizedDescription)" }
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
    func refreshChanges(background: Bool = false) async {
        guard let tree = selected, let root = root(for: tree), !isFolder(root) else { return }
        // Status is cheap and drives badges; the full `git diff` can be
        // multi-MB, so background ticks only fetch it when the Changes pane
        // is actually on screen (user-triggered refreshes always include it).
        let includeDiff = !background || changesViewVisible
        do {
            let result = try await Task.detached { () -> (String, String?) in
                let status = try Git.run(["status", "--short"], at: tree.path)
                guard includeDiff else { return (status, nil) }
                let diff = (try? Git.run(["diff", "--no-ext-diff", "--no-color", "HEAD", "--"], at: tree.path)) ?? "No commits yet."
                return (status, diff)
            }.value
            guard selected == tree else { return }
            // Publish only on change; identical status/diff strings fire
            // objectWillChange and re-render the whole changes view anyway.
            if status != result.0 { status = result.0 }
            if let newDiff = result.1, diff != newDiff { diff = newDiff }
        } catch {
            if background { backgroundError = "Background changes refresh failed: " + error.localizedDescription }
            else { self.error = error.localizedDescription }
        }
    }
    func refreshPR() async {
        guard githubEnabled, let path = selected?.path else { return }
        do {
            let output = try await Task.detached { try Shell.run("gh", ["pr", "view", "--json", "number,title,state,url,mergeable,statusCheckRollup"], at: path) }.value
            guard selected?.path == path else { return }; pullRequest = output
        } catch { pullRequest = ErrorExplainer.explain(error.localizedDescription) }
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
        guard let root = root(for: tree), !removingWorktrees.contains(tree.path) else { return }
        guard !(saved.tabs[tree.path] ?? []).contains(where: { closingPaneTabs.contains($0.id) }) else {
            error = "Wait for this worktree's terminal closure to finish before removing it."; return
        }
        removingWorktrees.insert(tree.path); defer { removingWorktrees.remove(tree.path) }
        do {
            // Eligibility must be checked before stopping any running work.
            try await Task.detached { try Git.validateRemoval(tree, at: root) }.value
            let panes = saved.tabs[tree.path]?.flatMap(\.panes) ?? []
            for pane in panes { try await endSession(pane.id) }
            // Recheck after teardown in case files changed during the await.
            try await Task.detached { try Git.remove(tree, at: root) }.value
            for pane in panes { sessions.removeValue(forKey: pane.id) }
            saved.tabs.removeValue(forKey: tree.path); saved.activeTabs?.removeValue(forKey: tree.path)
            saved.pinned.remove(tree.path); saved.archived.remove(tree.path); save()
            await reload()
        } catch {
            // Keep cached ended/error sessions: recreating them can replay a transient command.
            self.error = error.localizedDescription
        }
    }
    /// Repository or folder awaiting "Remove from Grove" confirmation.
    @Published var pendingRootRemoval: String?
    func requestRemoveRoot(_ root: String) { snapshotFocus(); pendingRootRemoval = root }
    /// Forget a repository or folder: end its panes' sessions, then drop its
    /// roots, tabs, pins, archives and repository-scoped scripts. Never touches
    /// files, branches or Git worktrees on disk.
    func removeRoot(_ root: String) async {
        guard saved.roots.contains(root) else { return }
        let paths = Set([root] + (trees[root] ?? []).map(\.path))
        guard paths.allSatisfy({ !removingWorktrees.contains($0) }),
              !paths.flatMap({ saved.tabs[$0] ?? [] }).contains(where: { closingPaneTabs.contains($0.id) }) else {
            error = "Wait for this repository's current terminal or worktree operation to finish."; return
        }
        removingWorktrees.formUnion(paths); defer { removingWorktrees.subtract(paths) }
        let panes = paths.flatMap { saved.tabs[$0] ?? [] }.flatMap(\.panes)
        do { for pane in panes { try await endSession(pane.id) } }
        catch { self.error = "Could not end this repository's terminal sessions: \(error.localizedDescription)"; return }
        for pane in panes { sessions.removeValue(forKey: pane.id) }
        saved.roots.removeAll { $0 == root }
        saved.collapsedRoots?.remove(root)
        saved.scripts.removeAll { $0.root == root }
        for path in paths {
            saved.tabs.removeValue(forKey: path); saved.activeTabs?.removeValue(forKey: path)
            saved.pinned.remove(path); saved.archived.remove(path)
        }
        if let current = selected?.path, paths.contains(current) { selected = nil; saved.selected = nil; status = ""; diff = ""; pullRequest = "" }
        trees.removeValue(forKey: root)
        diffStats = diffStats.filter { !paths.contains($0.key) }
        save()
        await reload()
    }
    func rename(_ tree: Worktree, branch: String) async {
        do { try await Task.detached { try Git.rename(branch, at: tree.path) }.value; await reload(); if let changed = trees.values.flatMap({ $0 }).first(where: { $0.path == tree.path }) { select(changed) } }
        catch { self.error = error.localizedDescription }
    }
    /// URL of the clone currently running, shown with a Cancel button.
    @Published private(set) var cloneInProgress: String?
    private var cloneHandle: ProcessHandle?
    func cancelClone() { cloneHandle?.cancel() }
    /// Why a clone URL is not accepted, or nil when it is (or still empty).
    nonisolated static func cloneURLProblem(_ url: String) -> String? {
        if url.isEmpty { return nil }
        guard url.hasPrefix("https://") || url.hasPrefix("git@") || url.hasPrefix("ssh://") else {
            return "Use an HTTPS or SSH Git URL (https://…, git@…, ssh://…)."
        }
        if url.contains(where: \.isWhitespace) { return "Remove spaces from the URL." }
        return nil
    }
    func clone(_ url: String, to parent: URL) async {
        if url.isEmpty || Self.cloneURLProblem(url) != nil { error = Self.cloneURLProblem(url) ?? "Enter a Git URL."; return }
        guard cloneInProgress == nil else { error = "A clone is already running. Wait for it or cancel it first."; return }
        let handle = ProcessHandle()
        busy = true; cloneInProgress = url; cloneHandle = handle
        defer { busy = false; cloneInProgress = nil; cloneHandle = nil }
        let destination = parent.appendingPathComponent("grove-clone-" + UUID().uuidString.prefix(8))
        do {
            // Abort an HTTP transfer that stays below 1 KB/s for a minute instead of waiting forever.
            let arguments = ["-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=60", "clone", "--", url, destination.path]
            _ = try await Task.detached { try Shell.run("git", arguments, at: parent.path, handle: handle) }.value
            await add(destination.path)
        } catch {
            if handle.isCancelled {
                // The destination name is unique to this clone, so removing a partial checkout is safe.
                if FileManager.default.fileExists(atPath: destination.path) { try? FileManager.default.removeItem(at: destination) }
                showNotice("Clone cancelled.")
            } else { self.error = error.localizedDescription }
        }
    }
    /// A `grove://` action that changes the workspace or runs repository code.
    /// Any web page, document or app can open a `grove://` URL, so these wait
    /// for explicit confirmation instead of running directly.
    enum PendingURLAction: Equatable {
        case open(path: String)
        case newWorktree(branch: String, worktreePath: String)
    }
    @Published var pendingURLAction: PendingURLAction?

    func handle(_ url: URL) { Task { await handleURL(url) } }
    func handleURL(_ url: URL) async {
        guard url.scheme == "grove", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let values = Dictionary((parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        await reload()
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
        }
        if url.host != "open", let path = values["path"] {
            guard let tree = trees.values.flatMap({ $0 }).first(where: { $0.path == path }) else { error = "That worktree is not in this workspace."; return }
            select(tree)
        }
        switch url.host {
        case "open":
            guard let path = values["path"] else { return }
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            let candidates: Set<String> = [path, standardized]
            if let known = trees.values.flatMap({ $0 }).first(where: { candidates.contains($0.path) }) { select(known) }
            else if let root = roots.first(where: { candidates.contains($0) }) { await add(root) }
            else { snapshotFocus(); pendingURLAction = .open(path: standardized) }
        case "new-tab": addTab()
        case "split": if let path = selected?.path {
            let tabs = saved.tabs[path] ?? []
            if let tab = tabs.first(where: { $0.id == saved.activeTabs?[path] }) ?? tabs.last { split(tab: tab.id, vertical: values["direction"] == "vertical") }
        }
        case "new-worktree":
            guard let branch = values["branch"], let path = selected?.path else { return }
            snapshotFocus(); pendingURLAction = .newWorktree(branch: branch, worktreePath: path)
        case "select": break
        default: error = "Unknown Grove URL action."
        }
    }
    /// Takes the action captured when the user confirmed: dismissing the alert
    /// clears `pendingURLAction` before this async work runs.
    func confirmURLAction(_ action: PendingURLAction?) async {
        guard let action else { return }
        pendingURLAction = nil
        switch action {
        case .open(let path): await add(path)
        case .newWorktree(let branch, let path):
            // The workspace may have changed while the confirmation was shown.
            guard let tree = trees.values.flatMap({ $0 }).first(where: { $0.path == path }) else { error = "That worktree is no longer in this workspace."; return }
            select(tree)
            await create(branch)
        }
    }
    func resetWorkspaceMetadata(deleteRecoveryCopy: Bool = false) {
        for session in sessions.values { session.detach() }
        sessions.removeAll(); saved = SavedWorkspace(); selected = nil; trees = [:]
        WorkspacePersistence.reset(deleteRecoveryCopy: deleteRecoveryCopy); workspaceStorageBlocked = false; save()
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

/// Lets the main actor cancel a command running on a detached task. A cancel
/// that arrives before the process starts terminates it as soon as it does.
final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    /// Returns false when the command was already cancelled.
    func attach(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        return !cancelled
    }
    func cancel() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }
}

enum Shell {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func run(_ executable: String, _ args: [String], at path: String, allowFailure: Bool = false, handle: ProcessHandle? = nil) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env; process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        try process.run()
        if let handle, !handle.attach(process) { process.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard allowFailure || process.terminationStatus == 0 else { throw CommandError(message: output) }; return output
    }
}
