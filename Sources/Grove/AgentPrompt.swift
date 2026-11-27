import Foundation

/// Recognises a terminal program that is waiting for the user, from the text
/// at the bottom of its screen: permission questions from coding agents,
/// yes/no confirmations and "press Enter" pauses. Pure text matching on rows
/// the caller copies from the visible screen; nothing is stored or sent.
enum AgentPrompt {
    /// How many bottom rows of the screen callers should pass in.
    static let rowsToScan = 12

    /// `rows` are visible screen rows, top to bottom.
    static func awaitsInput(_ rows: [String]) -> Bool {
        let lines = rows.map(normalize).filter { !$0.isEmpty }
        guard let last = lines.last else { return false }
        let tail = lines.suffix(8)
        // Agents show an interrupt hint while they are still working.
        if tail.contains(where: isBusy) { return false }
        // A shell prompt below the text means the program already finished.
        if !isPrompt(last) && looksLikeShellPrompt(last) { return false }
        return tail.contains(where: isPrompt)
    }

    /// Trim whitespace and the box-drawing borders agents draw around dialogs.
    static func normalize(_ row: String) -> String {
        row.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "│┃║|╭╮╰╯┌┐└┘─━═▌▐\u{00A0}")))
    }

    static func isBusy(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("esc to interrupt") || lower.contains("ctrl+c to interrupt") || lower.contains("ctrl-c to interrupt")
    }

    static func isPrompt(_ line: String) -> Bool {
        let lower = line.lowercased()
        // (y/n), [Y/n], (yes/no) at the end of the line, optionally followed by ? or :
        if lower.range(of: #"[\[(]\s*y(es)?\s*/\s*n(o)?\s*[\])]\s*[?:]?$"#, options: .regularExpression) != nil { return true }
        if lower.hasSuffix("?") {
            for opening in ["do you want to", "would you like to", "allow ", "approve ", "proceed", "continue"] where lower.hasPrefix(opening) { return true }
        }
        if lower.contains("press enter to") || lower.contains("press return to") || lower.contains("waiting for your approval") || lower.contains("waiting for your input") { return true }
        // A highlighted numbered choice, e.g. "❯ 1. Yes" or "› 2) No".
        if line.range(of: #"^[❯›▶●➤]\s*\d+[.)]\s+\S"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// zsh/bash/fish/starship prompts end with one of these marks.
    static func looksLikeShellPrompt(_ line: String) -> Bool {
        guard line.count <= 200, let mark = line.last else { return false }
        return "$%#❯➜λ".contains(mark)
    }
}
