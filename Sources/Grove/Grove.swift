import SwiftUI
import AppKit

@main struct GroveApp: App {
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(workspace)
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(workspace.appearance == "system" ? nil : workspace.appearance == "light" ? .light : .dark)
                .onOpenURL { workspace.handle($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Command Palette…") { workspace.palette = true }.keyboardShortcut("k", modifiers: .command)
                Button("Command Palette… (⇧⌘P)") { workspace.palette = true }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Add Repository…") { workspace.open() }.keyboardShortcut("o")
                Button("New Terminal Tab") { workspace.terminal() }.keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Scripts") {
                Button("Run Primary Script") { if let script = workspace.primaryScript { workspace.runScript(script) } }
                    .keyboardShortcut("r").disabled(workspace.primaryScript == nil || workspace.selected == nil)
                Button("Stop Primary Script") {
                    if let path = workspace.selected?.path, let script = workspace.primaryScript,
                       let tab = workspace.saved.tabs[path]?.first(where: { $0.scriptID == script.id }) {
                        Task { await workspace.stopScript(tab) }
                    }
                }.keyboardShortcut(".").disabled(workspace.primaryScript == nil || workspace.selected == nil)
            }
            CommandMenu("Workspace") {
                Button("Find in Terminal…") {
                    // Keyboard-first fallback: if no terminal holds focus, focus
                    // the selected worktree's terminal first, then open find.
                    let view = workspace.focusTerminalPane()
                    DispatchQueue.main.async {
                        guard view != nil || workspace.focusTerminalPane() != nil else { return }
                        let item = NSMenuItem(); item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                    }
                }.keyboardShortcut("f")
                Button("Close Pane / Tab") { workspace.closeFocused() }
                    .keyboardShortcut("w").disabled(workspace.selected == nil)
                Button("Split Left / Right") {
                    if let path = workspace.selected?.path, let active = workspace.activeTab(at: path) { workspace.split(tab: active.id, vertical: true) }
                }.keyboardShortcut("d").disabled(workspace.selected == nil)
                Button("Split Top / Bottom") {
                    if let path = workspace.selected?.path, let active = workspace.activeTab(at: path) { workspace.split(tab: active.id, vertical: false) }
                }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(workspace.selected == nil)
                Button("Next Tab") { workspace.cycleTab(offset: 1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(workspace.selected == nil)
                Button("Previous Tab") { workspace.cycleTab(offset: -1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(workspace.selected == nil)
                Divider()
                Button("Next Worktree Needing Attention") { workspace.jumpToNextAttention() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("New Worktree…") { workspace.snapshotFocus(); workspace.showCreateSheet = true }
                    .keyboardShortcut("n").disabled(workspace.selected == nil || workspace.busy)
                Button("Pin / Unpin Worktree") { if let tree = workspace.selected { workspace.pin(tree) } }
                    .disabled(workspace.selected == nil)
                Button("Archive / Unarchive Worktree") { if let tree = workspace.selected { workspace.archive(tree) } }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift]).disabled(workspace.selected == nil)
                Button("Rename Branch…") { workspace.requestRenameSelected() }
                    .disabled(workspace.selected == nil)
                Button("Remove Worktree…", role: .destructive) {
                    if let tree = workspace.selected { workspace.requestRemove(tree) }
                }.keyboardShortcut(.delete, modifiers: [.command]).disabled(workspace.selected == nil)
                Button("Copy Worktree Path") { workspace.copyWorktreePath() }
                    .keyboardShortcut("c", modifiers: [.command, .control]).disabled(workspace.selected == nil)
                Button("Copy Branch Name") { workspace.copyBranchName() }
                    .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(workspace.selected == nil)
                ForEach(1..<10, id: \.self) { index in
                    Button("Go to worktree \(index)") {
                        let trees = workspace.roots.flatMap { workspace.visibleTrees($0) }
                        if trees.indices.contains(index - 1) { workspace.select(trees[index - 1]) }
                    }.keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .control)
                }
                Divider()
                Button("Quit and End Grove Sessions…") {
                    let alert = NSAlert(); alert.messageText = "End all saved Grove terminal sessions?"; alert.informativeText = "This stops processes running in those sessions. Regular Quit keeps persistent sessions alive."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "End Sessions and Quit")
                    if alert.runModal() == .alertSecondButtonReturn { workspace.endSessionsAndQuit() }
                }
            }
        }
        Settings { SettingsView().environmentObject(workspace) }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.colorScheme) private var colorScheme
    @State private var renamedBranch = ""
    @State private var branch = ""
    @State private var search = ""
    @State private var searchCollapsedRoots = Set<String>()
    @State private var reviewing = false
    @State private var browsing = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var profile = PerformanceProfileManager.shared
    private let accent = Color(red: 0.68, green: 0.88, blue: 0.51)
    private var theme: AppTheme {
        AppTheme.resolved(tier: profile.effectiveTier, animationsEnabled: profile.animationsEnabled,
                          scheme: colorScheme, reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "leaf.fill").foregroundStyle(accent).font(.title2)
                    Text("grove").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("LOCAL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }.padding(.top, 24)
                Text("A little space for big ideas.").font(.caption).foregroundStyle(.secondary)
                TextField("Find a worktree…", text: $search).textFieldStyle(.roundedBorder)
                HStack { Text("REPOSITORIES").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary); Spacer(); Button { model.open() } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Add repository") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(model.roots, id: \.self) { root in
                            DisclosureGroup(isExpanded: Binding(
                                get: { search.isEmpty ? model.saved.collapsedRoots?.contains(root) != true : !searchCollapsedRoots.contains(root) },
                                set: { expanded in
                                    if search.isEmpty {
                                        var collapsed = model.saved.collapsedRoots ?? []
                                        if expanded { collapsed.remove(root) } else { collapsed.insert(root) }
                                        model.saved.collapsedRoots = collapsed; model.save()
                                    } else {
                                        if expanded { searchCollapsedRoots.remove(root) } else { searchCollapsedRoots.insert(root) }
                                    }
                                }
                            )) {
                                ForEach(model.visibleTrees(root).filter { search.isEmpty || $0.branch.localizedCaseInsensitiveContains(search) }) { tree in
                                    WorktreeRow(tree: tree, isSelected: model.selected == tree, accent: accent)
                                        .contentShape(Rectangle())
                                        .onTapGesture { model.select(tree) }
                                    .contextMenu {
                                        Button(model.saved.pinned.contains(tree.path) ? "Unpin" : "Pin") { model.pin(tree) }
                                        Button(model.saved.archived.contains(tree.path) ? "Unarchive" : "Archive") { model.archive(tree) }
                                        Button("Rename branch…") { renamedBranch = tree.branch; model.requestRename(tree) }
                                        Button("Remove worktree…", role: .destructive) { model.requestRemove(tree) }.disabled(tree.path == root || model.isFolder(root))
                                        Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tree.path) }
                                    }
                                }
                            } label: {
                                Label(URL(fileURLWithPath: root).lastPathComponent, systemImage: "folder")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { model.snapshotFocus(); model.showCreateSheet = true } label: { Label("New worktree", systemImage: "plus").frame(maxWidth: .infinity).padding(7) }
                    .buttonStyle(.bordered).disabled(model.selected == nil || model.busy)
                Toggle("Show archived", isOn: $model.showArchived).font(.caption)
                PerformancePill(profile: profile, accent: accent)
                Button("Command palette  ⌘K") { model.snapshotFocus(); model.palette = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 245)
                .background(theme.material.map { AnyShapeStyle($0) } ?? AnyShapeStyle(theme.sidebarBackground))
                .environment(\.appTheme, theme)
            Divider()
            VStack(spacing: 0) {
                if let tree = model.selected {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tree.branch).font(.system(size: 15, weight: .semibold))
                            Text(tree.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tree.path) } label: { Image(systemName: "folder") }.help("Reveal in Finder")
                        Button { model.terminal() } label: { Label("New tab", systemImage: "plus") }.help("Add an embedded interactive terminal")
                        Button { browsing.toggle() } label: { Image(systemName: "sidebar.right") }.help("Browse files")
                        Button { reviewing.toggle(); Task { await model.reload(); await model.refreshChanges() } } label: { Label("Changes", systemImage: "square.stack.3d.up") }
                    }.buttonStyle(.bordered).padding(22)
                    Divider()
                    if reviewing {
                        HStack { Label("WORKING TREE", systemImage: "arrow.triangle.branch"); Spacer(); Button("Refresh") { Task { await model.reload(); await model.refreshChanges() } } }.font(.caption).padding()
                        ChangesDiffView(statusText: model.status, diffText: model.diff)
                    } else { HSplitView { SessionTabs(path: tree.path).id(tree.path); if browsing { FileBrowser(root: tree.path).id(tree.path) } } }
                } else {
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(accent)
                    Text("Room to branch out.").font(.system(size: 30, weight: .medium, design: .rounded)).padding(.top, 12)
                    Text("One repository. Independent worktrees.\nA focused space for every coding task.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(10)
                    Button("Add your first repository…") { model.open() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).padding()
                    Spacer()
                    Text("GROVE  /  A LOCAL CODING WORKSPACE").font(.system(size: 10)).tracking(2).foregroundStyle(.secondary).padding(30)
                }
            }.background(theme.material.map { AnyShapeStyle($0) } ?? AnyShapeStyle(theme.mainBackground))
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if let notice = model.transientNotice {
                    NoticeBanner(text: notice, style: .info) { model.transientNotice = nil }
                }
                if let background = model.backgroundError {
                    NoticeBanner(text: background, style: .warning) { model.backgroundError = nil }
                }
            }.padding(.bottom, 6)
        }
        .animation(theme.animationsEnabled ? .easeInOut(duration: 0.15) : nil, value: profile.effectiveTier)
        .environment(\.appTheme, theme)
        .onChange(of: search) { _, _ in searchCollapsedRoots.removeAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            Task { await model.reload() }
        }
        .task {
            if let path = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"] {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    let info: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "windows": NSApp.windows.map { ["id": $0.windowNumber, "title": $0.title] }]
                    if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) { try? data.write(to: URL(fileURLWithPath: path + "/grove-runtime.json")) }
                }
            }
            await model.reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(PerformanceProfileManager.shared.statusPollInterval)) } catch { break }
                guard NSApp.isActive else { continue }
                await model.reload(); await model.refreshChanges(background: true); await model.pollDiffStats()
            }
        }
        .sheet(isPresented: Binding(get: { model.pendingRename != nil }, set: { if !$0 { model.pendingRename = nil } }), onDismiss: { model.restoreFocus() }) {
            VStack(spacing: 20) { Text("Rename branch").font(.headline); TextField("Branch name", text: $renamedBranch)
                HStack { Button("Cancel") { model.pendingRename = nil }
                    Button("Rename") { if let tree = model.pendingRename { Task { await model.rename(tree, branch: renamedBranch) } }; model.pendingRename = nil } } }
            .padding(30).frame(width: 350)
            .onAppear { renamedBranch = model.pendingRename?.branch ?? "" }
        }
        .sheet(isPresented: Binding(get: { model.pendingRemove != nil }, set: { if !$0 { model.pendingRemove = nil } }), onDismiss: { model.restoreFocus() }) {
            RemoveWorktreeDialog(tree: model.pendingRemove) { model.pendingRemove = nil }
        }
        .sheet(isPresented: $model.palette, onDismiss: { model.restoreFocus() }) { PaletteView() }
        .sheet(isPresented: $model.showCreateSheet, onDismiss: { model.restoreFocus() }) {
            VStack(alignment: .leading, spacing: 18) {
                Label("A fresh branch, a focused task.", systemImage: "arrow.triangle.branch").font(.title2)
                Text("Creates a new branch from the configured base reference in a sibling .grove-worktrees directory. Your current files stay in place.").foregroundStyle(.secondary)
                TextField("feature/my-next-idea", text: $branch).textFieldStyle(.roundedBorder).onSubmit { create() }
                if model.busy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Creating worktree…").font(.caption).foregroundStyle(.secondary) } }
                HStack { Spacer(); Button("Cancel") { model.showCreateSheet = false }
                    Button("Create worktree") { create() }.buttonStyle(.borderedProminent).disabled(branch.isEmpty || model.busy) }
            }.padding(30).frame(width: 460)
        }
        .alert("Grove needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.error) { _, newValue in
            if newValue == nil { model.restoreFocus() }
        }
    }
    private func create() { let name = branch; model.showCreateSheet = false; branch = ""; Task { await model.create(name) } }
}


struct SessionTabs: View {
    @EnvironmentObject var model: Workspace
    let path: String
    @Environment(\.openSettings) private var openSettings
    @State private var renaming: TabRecord?
    @State private var tabName = ""
    var tabs: [TabRecord] { model.saved.tabs[path] ?? [] }
    var active: TabRecord? { tabs.first(where: { $0.id == model.saved.activeTabs?[path] }) ?? tabs.last }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tabs) { tab in
                            HStack(spacing: 8) {
                                Button { model.saved.activeTabs = model.saved.activeTabs ?? [:]; model.saved.activeTabs?[path] = tab.id; model.save() } label: { Label(tab.name, systemImage: "terminal") }.buttonStyle(.plain)
                                Button { model.snapshotFocus(); model.pendingClose = Workspace.CloseRequest(path: path, tab: tab.id, pane: nil) } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain)
                            }.contextMenu {
                                Button("Rename…") { tabName = tab.name; renaming = tab }
                                Button("Move left") { model.moveTab(tab.id, offset: -1) }
                                Button("Move right") { model.moveTab(tab.id, offset: 1) }
                            }.padding(10).background(active?.id == tab.id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                Button { model.addTab() } label: { Image(systemName: "plus") }.help("New tab")
                Menu {
                    Button("Split left / right") { if let active { model.split(tab: active.id, vertical: true) } }
                    Button("Split top / bottom") { if let active { model.split(tab: active.id, vertical: false) } }
                } label: { Image(systemName: "rectangle.split.2x1") }
                if let active, active.scriptID != nil {
                    Button("Stop") { Task { await model.stopScript(active) } }.help("End this script tab's processes")
                    Button("Restart") { Task { await model.restartScript(active) } }.help("Run the saved command again")
                }
                Menu("Scripts") {
                    ForEach(model.availableScripts) { script in
                        Button { model.runScript(script) } label: { Label(script.name, systemImage: script.icon).foregroundStyle(script.color) }
                    }
                    Button("Manage scripts…") { openSettings() }
                }
                OpenMenu(path: path)
            }.font(.system(size: 11)).padding(10)
            Divider()
            if let active {
                if let layout = active.layout { splitView(layout, panes: active.panes) }
                else if active.vertical { HSplitView { ForEach(active.panes) { pane in paneView(pane).frame(minWidth: 180) } } }
                else { VSplitView { ForEach(active.panes) { pane in paneView(pane).frame(minHeight: 100) } } }
            }
        }
        .sheet(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            VStack(spacing: 20) { Text("Rename terminal tab").font(.headline); TextField("Tab name", text: $tabName); HStack { Button("Cancel") { renaming = nil }; Button("Save") { if let renaming { model.renameTab(renaming.id, name: tabName) }; renaming = nil } } }.padding(30).frame(width: 350)
        }
        .alert(closingPane == nil ? "Close this tab?" : "Close this split?", isPresented: Binding(get: { model.pendingClose != nil }, set: { if !$0 { model.pendingClose = nil } })) {
            Button("Cancel", role: .cancel) { model.pendingClose = nil }
            Button(closingPane == nil ? "Close Tab" : "Close Split", role: .destructive) {
                if let request = model.pendingClose {
                    if let pane = request.pane { Task { await model.closePane(pane, in: request.tab, at: request.path) } }
                    else if let tab = tabs.first(where: { $0.id == request.tab }) { Task { await model.closeTab(tab, at: request.path) } }
                }
                model.pendingClose = nil
                model.restoreFocus()
            }
        } message: {
            Text(closingPane == nil ? "Closing a tab ends its terminal sessions and running commands. Regular Quit keeps persistent sessions alive." : "This ends the terminal session and running commands in this pane. Other panes stay open.")
        }
    }
    private var closingPane: UUID? { model.pendingClose?.pane }
    func splitView(_ node: SplitNode, panes: [PaneRecord]) -> AnyView {
        switch node {
        case .pane(let id): return AnyView(Group { if let record = panes.first(where: { $0.id == id }) { paneView(record).frame(minWidth: 160, minHeight: 100) } })
        case .split(let vertical, let first, let second):
            if vertical { return AnyView(HSplitView { splitView(first, panes: panes); splitView(second, panes: panes) }) }
            return AnyView(VSplitView { splitView(first, panes: panes); splitView(second, panes: panes) })
        }
    }
    func paneView(_ record: PaneRecord) -> some View {
        TerminalPane(session: model.session(record), path: path, onClose: (active?.panes.count ?? 0) > 1 ? {
            if let active { model.snapshotFocus(); model.pendingClose = Workspace.CloseRequest(path: path, tab: active.id, pane: record.id) }
        } : nil)
    }
}

struct TerminalPane: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.appTheme) private var theme
    @ObservedObject var session: Session
    let path: String
    var onClose: (() -> Void)? = nil
    private var isFocused: Bool { model.focusedPaneID == session.id }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.color)
                    .accessibilityLabel(status.accessibilityLabel)
                Text(session.title).lineLimit(1)
                Spacer()
                Text(session.state).foregroundStyle(.secondary)
                Button("⌃C") { session.interrupt() }.buttonStyle(.plain).help("Send interrupt")
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Close split").accessibilityLabel("Close split")
                }
            }.font(.system(size: 10)).padding(8)
            EmbeddedTerminal(session: session, path: path, fontName: model.fontName, fontSize: model.fontSize, persistent: model.usePersistentTerminals, background: theme.terminalBackground)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isFocused ? theme.accent : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isFocused ? "Focused terminal: \(session.title)" : "Terminal: \(session.title)")
    }
    private var status: WorktreeStatus { WorktreeStatus.parse(session.state) }
}

// MARK: - Sidebar triage row

struct WorktreeRow: View {
    @EnvironmentObject var model: Workspace
    let tree: Worktree
    let isSelected: Bool
    let accent: Color
    var body: some View {
        let status = model.stableStatus(for: tree.path)
        let summary = model.diffStats[tree.path]
        let compact = model.compactSidebar
        HStack(spacing: 6) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .font(.system(size: compact ? 9 : 10))
                .accessibilityLabel(status.accessibilityLabel)
            Text(tree.branch)
                .font(.system(size: compact ? 11 : 12, design: .monospaced))
                .lineLimit(1)
            if let summary, summary.dirty {
                Text(compact || !summary.hasLineCounts ? "•" : "+\(summary.additions) −\(summary.deletions)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.saved.pinned.contains(tree.path) { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(accent) }
        }
        .padding(compact ? 4 : 10)
        .background(isSelected ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Worktree \(tree.branch), \(status.accessibilityLabel)\(summary?.dirty == true ? ", uncommitted changes" : "")")
    }
}

// MARK: - Performance status pill (SF Symbols, fixed-width label; trigger text lives in the popover only)

struct PerformancePill: View {
    @ObservedObject var profile: PerformanceProfileManager
    let accent: Color
    @State private var showPopover = false
    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: profile.effectiveTier == .efficient ? "leaf.fill" : "bolt.fill")
                Text(profile.effectiveTier == .efficient ? "Efficient" : "High Perf")
                    .frame(width: 58, alignment: .leading)
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Performance profile")
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            PerformancePopover(profile: profile, accent: accent).frame(width: 300)
        }
        .accessibilityLabel("Performance profile: \(profile.effectiveTier == .efficient ? "Efficient" : "High Performance")")
    }
}

struct PerformancePopover: View {
    @ObservedObject var profile: PerformanceProfileManager
    @EnvironmentObject var model: Workspace
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Performance").font(.headline)
            Picker("Mode", selection: $profile.profile) {
                ForEach(PerformanceProfile.allCases) { mode in Text(mode.label).tag(mode) }
            }.pickerStyle(.inline)
            .labelsHidden()
            Text("Efficient uses opaque surfaces and fewer visual effects. Auto adapts to Low Power Mode and sustained thermal pressure.").font(.caption).foregroundStyle(.secondary)
            if !profile.activeTriggers.isEmpty {
                Label(profile.activeTriggers.joined(separator: ", "), systemImage: "bolt.badge.clock")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            // Metrics computed on open; never a continuously published loop.
            HStack {
                Text("Terminal panes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.saved.tabs.values.flatMap { $0 }.reduce(0) { $0 + $1.panes.count })").font(.caption.monospacedDigit())
            }
            HStack {
                Text("Visual tier").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(profile.effectiveTier == .efficient ? "Efficient" : "High Performance").font(.caption)
            }
        }.padding(16)
    }
}

// MARK: - Shared banner strip (background errors + reattach notices; replaces, never stacks per-source)

struct NoticeBanner: View {
    enum Style { case info, warning }
    let text: String
    let style: Style
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(style == .warning ? Color.orange : Color.green)
            Text(text).font(.caption).lineLimit(2)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 8)) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss notice")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Risk-displayed remove dialog (sheet-hosted: ⌘Return confirm / Esc cancel work reliably here)

struct RemoveWorktreeDialog: View {
    @EnvironmentObject var model: Workspace
    let tree: Worktree?
    let dismiss: () -> Void
    @State private var unpushedCount: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Remove worktree?", systemImage: "trash").font(.headline)
            Text(tree.map { "Remove worktree \"\(URL(fileURLWithPath: $0.path).lastPathComponent)\" (\($0.branch))?" } ?? "").font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                Text("The checkout is deleted. The branch \(tree.map { "\"\($0.branch)\"" } ?? "and its commits") and its commits are kept.").font(.caption).foregroundStyle(.secondary)
                if let unpushedCount, unpushedCount > 0 {
                    Label("\(unpushedCount) unpushed commit\(unpushedCount == 1 ? "" : "s") — branch is kept, but not backed up remotely.", systemImage: "arrow.up.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if runningPanes > 0 {
                    Label("\(runningPanes) pane\(runningPanes == 1 ? " has" : "s have") a running program — its session will be terminated.", systemImage: "bolt.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Text("Uncommitted files block removal and are never deleted.").font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Remove Worktree", role: .destructive) {
                    if let tree { Task { await model.remove(tree) } }
                    dismiss()
                }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 430)
        .task { await gatherRisks() }
    }
    private var runningPanes: Int {
        guard let tree else { return 0 }
        let panes = model.saved.tabs[tree.path]?.flatMap(\.panes) ?? []
        return panes.filter { WorktreeStatus.parse(model.session($0).state) == .running }.count
    }
    private func gatherRisks() async {
        guard let tree else { return }
        let path = tree.path
        unpushedCount = await Task.detached { () -> Int? in
            // Probe upstream first: rev-list @{u} fails on branches without an upstream.
            guard (try? Git.run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], at: path)) != nil,
                  let log = try? Git.run(["rev-list", "--count", "@{u}..HEAD"], at: path) else { return nil }
            return Int(log.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}

// MARK: - PR badge (green-quiet, red-loud: only rendered when state/mergeability needs attention)

struct PullRequestBadge: View {
    let json: String
    var body: some View {
        if let data = json.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let number = values["number"] as? Int,
           (values["state"] as? String) == "OPEN",
           (values["mergeable"] as? String) != "MERGEABLE" {
            Text("#\(number)")
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
                .accessibilityLabel("Pull request #\(number) needs attention")
        }
    }
}
