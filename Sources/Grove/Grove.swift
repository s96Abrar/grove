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
                Button("Command Palette…") { workspace.palette = true }.keyboardShortcut("p", modifiers: [.command, .shift])
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
                    let item = NSMenuItem(); item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                }.keyboardShortcut("f")
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
    @State private var deleting: Worktree?
    @State private var renamingTree: Worktree?
    @State private var renamedBranch = ""
    @State private var creating = false
    @State private var branch = ""
    @State private var search = ""
    @State private var reviewing = false
    @State private var browsing = false
    private let accent = Color(red: 0.68, green: 0.88, blue: 0.51)
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
                            VStack(alignment: .leading, spacing: 7) {
                                Label(URL(fileURLWithPath: root).lastPathComponent, systemImage: "folder").font(.system(size: 13, weight: .semibold)).padding(.bottom, 5)
                                ForEach(model.visibleTrees(root).filter { search.isEmpty || $0.branch.localizedCaseInsensitiveContains(search) }) { tree in
                                    Button { model.select(tree) } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: "arrow.triangle.branch").foregroundStyle(model.selected == tree ? accent : .secondary)
                                            Text(tree.branch).lineLimit(1)
                                            Spacer()
                                            if model.saved.pinned.contains(tree.path) { Image(systemName: "pin.fill").foregroundStyle(accent) }
                                        }.font(.system(size: 12)).padding(10)
                                            .background(model.selected == tree ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button(model.saved.pinned.contains(tree.path) ? "Unpin" : "Pin") { model.pin(tree) }
                                        Button(model.saved.archived.contains(tree.path) ? "Unarchive" : "Archive") { model.archive(tree) }
                                        Button("Rename branch…") { renamedBranch = tree.branch; renamingTree = tree }
                                        Button("Remove worktree…", role: .destructive) { deleting = tree }.disabled(tree.path == root || model.isFolder(root))
                                        Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tree.path) }
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button { creating = true } label: { Label("New worktree", systemImage: "plus").frame(maxWidth: .infinity).padding(7) }
                    .buttonStyle(.bordered).disabled(model.selected == nil || model.busy).keyboardShortcut("n")
                Toggle("Show archived", isOn: $model.showArchived).font(.caption)
                Button("Command palette  ⇧⌘P") { model.palette = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack { Circle().fill(accent).frame(width: 6, height: 6); Text("On your machine. In your control.").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(20).frame(width: 245).background(colorScheme == .dark ? Color(red: 0.085, green: 0.095, blue: 0.09) : Color(nsColor: .controlBackgroundColor))
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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(model.status.isEmpty ? "Working tree is clean." : model.status).foregroundStyle(accent)
                                Text(model.diff.isEmpty ? "No tracked changes. Untracked files appear above; add them with Git to include them in the diff." : model.diff)
                            }.font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(22)
                        }
                    } else { HSplitView { SessionTabs(path: tree.path).id(tree.path); if browsing { FileBrowser(root: tree.path).id(tree.path) } } }
                    Divider()
                    HStack { Image(systemName: "externaldrive"); Text("Isolated worktree"); Spacer(); Text("⌘N  new worktree    ⇧⌘T  new terminal tab") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(12)
                } else {
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(accent)
                    Text("Room to branch out.").font(.system(size: 30, weight: .medium, design: .rounded)).padding(.top, 12)
                    Text("One repository. Independent worktrees.\nA focused space for every coding task.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(10)
                    Button("Add your first repository…") { model.open() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).padding()
                    Spacer()
                    Text("GROVE  /  A LOCAL CODING WORKSPACE").font(.system(size: 10)).tracking(2).foregroundStyle(.secondary).padding(30)
                }
            }.background(colorScheme == .dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : Color(nsColor: .windowBackgroundColor))
        }
        .task {
            if let path = ProcessInfo.processInfo.environment["GROVE_VERIFY_PATH"] {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    let info: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "windows": NSApp.windows.map { ["id": $0.windowNumber, "title": $0.title] }]
                    if let data = try? JSONSerialization.data(withJSONObject: info, options: .prettyPrinted) { try? data.write(to: URL(fileURLWithPath: path + "/grove-runtime.json")) }
                }
            }
            await model.reload(); while !Task.isCancelled { do { try await Task.sleep(for: .seconds(5)) } catch { break }; await model.reload(); await model.refreshChanges() } }
        .sheet(isPresented: Binding(get: { renamingTree != nil }, set: { if !$0 { renamingTree = nil } })) {
            VStack(spacing: 20) { Text("Rename branch").font(.headline); TextField("Branch name", text: $renamedBranch); HStack { Button("Cancel") { renamingTree = nil }; Button("Rename") { if let tree = renamingTree { Task { await model.rename(tree, branch: renamedBranch) } }; renamingTree = nil } } }.padding(30).frame(width: 350)
        }
        .confirmationDialog("Remove this worktree? Uncommitted files will block removal. The branch is kept.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove worktree", role: .destructive) { if let tree = deleting { Task { await model.remove(tree) } }; deleting = nil }
        }
        .sheet(isPresented: $model.palette) { PaletteView() }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 18) {
                Label("A fresh branch, a focused task.", systemImage: "arrow.triangle.branch").font(.title2)
                Text("Creates a new branch from the configured base reference in a sibling .grove-worktrees directory. Your current files stay in place.").foregroundStyle(.secondary)
                TextField("feature/my-next-idea", text: $branch).textFieldStyle(.roundedBorder).onSubmit { create() }
                HStack { Spacer(); Button("Cancel") { creating = false }; Button("Create worktree") { create() }.buttonStyle(.borderedProminent).disabled(branch.isEmpty || model.busy) }
            }.padding(30).frame(width: 460)
        }
        .alert("Grove needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func create() { let name = branch; creating = false; branch = ""; Task { await model.create(name) } }
}


struct SessionTabs: View {
    @EnvironmentObject var model: Workspace
    let path: String
    @Environment(\.openSettings) private var openSettings
    @State private var closing: TabRecord?
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
                                Button { closing = tab } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain)
                            }.contextMenu {
                                Button("Rename…") { tabName = tab.name; renaming = tab }
                                Button("Move left") { model.moveTab(tab.id, offset: -1) }
                                Button("Move right") { model.moveTab(tab.id, offset: 1) }
                            }.padding(10).background(active?.id == tab.id ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
        .alert("Close this tab?", isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } })) {
            Button("Cancel", role: .cancel) { closing = nil }
            Button("Close", role: .destructive) { if let closing { Task { await model.closeTab(closing) } }; closing = nil }
        } message: { Text("Closing a tab ends its terminal sessions and running commands. Regular Quit keeps persistent sessions alive.") }
    }
    func splitView(_ node: SplitNode, panes: [PaneRecord]) -> AnyView {
        switch node {
        case .pane(let id): return AnyView(Group { if let record = panes.first(where: { $0.id == id }) { paneView(record).frame(minWidth: 160, minHeight: 100) } })
        case .split(let vertical, let first, let second):
            if vertical { return AnyView(HSplitView { splitView(first, panes: panes); splitView(second, panes: panes) }) }
            return AnyView(VSplitView { splitView(first, panes: panes); splitView(second, panes: panes) })
        }
    }
    func paneView(_ record: PaneRecord) -> some View {
        TerminalPane(session: model.session(record), path: path)
    }
}

struct TerminalPane: View {
    @EnvironmentObject var model: Workspace
    @ObservedObject var session: Session
    let path: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(session.state.hasPrefix("Exited") ? .gray : .green).frame(width: 5, height: 5)
                Text(session.title).lineLimit(1)
                Spacer()
                Text(session.state).foregroundStyle(.secondary)
                Button("⌃C") { session.interrupt() }.buttonStyle(.plain).help("Send interrupt")
            }.font(.system(size: 10)).padding(8)
            EmbeddedTerminal(session: session, path: path, fontSize: model.fontSize, persistent: model.usePersistentTerminals)
        }
    }
}
