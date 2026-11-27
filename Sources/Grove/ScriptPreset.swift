import Foundation

/// Grove-owned starting points. No command is installed or executed by choosing one.
struct ScriptPreset {
    let name: String
    let command: String
    let icon: String
    let tint: String
    var script: ScriptRecord { ScriptRecord(name: name, command: command, icon: icon, tint: tint, kind: Self.kinds.contains(name.lowercased()) ? name.lowercased() : "custom") }
    static let kinds = ["run", "setup", "test", "deploy", "lint", "format", "custom"]
    static let all: [ScriptPreset] = [
        .init(name: "Run", command: "", icon: "play.fill", tint: "green"),
        .init(name: "Setup", command: "", icon: "hammer", tint: "orange"),
        .init(name: "Test", command: "", icon: "checkmark.circle", tint: "blue"),
        .init(name: "Deploy", command: "", icon: "paperplane", tint: "purple"),
        .init(name: "Lint", command: "", icon: "checkmark.shield", tint: "orange"),
        .init(name: "Format", command: "", icon: "text.alignleft", tint: "blue"),
        .init(name: "Custom", command: "", icon: "terminal", tint: "gray"),
        .init(name: "Example: Swift build", command: "swift build", icon: "hammer", tint: "orange"),
        .init(name: "Example: Swift tests", command: "swift test", icon: "checkmark.circle", tint: "blue"),
        .init(name: "Example: npm development server", command: "npm run dev", icon: "bolt", tint: "green"),
        .init(name: "Example: npm tests", command: "npm test", icon: "checkmark.circle", tint: "blue"),
        .init(name: "Example: Grove checks", command: "bash scripts/check.sh", icon: "checkmark.shield", tint: "orange")
    ]
}

/// A repository file is imported by explicit review; merely opening a repo never runs it.
struct ScriptConfiguration: Codable {
    var version: Int = 1
    var scripts: [ScriptRecord]
    static func load(at root: String) throws -> [ScriptRecord] {
        let url = URL(fileURLWithPath: root).appendingPathComponent("grove.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw WorkspaceStateError(message: "grove.json must be a regular file, not a symlink or special file.")
        }
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_048_576 else {
            throw WorkspaceStateError(message: "grove.json must be smaller than 1 MB.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw WorkspaceStateError(message: "grove.json must be smaller than 1 MB.") }
        let configuration = try JSONDecoder().decode(Self.self, from: data)
        guard configuration.version == 1, configuration.scripts.count <= 64 else {
            throw WorkspaceStateError(message: "Unsupported grove.json version or more than 64 scripts.")
        }
        guard Set(configuration.scripts.map(\.id)).count == configuration.scripts.count,
              configuration.scripts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.command.contains("\0") }) else {
            throw WorkspaceStateError(message: "grove.json contains duplicate identities or invalid scripts.")
        }
        return configuration.scripts.map { source in
            var script = source
            script.root = root
            return script
        }
    }
}

/// Shell-quote the complete user command, so quotes/newlines and `exit` stay inside it.
enum ScriptLaunch {
    static func command(_ command: String) -> String {
        let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/bin/zsh -l -c " + quoted + "; grove_status=$?; printf '\\n[Grove script exited: %s]\\n' \"$grove_status\"; exec /bin/zsh -l"
    }
}
