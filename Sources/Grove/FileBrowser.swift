import SwiftUI
import AppKit

struct FileBrowser: View {
    let root: String
    @State private var directory: String?
    @State private var files: [URL] = []
    @State private var error: String?
    /// File awaiting confirmation because opening it can run code.
    @State private var confirming: URL?
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
                    Label(file.lastPathComponent, systemImage: (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "folder" : "doc.text").font(.system(size: 11)).lineLimit(1)
                }.buttonStyle(.plain).contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding() }
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
    func load() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory ?? root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            error = nil
        } catch { self.error = error.localizedDescription; files = [] }
    }
}
