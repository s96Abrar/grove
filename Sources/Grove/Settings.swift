import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: Workspace
    @State private var resetting = false
    var body: some View {
        TabView {
            Form {
                Picker("Appearance", selection: $model.appearance) { Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system") }
                Slider(value: $model.fontSize, in: 10...24, step: 1) { Text("Terminal font: \(Int(model.fontSize)) pt") }
                Toggle("Keep terminal sessions alive with tmux", isOn: $model.persistent)
                Text("New terminals use Grove’s own tmux server. Quit detaches; reopening restores sessions. Existing screen sessions stay attached until closed.").font(.caption).foregroundStyle(.secondary)
                if PersistentTerminal.tmux == nil {
                    Text("Install tmux for persistent terminals: brew install tmux").font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                TextField("New worktree base ref", text: $model.baseRef)
                Toggle("Fetch before creating worktrees", isOn: $model.fetchBeforeCreate)
                if model.workspaceStorageBlocked { Text("Workspace metadata needs recovery.").foregroundStyle(.orange) }
                Button("Reset Workspace Metadata…", role: .destructive) { resetting = true }
                Toggle("Enable GitHub CLI integration", isOn: $model.githubEnabled)
                Text("Uses your local gh authentication. No account, analytics, telemetry or license activation is required by Grove.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label("General", systemImage: "gear") }
            ScriptSettingsView().tabItem { Label("Scripts", systemImage: "play") }
            ShortcutsHelpView().tabItem { Label("Help", systemImage: "questionmark.circle") }
        }.frame(width: 660, height: 640)
        .confirmationDialog("Reset saved repositories, scripts and terminal layouts? Your source files and Git worktrees are kept. Existing persistent sessions are detached.", isPresented: $resetting) {
            Button("Reset Workspace Metadata", role: .destructive) { model.resetWorkspaceMetadata() }
        }
    }
}

struct PaletteView: View {
    @EnvironmentObject var model: Workspace
    @State private var query = ""
    @State private var branch = ""
    @State private var cloneURL = ""
    @State private var creating = false
    @State private var cloning = false
    struct Action: Identifiable { var id: String { key ?? name }; var key: String? = nil; let name: String; let icon: String; let run: () -> Void }
    var actions: [Action] {
        var result = [
            Action(name: "Add folder or repository", icon: "folder.badge.plus", run: { model.open() }),
            Action(name: "New terminal tab", icon: "terminal", run: { model.addTab() }),
            Action(name: "Create worktree…", icon: "arrow.triangle.branch", run: { creating = true }),
            Action(name: "Clone repository…", icon: "square.and.arrow.down", run: { cloning = true }),
            Action(name: "Refresh repositories", icon: "arrow.clockwise", run: { Task { await model.reload() } }),
            Action(name: "Refresh GitHub pull request", icon: "arrow.triangle.pull", run: { Task { await model.refreshPR() } })
        ]
        for root in model.roots {
            for tree in model.trees[root] ?? [] { result.append(Action(name: "Go to \(URL(fileURLWithPath: root).lastPathComponent) / \(tree.branch)", icon: "arrow.triangle.branch", run: { model.select(tree) })) }
        }
        for script in model.availableScripts { result.append(Action(key: script.id.uuidString, name: "Run script: \(script.name)", icon: script.icon, run: { model.runScript(script) })) }
        return result.filter { query.isEmpty || Self.matches(query, in: $0.name) }
    }
    static func matches(_ needle: String, in haystack: String) -> Bool {
        var remaining = haystack.lowercased()[...]
        for character in needle.lowercased() {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Where do you want to go?", text: $query).font(.title3).textFieldStyle(.plain).onSubmit { executeFirst() }
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        Button { action.run(); if !creating && !cloning { model.palette = false } } label: { HStack { Label(action.name, systemImage: action.icon); Spacer(); Image(systemName: "return") }.padding(10).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                }
            }
            if creating {
                TextField("New branch name", text: $branch)
                Button("Create worktree") { Task { await model.create(branch) }; model.palette = false }.disabled(branch.isEmpty)
            }
            if cloning {
                TextField("HTTPS or SSH Git URL", text: $cloneURL)
                Button("Choose destination and clone…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let parent = panel.url { Task { await model.clone(cloneURL, to: parent) }; model.palette = false }
                }.disabled(cloneURL.isEmpty)
            }
            if !model.pullRequest.isEmpty { ScrollView { Text(model.pullRequest).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }.frame(height: 100) }
            HStack { Text("GROVE COMMANDS").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Done") { model.palette = false }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 560, height: 420)
    }
    func executeFirst() { if let action = actions.first { action.run(); if !creating && !cloning { model.palette = false } } }
}

struct ShortcutsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard shortcuts").font(.title2)
                Text("⌘ Command   ⇧ Shift   ⌃ Control").font(.callout).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 12) {
                    shortcut("Add repository or folder", "⌘O")
                    shortcut("Create worktree", "⌘N")
                    shortcut("New terminal tab", "⇧⌘T")
                    shortcut("Command palette", "⇧⌘P")
                    shortcut("Go to worktree 1–9", "⌃1–9")
                    shortcut("Find in terminal", "⌘F")
                    shortcut("Run primary script", "⌘R")
                    shortcut("Stop primary script", "⌘.")
                    shortcut("Interrupt terminal command", "⌃C")
                    shortcut("Run first palette result", "Return")
                    shortcut("Close command palette", "Escape")
                    shortcut("Open Settings", "⌘,")
                    shortcut("Quit Grove", "⌘Q")
                }
                Divider()
                Text("Run and Stop target the first available Run-type script. Find and Interrupt need focus in a terminal pane. Worktree numbers follow sidebar ordering and exclude hidden archived worktrees.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Regular Quit keeps persistent terminal sessions alive. Use Workspace → Quit and End Grove Sessions to stop them.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.textSelection(.enabled)
    }
    private func shortcut(_ action: String, _ keys: String) -> some View {
        GridRow {
            Text(action)
            Text(keys).font(.system(.body, design: .monospaced)).gridColumnAlignment(.trailing)
        }
    }
}
