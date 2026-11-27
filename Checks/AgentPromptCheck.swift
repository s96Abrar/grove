import Foundation

@main struct AgentPromptCheck {
    static func main() {
        let waiting: [(String, [String])] = [
            ("coding-agent permission dialog", ["╭──────────────────────────────╮", "│ Bash command                  │", "│   rm -rf build                │", "│ Do you want to proceed?       │", "│ ❯ 1. Yes                      │", "│   2. No, and tell me what to do differently (esc) │", "╰──────────────────────────────╯", "", ""]),
            ("allow question", ["▌ Allow command?", "▌ Yes (y)   No (n)"]),
            ("would you like to", ["Would you like to run the following command?", "  npm test", "› 1. Yes, proceed", "  2. No"]),
            ("y/N confirmation", ["Overwrite file.txt? [y/N]"]),
            ("Y/n with colon", ["Continue (Y/n):"]),
            ("yes/no", ["Are you sure you want to continue connecting (yes/no)?"]),
            ("press enter", ["Setup complete.", "Press Enter to continue..."])
        ]
        let notWaiting: [(String, [String])] = [
            ("empty screen", ["", "   ", ""]),
            ("plain shell", ["user@mac grove % ls", "README.md Sources", "user@mac grove %"]),
            ("starship prompt", ["~/grove on main", "❯"]),
            ("agent still working", ["│ Do you want to proceed? │", "✻ Thinking… (esc to interrupt)"]),
            ("answered and exited", ["Overwrite file.txt? [y/N] y", "done", "user@mac grove %"]),
            ("ordinary question in output", ["What is 2+2?", "4"]),
            ("question then shell prompt", ["Do you want to proceed?", "❯ 1. Yes", "$"])
        ]
        for (name, rows) in waiting { precondition(AgentPrompt.awaitsInput(rows), "should detect: \(name)") }
        for (name, rows) in notWaiting { precondition(!AgentPrompt.awaitsInput(rows), "should not detect: \(name)") }
        precondition(AgentPrompt.normalize("│  Do you want to proceed?  │") == "Do you want to proceed?")
        print("PASS: awaiting-input prompts (\(waiting.count) detected, \(notWaiting.count) ignored)")
    }
}
