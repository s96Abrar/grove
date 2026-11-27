import SwiftUI
import AppKit

struct FileBrowser: View {
    let root: String
    @State private var directory: String?
    @State private var files: [URL] = []
    @State private var error: String?
    /// File awaiting confirmation because opening it can run code.
    @State private var confirming: URL?
    /// Git status of changed files and the folders that contain them, by
    /// absolute path; empty outside a repository.
    @State private var status = StatusIndex()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { directory = URL(fileURLWithPath: directory ?? root).deletingLastPathComponent().path; load() } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Parent folder").disabled((directory ?? root) == root)
                Text(URL(fileURLWithPath: directory ?? root).lastPathComponent).font(.caption).lineLimit(1)
                Spacer()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reload files")
            }.buttonStyle(.plain).padding(12)
            List(files, id: \.path) { file in
                Button {
                    if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { directory = file.path; load() }
                    else { open(file) }
                } label: {
                    HStack(spacing: 4) {
                        Label(file.lastPathComponent, systemImage: (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "folder" : "doc.text").font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let marker = marker(for: file) {
                            Text(marker.symbol).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(marker.color)
                                .help(marker.description).accessibilityLabel(marker.description)
                        }
                    }
                }.buttonStyle(.plain).contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
            }
            if let error { Text(ErrorExplainer.explain(error)).font(.caption).foregroundStyle(.red).padding().textSelection(.enabled) }
            else if files.isEmpty { Text("No visible files in this folder.").font(.caption).foregroundStyle(.secondary).padding() }
        }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300).task { load() }
        .confirmationDialog("Open “\(confirming?.lastPathComponent ?? "")”?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Open") { if let file = confirming { NSWorkspace.shared.open(file) }; confirming = nil }
            Button("Reveal in Finder") { if let file = confirming { NSWorkspace.shared.activateFileViewerSelecting([file]) }; confirming = nil }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("This file can run code on your Mac. Files checked out with Git are not checked by Gatekeeper. Only open it if you trust this repository.")
        }
    }
    /// Ordinary documents open directly; anything that can run code asks first.
    private func open(_ file: URL) {
        if Self.mayRunCode(file) { confirming = file } else { NSWorkspace.shared.open(file) }
    }
    /// Launchers, scripts, installers and executables. Git checkouts carry no
    /// quarantine attribute, so macOS would open these without a warning.
    static let codeExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "bash", "zsh", "fish", "csh", "ksh",
        "py", "rb", "pl", "scpt", "scptd", "applescript", "workflow", "action",
        "shortcut", "pkg", "mpkg", "dmg", "jar", "webloc", "inetloc", "fileloc", "url",
        "prefpane", "saver", "plugin", "bundle", "kext", "osax", "qlgenerator", "mdimporter"
    ]
    static func mayRunCode(_ file: URL) -> Bool {
        if codeExtensions.contains(file.pathExtension.lowercased()) { return true }
        if (try? file.resourceValues(forKeys: [.isPackageKey]).isPackage) == true { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: file.path)
    }
    struct Marker: Equatable { let symbol: String; let description: String; let color: Color }
    struct StatusIndex: Equatable {
        var files: [String: String] = [:]
        var folders: Set<String> = []
        /// `paths` are relative to `top`, the repository's top-level folder.
        init(top: String = "", paths: [String: String] = [:]) {
            for (relative, code) in paths {
                files[top + "/" + relative] = code
                var folder = URL(fileURLWithPath: top + "/" + relative).deletingLastPathComponent().path
                while folder.count > top.count, folders.insert(folder).inserted {
                    folder = URL(fileURLWithPath: folder).deletingLastPathComponent().path
                }
            }
        }
        /// Both spellings of the listed folder, e.g. /var/… and /private/var/….
        func lookup(_ file: URL, root: String) -> (code: String?, folder: Bool) {
            let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            var candidates = [file.path]
            if file.path.hasPrefix(root + "/") { candidates.append(resolvedRoot + file.path.dropFirst(root.count)) }
            if file.path.hasPrefix(resolvedRoot + "/") { candidates.append(root + file.path.dropFirst(resolvedRoot.count)) }
            if let code = candidates.lazy.compactMap({ files[$0] }).first { return (code, false) }
            return (nil, candidates.contains { folders.contains($0) })
        }
    }
    /// Porcelain v1 `-z` output to relative path → two-letter status code.
    /// Renames and copies carry the original path as an extra field.
    nonisolated static func parseStatus(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        var fields = output.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
        while let field = fields.next() {
            guard field.count > 3 else { continue }
            let code = String(field.prefix(2)), path = String(field.dropFirst(3))
            result[path] = code
            if code.contains("R") || code.contains("C") { _ = fields.next() }
        }
        return result
    }
    nonisolated static func marker(code: String) -> Marker {
        let conflicts: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        if conflicts.contains(code) { return Marker(symbol: "!", description: "Merge conflict", color: .red) }
        if code == "??" { return Marker(symbol: "U", description: "Untracked", color: .green) }
        if code.contains("R") { return Marker(symbol: "R", description: "Renamed", color: .blue) }
        if code.contains("A") || code.contains("C") { return Marker(symbol: "A", description: "Added", color: .green) }
        if code.contains("D") { return Marker(symbol: "D", description: "Deleted", color: .red) }
        return Marker(symbol: "M", description: "Modified", color: .orange)
    }
    /// A file shows its own status; a folder shows a dot when anything inside it changed.
    func marker(for file: URL) -> Marker? {
        guard !status.files.isEmpty else { return nil }
        let found = status.lookup(file, root: root)
        if let code = found.code { return Self.marker(code: code) }
        return found.folder ? Marker(symbol: "•", description: "Contains changes", color: .orange) : nil
    }
    func load() {
        let root = root
        Task {
            let index = await Task.detached { () -> StatusIndex in
                guard let top = try? Git.run(["rev-parse", "--show-toplevel"], at: root).trimmingCharacters(in: .whitespacesAndNewlines),
                      let output = try? Git.run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: root) else { return StatusIndex() }
                return StatusIndex(top: top, paths: FileBrowser.parseStatus(output))
            }.value
            if index != status { status = index }
        }
        do {
            files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory ?? root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            error = nil
        } catch { self.error = error.localizedDescription; files = [] }
    }
}
