import SwiftUI
import AppKit

struct FileBrowser: View {
    let root: String
    @State private var directory: String?
    @State private var files: [URL] = []
    @State private var error: String?
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
                    else { NSWorkspace.shared.open(file) }
                } label: {
                    Label(file.lastPathComponent, systemImage: (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "folder" : "doc.text").font(.system(size: 11)).lineLimit(1)
                }.buttonStyle(.plain).contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding() }
        }.frame(minWidth: 180, idealWidth: 220, maxWidth: 300).task { load() }
    }
    func load() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory ?? root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            error = nil
        } catch { self.error = error.localizedDescription; files = [] }
    }
}
