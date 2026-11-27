import Foundation

struct PaneRecord: Codable, Identifiable {
    var id = UUID()
    var title = "Shell"
    var command: String? = nil
    var environment: [String: String] = [:]
    // Startup commands are a one-time user action, never an automatic restore action.
    enum CodingKeys: String, CodingKey { case id, title }
}
struct TabRecord: Codable, Identifiable {
    var id = UUID()
    var name = "Terminal"
    var vertical = true
    var panes = [PaneRecord()]
    var layout: SplitNode? = nil
    var scriptID: UUID? = nil
    func removingPane(_ id: UUID) -> TabRecord? {
        guard panes.count > 1, panes.contains(where: { $0.id == id }) else { return nil }
        var result = self
        result.panes.removeAll { $0.id == id }
        result.layout = layout?.removing(id)
        return result
    }
}
indirect enum SplitNode: Codable {
    case pane(UUID)
    case split(vertical: Bool, first: SplitNode, second: SplitNode)
    func removing(_ target: UUID) -> SplitNode? {
        switch self {
        case .pane(let id): return id == target ? nil : self
        case .split(let vertical, let first, let second):
            let left = first.removing(target), right = second.removing(target)
            if let left, let right { return .split(vertical: vertical, first: left, second: right) }
            return left ?? right
        }
    }
    func inserting(_ newID: UUID, after target: UUID, vertical: Bool) -> SplitNode {
        switch self {
        case .pane(let id): return id == target ? .split(vertical: vertical, first: self, second: .pane(newID)) : self
        case .split(let axis, let first, let second): return .split(vertical: axis, first: first.inserting(newID, after: target, vertical: vertical), second: second.inserting(newID, after: target, vertical: vertical))
        }
    }
}

struct ScriptRecord: Codable, Identifiable {
    var id = UUID()
    var name: String
    var command: String
    var root: String? = nil
    var icon = "play.fill"
    var tint = "green"
    var kind = "custom"
    enum CodingKeys: String, CodingKey { case id, name, command, root, icon, tint, kind }
    init(id: UUID = UUID(), name: String, command: String, root: String? = nil, icon: String = "play.fill", tint: String = "green", kind: String = "custom") {
        self.id = id; self.name = name; self.command = command; self.root = root; self.icon = icon; self.tint = tint; self.kind = kind
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        command = try values.decode(String.self, forKey: .command)
        root = try values.decodeIfPresent(String.self, forKey: .root)
        icon = try values.decodeIfPresent(String.self, forKey: .icon) ?? "play.fill"
        tint = try values.decodeIfPresent(String.self, forKey: .tint) ?? "green"
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "custom"
    }
    func applies(to root: String?) -> Bool { self.root == nil || self.root == root }
}

struct SavedWorkspace: Codable {
    var schemaVersion: Int? = 1
    var activeTabs: [String: UUID]? = nil
    var roots: [String] = []
    var collapsedRoots: Set<String>? = nil
    var tabs: [String: [TabRecord]] = [:]
    var pinned: Set<String> = []
    var archived: Set<String> = []
    var selected: String? = nil
    var scripts: [ScriptRecord] = []
    /// Worktree paths whose "waiting for input" notifications are muted.
    var mutedAlerts: Set<String>? = nil
}


struct WorkspaceStateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension SavedWorkspace {
    func validate() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw WorkspaceStateError(message: message) }
        }
        func absolute(_ path: String) -> Bool { path.hasPrefix("/") && !path.contains("\0") }
        try check(schemaVersion == nil || schemaVersion == 1, "This workspace was saved by a newer Grove version.")
        try check(roots.allSatisfy(absolute) && tabs.keys.allSatisfy(absolute), "Workspace paths must be absolute directories.")
        try check(Set(roots).count == roots.count, "Duplicate workspace roots.")
        var tabIDs = Set<UUID>(), paneIDs = Set<UUID>()
        for records in tabs.values {
            try check(records.count <= 64, "Too many tabs in a workspace.")
            for tab in records {
                try check(tabIDs.insert(tab.id).inserted, "Duplicate tab identity.")
                try check(!tab.panes.isEmpty && tab.panes.count <= 64, "A tab must contain between 1 and 64 panes.")
                for pane in tab.panes { try check(paneIDs.insert(pane.id).inserted, "Duplicate terminal identity.") }
                if let layout = tab.layout {
                    var leaves = [UUID]()
                    func inspect(_ node: SplitNode, depth: Int) throws {
                        try check(depth <= 32, "Terminal layout is too deeply nested.")
                        switch node {
                        case .pane(let id): leaves.append(id)
                        case .split(_, let first, let second): try inspect(first, depth: depth + 1); try inspect(second, depth: depth + 1)
                        }
                    }
                    try inspect(layout, depth: 0)
                    try check(leaves.count == tab.panes.count && Set(leaves) == Set(tab.panes.map(\.id)), "Terminal layout does not match its panes.")
                }
            }
        }
        try check(Set(scripts.map(\.id)).count == scripts.count, "Duplicate script identity.")
    }
}

enum WorkspacePersistence {
    static let currentKey = "workspace.v2"
    static let backupKey = "workspace.v2.backup"
    static let unreadableKey = "workspace.v2.unreadable"
    static func decode(_ data: Data) throws -> SavedWorkspace {
        let state = try JSONDecoder().decode(SavedWorkspace.self, from: data)
        try state.validate()
        return state
    }
    static func load(from defaults: UserDefaults = .standard) throws -> (state: SavedWorkspace, recoveredBackup: Bool)? {
        guard let data = defaults.data(forKey: currentKey) else { return nil }
        do { return (try decode(data), false) }
        catch {
            defaults.set(data, forKey: unreadableKey)
            if let backup = defaults.data(forKey: backupKey), let state = try? decode(backup) { return (state, true) }
            throw error
        }
    }
    static func save(_ state: SavedWorkspace, to defaults: UserDefaults = .standard) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        if let previous = defaults.data(forKey: currentKey), (try? decode(previous)) != nil { defaults.set(previous, forKey: backupKey) }
        defaults.set(data, forKey: currentKey)
    }
    /// A copy of metadata that could not be read, kept by `load` for recovery.
    static func hasRecoveryCopy(in defaults: UserDefaults = .standard) -> Bool { defaults.data(forKey: unreadableKey) != nil }
    /// A user-chosen reset deletes the workspace and its backup. It no longer
    /// copies readable metadata into the recovery key: someone resetting to
    /// remove saved paths or script commands expects them gone. A recovery copy
    /// of corrupt data saved earlier by `load` stays unless explicitly deleted.
    static func reset(in defaults: UserDefaults = .standard, deleteRecoveryCopy: Bool = false) {
        defaults.removeObject(forKey: currentKey)
        defaults.removeObject(forKey: backupKey)
        if deleteRecoveryCopy { defaults.removeObject(forKey: unreadableKey) }
    }
}
