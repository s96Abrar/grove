import SwiftUI

extension ScriptRecord {
    static let icons = ["play.fill", "terminal", "hammer", "checkmark.circle", "bolt", "ladybug", "folder", "arrow.triangle.branch", "paperplane", "checkmark.shield", "text.alignleft"]
    static let tints = ["green", "blue", "orange", "purple", "red", "gray"]
    var color: Color {
        switch tint {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "gray": return .gray
        default: return .green
        }
    }
}

@MainActor extension Workspace {
    var availableScripts: [ScriptRecord] {
        let root = selected.flatMap { self.root(for: $0) }
        return saved.scripts.filter { $0.root != nil && $0.applies(to: root) } + saved.scripts.filter { $0.root == nil }
    }
    var primaryScript: ScriptRecord? { availableScripts.first { $0.kind == "run" } }
    func runScript(_ script: ScriptRecord) {
        guard selected != nil, availableScripts.contains(where: { $0.id == script.id }) else { error = "Select a workspace that can run this script."; return }
        guard !script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a command in Settings → Scripts first."; return }
        if let path = selected?.path, let tab = saved.tabs[path]?.first(where: { $0.scriptID == script.id }) {
            saved.activeTabs = saved.activeTabs ?? [:]; saved.activeTabs?[path] = tab.id; save()
        } else { addTab(command: script.command, name: script.name, scriptID: script.id) }
    }
    func stopScript(_ tab: TabRecord) async {
        guard tab.scriptID != nil else { return }
        do { for pane in tab.panes { try await endSession(pane.id) } }
        catch { self.error = "Could not stop this script: \(error.localizedDescription)" }
    }
    func restartScript(_ tab: TabRecord) async {
        guard let path = selected?.path, !isRemoving(path), let id = tab.scriptID,
              let script = availableScripts.first(where: { $0.id == id }),
              !script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "This script was removed or is unavailable. Add it in Settings → Scripts."; return
        }
        do { for pane in tab.panes { try await endSession(pane.id) } }
        catch { self.error = "Could not restart this script: \(error.localizedDescription)"; return }
        guard selected?.path == path, !isRemoving(path), let index = saved.tabs[path]?.firstIndex(where: { $0.id == tab.id }) else { return }
        for pane in tab.panes { sessions.removeValue(forKey: pane.id) }
        var replacement = TabRecord(name: script.name, panes: [PaneRecord(title: script.name, command: script.command)])
        replacement.scriptID = script.id
        replacement.panes[0].environment = scriptEnvironment(scriptID: script.id, tabID: replacement.id)
        saved.tabs[path]![index] = replacement
        saved.activeTabs = saved.activeTabs ?? [:]; saved.activeTabs?[path] = replacement.id; save()
    }
    func scriptEnvironment(scriptID: UUID?, tabID: UUID) -> [String: String] {
        var environment = ["GROVE_TAB_ID": tabID.uuidString]
        if let tree = selected {
            environment["GROVE_ROOT_PATH"] = root(for: tree) ?? tree.path
            environment["GROVE_BRANCH"] = tree.branch
        }
        if let scriptID { environment["GROVE_SCRIPT_ID"] = scriptID.uuidString }
        return environment
    }

}

struct ScriptSettingsView: View {
    @EnvironmentObject var model: Workspace
    @State private var editing: UUID?
    @State private var draft = ScriptRecord(name: "", command: "")
    @State private var repositoryOnly = false
    @State private var removing: ScriptRecord?
    @State private var importPreview: [ScriptRecord] = []
    @State private var importRoot: String?
    @State private var importError: String?
    private var selectedRoot: String? { model.selected.flatMap { model.root(for: $0) } }
    private var valid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!repositoryOnly || draft.root != nil || selectedRoot != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scripts").font(.title2)
                Spacer()
                Menu("Add preset") {
                    ForEach(ScriptPreset.all, id: \.name) { preset in
                        Button(preset.name) { editing = nil; draft = preset.script; repositoryOnly = false }
                    }
                }
                Button("Import grove.json…") {
                    guard let root = selectedRoot else { return }
                    do { importPreview = try ScriptConfiguration.load(at: root); importRoot = root }
                    catch { importError = error.localizedDescription }
                }.disabled(selectedRoot == nil)
                Button("New") { clear() }
            }
            List {
                ForEach(Array(model.saved.scripts.enumerated()), id: \.element.id) { index, script in
                    HStack {
                        Button { editing = script.id; draft = script; repositoryOnly = script.root != nil } label: {
                            HStack {
                                Image(systemName: script.icon).foregroundStyle(script.color)
                                VStack(alignment: .leading) {
                                    Text(script.name)
                                    Text(script.root ?? "All repositories and folders").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { model.runScript(script) } label: { Image(systemName: "play.fill") }.help("Run in selected worktree").disabled(!model.availableScripts.contains { $0.id == script.id } || model.selected == nil)
                        Button { model.saved.scripts.swapAt(index, index - 1); model.save() } label: { Image(systemName: "arrow.up") }.help("Move earlier").disabled(index == 0)
                        Button { removing = script } label: { Image(systemName: "trash") }.help("Remove script")
                    }
                }
            }.frame(minHeight: 100)
            TextField("Script name", text: $draft.name)
            Text("Shell command").font(.caption)
            TextEditor(text: $draft.command).font(.system(size: 12, design: .monospaced)).frame(height: 66).border(.secondary.opacity(0.3))
            Picker("Type", selection: $draft.kind) {
                ForEach(ScriptPreset.kinds, id: \.self) { Text($0.capitalized).tag($0) }
            }
            HStack {
                Picker("Icon", selection: $draft.icon) { ForEach(ScriptRecord.icons, id: \.self) { Label($0, systemImage: $0).tag($0) } }
                Picker("Color", selection: $draft.tint) { ForEach(ScriptRecord.tints, id: \.self) { Text($0.capitalized).tag($0) } }
            }
            Toggle("Only for this repository or folder", isOn: $repositoryOnly)
            if repositoryOnly { Text(draft.root ?? selectedRoot ?? "Select a repository or folder first").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                Button(editing == nil ? "Add script" : "Save changes") { store() }.disabled(!valid)
                if editing != nil { Button("Cancel editing") { clear() } }
            }
            Text("Presets fill the editor; review and save to add them. Commands run only when chosen, in the selected worktree. Tools must already be installed.").font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        .alert("Could not import scripts", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .sheet(isPresented: Binding(get: { importRoot != nil }, set: { if !$0 { importRoot = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import repository scripts?").font(.title2)
                Text(importRoot ?? "").font(.caption)
                Text("Review every command. Import replaces this repository's saved scripts; commands run only when chosen.")
                ScrollView {
                    ForEach(importPreview) { script in
                        VStack(alignment: .leading) { Text(script.name).bold(); Text(script.command.isEmpty ? "(command not configured)" : script.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.padding(.bottom, 8)
                    }
                }
                HStack {
                    Button("Cancel") { importRoot = nil }.keyboardShortcut(.cancelAction)
                    Button("Import scripts") {
                        guard let root = importRoot else { return }
                        let otherIDs = Set(model.saved.scripts.filter { $0.root != root }.map(\.id))
                        let imported = importPreview.map { source in
                            var script = source
                            if otherIDs.contains(script.id) { script.id = UUID() }
                            return script
                        }
                        model.saved.scripts.removeAll { $0.root == root }
                        model.saved.scripts.append(contentsOf: imported); model.save(); importRoot = nil; clear()
                    }
                }
            }.padding(20).frame(width: 520, height: 380)
        }
        .confirmationDialog("Remove \(removing?.name ?? "script")? Running terminals are kept.", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove script", role: .destructive) {
                guard let id = removing?.id else { return }
                model.saved.scripts.removeAll { $0.id == id }; model.save()
                if editing == id { clear() }; removing = nil
            }
        }
    }
    private func clear() { editing = nil; draft = ScriptRecord(name: "", command: ""); repositoryOnly = false }
    private func store() {
        guard valid else { return }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.root = repositoryOnly ? (draft.root ?? selectedRoot) : nil
        if let editing, let index = model.saved.scripts.firstIndex(where: { $0.id == editing }) { model.saved.scripts[index] = draft }
        else { model.saved.scripts.append(draft) }
        model.save(); clear()
    }
}
