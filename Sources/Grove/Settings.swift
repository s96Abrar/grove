import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: Workspace
    @ObservedObject private var profile = PerformanceProfileManager.shared
    // Static: lazy and computed once. GroveApp.body re-creates this view on every workspace publish.
    private static let fonts = (NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    @State private var resetting = false
    var body: some View {
        TabView {
            Form {
                Picker("Appearance", selection: $model.appearance) { Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system") }
                Picker("Visual profile", selection: $profile.profile) {
                    ForEach(PerformanceProfile.allCases) { mode in Text(mode.label).tag(mode) }
                }
                Text("Auto adapts to sustained Low Power Mode and thermal pressure. Manual profiles apply immediately.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Terminal font", selection: $model.fontName) {
                    Text("System Monospaced").tag("")
                    if !model.fontName.isEmpty && !Self.fonts.contains(model.fontName) { Text("\(model.fontName) (unavailable)").tag(model.fontName) }
                    ForEach(Self.fonts, id: \.self) { name in Text(NSFont(name: name, size: 13)?.displayName ?? name).tag(name) }
                }
                Slider(value: $model.fontSize, in: 10...24, step: 1) { Text("Terminal font: \(Int(model.fontSize)) pt") }
                Toggle("Keep terminal sessions alive with tmux", isOn: $model.persistent)
                Text("New terminals use Grove’s own tmux server. Quit detaches; reopening restores sessions. Existing screen sessions stay attached until closed.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if PersistentTerminal.tmux == nil {
                    Text("Install tmux for persistent terminals: brew install tmux").font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                TextField("New worktree base ref", text: $model.baseRef)
                Toggle("Fetch before creating worktrees", isOn: $model.fetchBeforeCreate)
                if model.workspaceStorageBlocked { Text("Workspace metadata needs recovery.").foregroundStyle(.orange) }
                Button("Reset Workspace Metadata…", role: .destructive) { resetting = true }
                Toggle("Sort worktrees by attention", isOn: $model.triageSort)
                Toggle("Compact sidebar", isOn: $model.compactSidebar)
                Toggle("Enable GitHub CLI integration", isOn: $model.githubEnabled)
                Text("Uses your local gh authentication. No account, analytics, telemetry or license activation is required by Grove.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).tabItem { Label("General", systemImage: "gear") }
            ScriptSettingsView().tabItem { Label("Scripts", systemImage: "play") }
            ShortcutsHelpView().tabItem { Label("Help", systemImage: "questionmark.circle") }
        }.frame(minWidth: 660, idealWidth: 660, maxWidth: .infinity, minHeight: 640, idealHeight: 640, maxHeight: .infinity)
        .confirmationDialog("Reset saved repositories, scripts and terminal layouts?", isPresented: $resetting) {
            Button("Reset Workspace Metadata", role: .destructive) { model.resetWorkspaceMetadata() }
            if WorkspacePersistence.hasRecoveryCopy() {
                Button("Reset and Delete Recovery Copy", role: .destructive) { model.resetWorkspaceMetadata(deleteRecoveryCopy: true) }
            }
        } message: {
            Text(WorkspacePersistence.hasRecoveryCopy()
                 ? "Saved metadata and its backup are deleted. Your source files and Git worktrees are kept, and persistent sessions are detached. A recovery copy of earlier unreadable metadata also exists; delete it too if you no longer need it."
                 : "Saved metadata and its backup are deleted. Your source files and Git worktrees are kept, and persistent sessions are detached.")
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
    @State private var selection = 0
    @State private var keyMonitor: Any?
    @State private var paletteWindow = PaletteWindowReference()
    @FocusState private var queryFocused: Bool
    struct Action: Identifiable { var id: String { actionID ?? name }; var actionID: String? = nil; var shortcut: String? = nil; let name: String; let icon: String; let run: () -> Void }
    var actions: [Action] {
        var result = [
            Action(shortcut: "⇧⌘T", name: "New terminal tab", icon: "terminal", run: { model.addTab() }),
            Action(shortcut: "⌘N", name: "Create worktree…", icon: "arrow.triangle.branch", run: { model.showCreateSheet = true }),
            Action(shortcut: "⌘O", name: "Add folder or repository", icon: "folder.badge.plus", run: { model.open() }),
            Action(name: "Clone repository…", icon: "square.and.arrow.down", run: { cloning = true }),
            Action(shortcut: "⌘R", name: "Run primary script", icon: "play.fill", run: { if let script = model.primaryScript { model.runScript(script) } }),
            Action(name: "Refresh repositories", icon: "arrow.clockwise", run: { Task { await model.reload() } }),
            Action(name: "Refresh GitHub pull request", icon: "arrow.triangle.pull", run: { Task { await model.refreshPR() } }),
            Action(shortcut: "⌘⇧A", name: "Next worktree needing attention", icon: "exclamationmark.triangle", run: { model.jumpToNextAttention() }),
            Action(shortcut: "⌃⌘C", name: "Copy worktree path", icon: "doc.on.doc", run: { model.copyWorktreePath() }),
            Action(shortcut: "⇧⌘B", name: "Copy branch name", icon: "doc.on.doc", run: { model.copyBranchName() }),
            Action(shortcut: "⌘D", name: "Split terminal left / right", icon: "rectangle.split.2x1", run: { if let path = model.selected?.path, let active = model.activeTab(at: path) { model.split(tab: active.id, vertical: true) } }),
            Action(shortcut: "⇧⌘D", name: "Split terminal top / bottom", icon: "rectangle.split.2x2", run: { if let path = model.selected?.path, let active = model.activeTab(at: path) { model.split(tab: active.id, vertical: false) } }),
            Action(shortcut: "⌘W", name: "Close pane or tab", icon: "xmark", run: { model.closeFocused() })
        ]
        for root in model.roots {
            for tree in model.trees[root] ?? [] { result.append(Action(actionID: "worktree:" + tree.path, name: "Go to \(URL(fileURLWithPath: root).lastPathComponent) / \(tree.branch)", icon: "arrow.triangle.branch", run: { model.select(tree) })) }
        }
        for script in model.availableScripts { result.append(Action(actionID: script.id.uuidString, name: "Run script: \(script.name)", icon: script.icon, run: { model.runScript(script) })) }
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
            TextField("Where do you want to go?", text: $query)
                .accessibilityLabel("Search commands")
                .font(.title3).textFieldStyle(.plain)
                .focused($queryFocused)
                .background(PaletteWindowReader(reference: paletteWindow).allowsHitTesting(false))
                .onSubmit { executeSelection() }
                .onChange(of: query) { _, _ in selection = 0 }
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        Button { execute(action) } label: {
                            HStack {
                                Label(action.name, systemImage: action.icon)
                                Spacer()
                                if let shortcut = action.shortcut {
                                    Text(shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                if index == selection { Image(systemName: "return") }
                            }.padding(10).contentShape(Rectangle())
                            .background(index == selection ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if creating {
                TextField("New branch name", text: $branch).accessibilityLabel("New branch name")
                if let problem = Git.branchNameProblem(branch) { Text(problem).font(.caption).foregroundStyle(.red) }
                Button("Create worktree") { Task { await model.create(branch) }; model.palette = false }.disabled(branch.isEmpty || Git.branchNameProblem(branch) != nil || model.busy)
            }
            if cloning {
                TextField("HTTPS or SSH Git URL", text: $cloneURL).accessibilityLabel("Git repository URL")
                if let problem = Workspace.cloneURLProblem(cloneURL) { Text(problem).font(.caption).foregroundStyle(.red) }
                Button("Choose destination and clone…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let parent = panel.url { Task { await model.clone(cloneURL, to: parent) }; model.palette = false }
                }.disabled(cloneURL.isEmpty || Workspace.cloneURLProblem(cloneURL) != nil || model.cloneInProgress != nil)
            }
            if !model.pullRequest.isEmpty { ScrollView { Text(model.pullRequest).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }.frame(height: 100) }
            HStack { Text("GROVE COMMANDS").font(.caption2).foregroundStyle(.secondary); Spacer(); Text("↑↓ navigate · Return run · Esc back/clear/close").font(.caption2).foregroundStyle(.secondary) }
        }.padding(20).frame(width: 560, height: 420)
        .onAppear {
            queryFocused = true
            // Arrow-key navigation: the query field is first responder, so
            // .onMoveCommand on containers never fires — intercept locally.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard model.palette, let window = paletteWindow.window, event.window === window,
                      window.isKeyWindow,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                // Let the input method handle candidate navigation/cancellation.
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                if event.keyCode == 53 {
                    if creating || cloning { creating = false; cloning = false; queryFocused = true }
                    else if !query.isEmpty { query = ""; selection = 0; queryFocused = true }
                    else { model.palette = false }
                    return nil
                }
                guard !creating && !cloning, queryFocused,
                      let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return event }
                switch event.keyCode {
                case 125: selection = min(selection + 1, max(actions.count - 1, 0)); return nil
                case 126: selection = max(selection - 1, 0); return nil
                default: return event
                }
            }
        }
        .onDisappear { if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }; keyMonitor = nil; paletteWindow.window = nil }
    }
    func execute(_ action: Action) {
        action.run()
        if !creating && !cloning { model.palette = false; model.restoreFocus() }
    }
    func executeSelection() {
        if actions.indices.contains(selection) { execute(actions[selection]) }
        else if let first = actions.first { execute(first) }
    }
}


/// Read the query field's actual hosting window; never infer it from the app's
/// key window, which may change while a palette remains open in another window.
private final class PaletteWindowReference {
    weak var window: NSWindow?
}

private struct PaletteWindowReader: NSViewRepresentable {
    let reference: PaletteWindowReference
    func makeNSView(context: Context) -> WindowView { WindowView(reference: reference) }
    func updateNSView(_ view: WindowView, context: Context) { view.reference = reference }
    final class WindowView: NSView {
        var reference: PaletteWindowReference
        init(reference: PaletteWindowReference) {
            self.reference = reference
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Only a weak reference is changed; no SwiftUI state is published
            // during AppKit view updates and the monitor cannot retain a window.
            reference.window = window
        }
    }
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
                    shortcut("Command palette", "⌘K or ⇧⌘P")
                    shortcut("Go to worktree 1–9", "⌃1–9")
                    shortcut("Find in terminal", "⌘F")
                    shortcut("Close pane / tab", "⌘W")
                    shortcut("Split left / right", "⌘D")
                    shortcut("Split top / bottom", "⇧⌘D")
                    shortcut("Next / previous tab", "⇧⌘] / ⇧⌘[")
                    shortcut("Next worktree needing attention", "⌘⇧A")
                    shortcut("Copy worktree path", "⌃⌘C")
                    shortcut("Copy branch name", "⇧⌘B")
                    shortcut("Archive worktree", "⇧⌘⌫")
                    shortcut("Remove worktree…", "⌘⌫")
                    shortcut("Confirm destructive dialog", "⌘Return")
                    shortcut("Run primary script", "⌘R")
                    shortcut("Stop primary script", "⌘.")
                    shortcut("Interrupt terminal command", "⌃C")
                    shortcut("Navigate command palette", "↑↓ · Return")
                    shortcut("Back / clear / close palette", "Escape")
                    shortcut("Open Settings", "⌘,")
                    shortcut("Quit Grove", "⌘Q")
                }
                Divider()
                Text("Run and Stop target the first available Run-type script. Find falls back to the selected worktree's terminal when no pane holds focus. Worktree numbers follow sidebar ordering and exclude hidden archived worktrees.")
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
