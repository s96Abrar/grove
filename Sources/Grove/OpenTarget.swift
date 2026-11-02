import Foundation

/// Targets are file URLs, never interpolated shell commands.
enum OpenTarget: String, CaseIterable, Identifiable {
    case vscode, xcode, terminal, finder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vscode: return "VS Code"
        case .xcode: return "Xcode"
        case .terminal: return "Terminal"
        case .finder: return "Finder"
        }
    }
    var bundleIdentifier: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .xcode: return "com.apple.dt.Xcode"
        case .terminal: return "com.apple.Terminal"
        case .finder: return "com.apple.finder"
        }
    }
    var symbol: String {
        switch self {
        case .vscode: return "chevron.left.forwardslash.chevron.right"
        case .xcode: return "hammer"
        case .terminal: return "terminal"
        case .finder: return "folder"
        }
    }
    func url(at path: String) throws -> URL {
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }
        guard self == .xcode else { return root }
        // Search only the selected worktree; exclude generated/dependency trees.
        let excluded: Set<String> = ["node_modules", "Pods", "Carthage", "DerivedData", "build", "dist", "vendor"]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return root }
        var candidates: [URL] = []
        for case let url as URL in entries {
            let depth = entries.level
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true || excluded.contains(url.lastPathComponent) || depth > 3 {
                entries.skipDescendants(); continue
            }
            if ["xcworkspace", "xcodeproj"].contains(url.pathExtension) && values.isDirectory == true {
                candidates.append(url); entries.skipDescendants()
            }
            if depth == 3 { entries.skipDescendants() }
        }
        let sorted = candidates.sorted {
            if $0.pathExtension != $1.pathExtension { return $0.pathExtension == "xcworkspace" }
            let lhs = $0.pathComponents.count, rhs = $1.pathComponents.count
            if lhs != rhs { return lhs < rhs }
            return $0.path < $1.path
        }
        if let first = sorted.first { return first }
        let package = root.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: package.path) { return package }
        return root
    }
}
