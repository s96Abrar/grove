import Foundation

@main struct OpenTargetCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("grove open 'quoted' " + UUID().uuidString).standardizedFileURL
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for target in [OpenTarget.vscode, .terminal, .finder] {
            precondition(tryURL(target, root) == root.standardizedFileURL)
        }
        try Data("// fixture".utf8).write(to: root.appendingPathComponent("Package.swift"))
        precondition(tryURL(.xcode, root).lastPathComponent == "Package.swift")
        let project = root.appendingPathComponent("App.xcodeproj")
        try manager.createDirectory(at: project.appendingPathComponent("project.xcworkspace"), withIntermediateDirectories: true)
        precondition(tryURL(.xcode, root).resolvingSymlinksInPath().path == project.resolvingSymlinksInPath().path, "Selected \(tryURL(.xcode, root).path), expected \(project.path)")
        try manager.createDirectory(at: root.appendingPathComponent("node_modules/Ignored.xcworkspace"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent(".build/Ignored.xcworkspace"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("one/two/three/TooDeep.xcworkspace"), withIntermediateDirectories: true)
        precondition(tryURL(.xcode, root).resolvingSymlinksInPath().path == project.resolvingSymlinksInPath().path)
        let workspace = root.appendingPathComponent("Sources/App.xcworkspace")
        try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        precondition(tryURL(.xcode, root).resolvingSymlinksInPath().path == workspace.resolvingSymlinksInPath().path, "Workspace should take precedence over project")
        let external = root.deletingLastPathComponent().appendingPathComponent("outside-" + UUID().uuidString + ".xcworkspace")
        try manager.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: external) }
        try manager.createSymbolicLink(at: root.appendingPathComponent("Link.xcworkspace"), withDestinationURL: external)
        precondition(tryURL(.xcode, root).resolvingSymlinksInPath().path == workspace.resolvingSymlinksInPath().path)
        do { _ = try OpenTarget.terminal.url(at: root.appendingPathComponent("missing").path); fatalError("Missing worktree accepted") } catch {}
        print("PASS: open targets preserve literal paths; Xcode workspace/project/package priority, depth/exclusion/symlink boundaries, missing-path rejection")
    }
    static func tryURL(_ target: OpenTarget, _ root: URL) -> URL {
        do { return try target.url(at: root.path) } catch { fatalError(error.localizedDescription) }
    }
}
