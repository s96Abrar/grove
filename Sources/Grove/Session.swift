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
    /// The visible screen shows a prompt waiting for the user. Updated by the
    /// status poll (`sampleAwaitingInput`), not on every output byte.
    @Published private(set) var awaitingInput = false
    var view: LocalProcessTerminalView?
    /// Last terminal background color applied to this session's view; guards
    /// against redundant `nativeBackgroundColor` assignments from frequent
    /// `updateNSView` passes (each assignment forces cached-state refresh).
    var appliedBackground: NSColor?
    /// Last terminal font applied to this session's view; guards against
    /// redundant `view.font` assignments, each of which forces SwiftTerm to
    /// rebuild its FontSet, recompute cell metrics, clear selections and
    /// re-render the whole terminal on the main thread.
    var appliedFont: NSFont?
    init(_ record: PaneRecord) { self.record = record; title = record.title }
    func terminal(path: String, font: NSFont, persistent: Bool, background: NSColor, steadyCursor: Bool = false) -> LocalProcessTerminalView {
        if let view {
            if appliedFont != font { appliedFont = font; view.font = font }
            return view
        }
        let terminal = GroveTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        terminal.steadyCursor = steadyCursor
        if state == "Ended" {
            view = terminal
            // Ended panes still render; apply the requested font now so the
            // updateNSView guard does not skip it via a stale appliedFont.
            terminal.font = font
            appliedFont = font
            return terminal
        }
        terminal.processDelegate = self
        terminal.font = font
        appliedFont = font
        // Prompt-theme icons (Nerd Font/Powerline codepoints) render from an
        // installed patched font even when the selected font lacks them.
        terminal.glyphFallbackProvider = NerdFontFallback.shared
        terminal.nativeBackgroundColor = background
        appliedBackground = background
        var env = ProcessInfo.processInfo.environment
        env.merge(record.environment) { _, new in new }
        env = PersistentTerminal.environment(env)
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
            let wrapper = PersistentTerminal.wrapper(name: name, path: path, launch: [shell] + args)
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
    /// Read the bottom rows of the screen (a copied, lock-safe read) and
    /// match them against known prompts. Only live shells are sampled.
    @discardableResult func sampleAwaitingInput(enabled: Bool) -> Bool {
        var value = false
        if enabled, let view, state == "Shell" || state == "Program active" {
            let rows = view.terminalDimensions.rows
            value = AgentPrompt.awaitsInput(view.visibleRowsText(max(0, rows - AgentPrompt.rowsToScan)..<rows))
        }
        if awaitingInput != value { awaitingInput = value }
        return value
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
    /// OSC 7501: a program reporting `blocked` (permission, question or
    /// sign-in) is waiting for the user.
    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
        state = records.isEmpty ? "Shell" : (records.contains { $0.state == .blocked } ? "Awaiting input" : "Program active")
    }
}

/// Terminal focus tracking is event-driven via window update/key notifications
/// (SwiftTerm's first-responder overrides are not `open`, so no subclass hook).
/// The handler is an O(panes) pointer comparison; publishes only on change.

struct EmbeddedTerminal: NSViewRepresentable {
    @ObservedObject var session: Session
    let path: String
    let fontName: String
    let fontSize: Double
    let persistent: Bool
    let background: NSColor
    var steadyCursor = false
    var font: NSFont { NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.terminal(path: path, font: font, persistent: persistent, background: background, steadyCursor: steadyCursor) }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        // Assign only when the target actually changed: updateNSView fires on
        // every state publish, and each assignment forces a cached-state refresh.
        if session.appliedFont != font {
            session.appliedFont = font
            view.font = font
        }
        // The setter returns early when the value is unchanged.
        (view as? GroveTerminalView)?.steadyCursor = steadyCursor
        if session.appliedBackground != background {
            session.appliedBackground = background
            view.nativeBackgroundColor = background
        }
    }
}

