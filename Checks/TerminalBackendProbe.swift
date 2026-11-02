import Foundation

@main struct TerminalBackendProbe {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 3 && arguments[1] == "end" {
            try PersistentTerminal.end(name: arguments[2]); return
        }
        guard arguments.count == 4 && arguments[1] == "wrapper" else { fatalError("Expected wrapper NAME PATH or end NAME") }
        let input = ["STY": "inherited-screen", "TMUX": "inherited-tmux", "TMUX_PANE": "%99", "TMUX_TMPDIR": "/bad", "TERM": "screen", "GROVE_PANE_ID": arguments[2]]
        let output = PersistentTerminal.environment(input)
        precondition(output["STY"] == nil && output["TMUX"] == nil && output["TMUX_PANE"] == nil && output["TMUX_TMPDIR"] == nil && output["TERM"] == "xterm-256color")
        precondition(output["GROVE_PANE_ID"] == arguments[2])
        print(PersistentTerminal.wrapper(name: arguments[2], path: arguments[3], launch: ["/bin/zsh", "-f"]))
    }
}
