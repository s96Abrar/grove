import Foundation
import Darwin

enum PersistentTerminal {
    static let server = "grove"
    static var tmux: String? {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return directories.filter { $0.hasPrefix("/") }.map { $0 + "/tmux" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static var configuration: String {
        if let url = Bundle.main.url(forResource: "tmux", withExtension: "conf") { return url.path }
        // SwiftPM development runs do not have an app bundle.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/tmux.conf").path
    }
    static func environment(_ source: [String: String]) -> [String: String] {
        var result = source
        // A fresh PTY does not inherit the enclosing terminal's multiplexer context.
        // screen/tmux set their real context again inside their own new session.
        for key in ["STY", "TMUX", "TMUX_PANE", "TMUX_TMPDIR"] { result.removeValue(forKey: key) }
        result["TERM"] = "xterm-256color"
        return result
    }
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func wrapper(name: String, path: String, launch: [String]) -> String {
        let session = quote(name), target = quote("=" + name)
        // Retain live legacy shells. Never replace or replay a user's running work.
        let legacy = "if /usr/bin/screen -list " + session + " 2>/dev/null | /usr/bin/grep -Fq " + quote("." + name) + "; then exec /usr/bin/screen -U -D -r " + session + "; fi; "
        guard let tmux else { return legacy + "printf '\\r\\nGrove persistent terminals require tmux. Install it with: brew install tmux\\r\\n'; exit 127" }
        let client = quote(tmux) + " -L " + quote(server) + " -f " + quote(configuration)
        // Set per-session environment explicitly: the shared server may predate this pane.
        let context = ["GROVE_PANE_ID", "GROVE_WORKTREE_PATH", "GROVE_ROOT_PATH", "GROVE_BRANCH", "GROVE_TAB_ID", "GROVE_SCRIPT_ID"]
            .map { " -e " + quote($0) + "=\"${" + $0 + "-}\"" }.joined()
        let command = launch.map(quote).joined(separator: " ")
        return legacy + "if ! " + client + " has-session -t " + target + " 2>/dev/null; then " + client + " new-session -d -s " + session + " -c " + quote(path) + context + " -e COLORTERM=truecolor " + quote(command) + " || exit $?; fi; exec " + client + " attach-session -d -t " + target
    }
    static func end(name: String) throws {
        let legacy = try run("/usr/bin/screen", ["-list", name])
        if legacy.output.contains("." + name) {
            let stopped = try run("/usr/bin/screen", ["-S", name, "-X", "quit"])
            guard stopped.status == 0 else { throw WorkspaceStateError(message: stopped.output) }
        }
        if let tmux {
            let existing = try run(tmux, ["-L", server, "has-session", "-t", "=" + name])
            if existing.status == 0 {
                let stopped = try run(tmux, ["-L", server, "kill-session", "-t", "=" + name])
                guard stopped.status == 0 else { throw WorkspaceStateError(message: stopped.output) }
            } else if FileManager.default.fileExists(atPath: "/tmp/tmux-\(getuid())/" + server) {
                // A missing target is normal; server/protocol failures must not masquerade as absence.
                let listing = try run(tmux, ["-L", server, "list-sessions", "-F", "#{session_name}"])
                guard listing.status == 0 else { throw WorkspaceStateError(message: listing.output) }
            }
        } else if FileManager.default.fileExists(atPath: "/tmp/tmux-\(getuid())/" + server) {
            throw WorkspaceStateError(message: "tmux is unavailable; restore it before ending persistent sessions.")
        }
    }
    private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = environment(ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
