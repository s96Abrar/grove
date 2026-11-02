import Foundation

@main struct ScriptCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-script-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ScriptRecord(name: "Quoted test", command: "printf done > cwd-marker; printf '%s\\n' \"it's quoted\";\nprintf '%s\\n' \"$GROVE_WORKTREE_PATH\"; exit 7", root: "/other", icon: "hammer", tint: "blue")
        precondition(script.applies(to: "/other") && !script.applies(to: root.path))
        precondition(ScriptRecord(name: "Global", command: "true").applies(to: root.path))
        let file = root.appendingPathComponent("grove.json")
        try JSONEncoder().encode(ScriptConfiguration(scripts: [script])).write(to: file)
        let imported = try ScriptConfiguration.load(at: root.path)
        precondition(imported.count == 1 && imported[0].root == root.path, "File must not choose another repository's scope")
        precondition(imported[0].id == script.id && imported[0].command == script.command && imported[0].tint == "blue")
        try JSONEncoder().encode(ScriptConfiguration(scripts: [script, script])).write(to: file)
        do { _ = try ScriptConfiguration.load(at: root.path); fatalError("Duplicate identities accepted") } catch {}
        try JSONEncoder().encode(ScriptConfiguration(version: 99, scripts: [])).write(to: file)
        do { _ = try ScriptConfiguration.load(at: root.path); fatalError("Future schema accepted") } catch {}
        try Data(repeating: 32, count: 1_048_577).write(to: file)
        do { _ = try ScriptConfiguration.load(at: root.path); fatalError("Oversized file accepted") } catch {}
        try Data("{bad json".utf8).write(to: file)
        do { _ = try ScriptConfiguration.load(at: root.path); fatalError("Invalid JSON accepted") } catch {}
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
        do { _ = try ScriptConfiguration.load(at: root.path); fatalError("Special-file symlink accepted") } catch {}
        let presets = ScriptPreset.all
        precondition(Array(presets.prefix(6)).map(\.name) == ["Run", "Test", "Deploy", "Lint", "Format", "Custom"])
        precondition(presets.prefix(6).allSatisfy { $0.command.isEmpty }, "Categories must not invent an executable command")
        precondition(presets[0].script.id != presets[0].script.id, "Each new script needs its own identity")
        let project = try ScriptConfiguration.load(at: FileManager.default.currentDirectoryPath)
        precondition(project.count == 4 && project.contains { $0.command == "make build" })
        // Actual shell execution verifies command quoting, cwd, environment and nonzero exits.
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", ScriptLaunch.command(script.command)]
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GROVE_WORKTREE_PATH"] = root.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        precondition(output.contains("it's quoted\n") && output.contains(root.path), output)
        precondition(output.contains("[Grove script exited: 7]"), output)
        let marker = try String(contentsOf: root.appendingPathComponent("cwd-marker"), encoding: .utf8)
        precondition(marker == "done")
        // Old stored script definitions must gain harmless metadata defaults.
        let legacy = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Old\",\"command\":\"echo old\"}"
        let restored = try JSONDecoder().decode(ScriptRecord.self, from: Data(legacy.utf8))
        precondition(restored.icon == "play.fill" && restored.tint == "green" && restored.root == nil)
        var tab = TabRecord(panes: [PaneRecord(command: "never replay", environment: ["SECRET_TEST": "transient"])])
        tab.scriptID = script.id
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(TabRecord.self, from: data)
        precondition(decoded.scriptID == script.id && decoded.panes[0].command == nil && decoded.panes[0].environment.isEmpty)
        precondition(!String(decoding: data, as: UTF8.self).contains("SECRET_TEST"))
        print("PASS: script presets, repository config validation/scoping, legacy migration, no command/environment replay, actual shell quoting and exit status")
    }
}
