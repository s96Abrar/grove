import AppKit
import SwiftUI
import SwiftTerm
import Darwin

@MainActor final class Session: ObservableObject, LocalProcessTerminalViewDelegate {
    let record: PaneRecord
    var id: UUID { record.id }
    @Published var title: String
    @Published var state = "Starting"
    @Published var muted = false
    var view: LocalProcessTerminalView?
    init(_ record: PaneRecord) { self.record = record; title = record.title }
    func terminal(path: String, fontSize: Double, persistent: Bool) -> LocalProcessTerminalView {
        if let view { view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular); return view }
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        if state == "Ended" { view = terminal; return terminal }
        terminal.processDelegate = self
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.06, alpha: 1)
        var env = ProcessInfo.processInfo.environment
        env.merge(record.environment) { _, new in new }
        env["TERM"] = "xterm-256color"
        env["GROVE_PANE_ID"] = id.uuidString
        env["GROVE_WORKTREE_PATH"] = path
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        let shell = "/bin/zsh"
        var args = ["-l"]
        if let command = record.command {
            // Isolate exit/set -e in the command; always leave an interactive shell.
            args = ["-l", "-c", ScriptLaunch.command(command)]
        }
        if persistent {
            let name = "grove-" + id.uuidString
            let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let launch = ([shell] + args).map(quote).joined(separator: " ")
            let wrapper = "if ! /usr/bin/screen -list " + name + " 2>/dev/null | /usr/bin/grep -Fq " + quote("." + name) + "; then /usr/bin/screen -U -dmS " + name + " -h 10000 " + launch + "; fi; exec /usr/bin/screen -U -D -r " + name
            terminal.startProcess(executable: "/bin/zsh", args: ["-c", wrapper], environment: env.map { "\($0)=\($1)" }, currentDirectory: path)
        } else {
            terminal.startProcess(executable: shell, args: args, environment: env.map { "\($0)=\($1)" }, currentDirectory: path)
        }
        view = terminal
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == "Starting" else { return }
            self.state = terminal.process.running ? "Shell" : "Exited"
        }
        return terminal
    }
    func interrupt() { guard let view else { return }; view.send(source: view, data: [3][...]) }
    func detach() { view?.terminate(); state = "Ended" }
    func end() {
        // Signal only the foreground group of our own PTY, including a script child.
        if let view, view.process.running {
            let group = tcgetpgrp(view.process.childfd)
            if group > 0 && group != getpgrp() { kill(-group, SIGTERM) }
        }
        detach()
    }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { self.title = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { state = "Exited \(exitCode.map(String.init) ?? "signal")" }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) { state = "Launch failed: \(error)" }
    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) { state = records.isEmpty ? "Shell" : "Program active" }
}

struct EmbeddedTerminal: NSViewRepresentable {
    @ObservedObject var session: Session
    let path: String
    let fontSize: Double
    let persistent: Bool
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.terminal(path: path, fontSize: fontSize, persistent: persistent) }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) { view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
}
