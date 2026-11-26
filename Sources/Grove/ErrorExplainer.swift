import Foundation

/// Turns common Git, SSH, `gh` and macOS failures into a plain sentence with
/// a next step, keeping the tool's own output underneath as details.
/// Messages it does not recognise are returned unchanged.
enum ErrorExplainer {
    private static let rules: [(needles: [String], advice: String)] = [
        (["could not resolve host", "network is unreachable", "connection timed out", "operation timed out", "failed to connect", "no route to host"],
         "Grove couldn't reach the server. Check your network connection, then try again."),
        (["low speed limit", "transfer rate"],
         "The transfer stalled (slower than 1 KB/s for a minute) and was stopped. Try again on a better connection."),
        (["permission denied (publickey)", "host key verification failed"],
         "The SSH connection was refused. Check that your SSH key is loaded (ssh-add) and that the host is in known_hosts, by connecting once in Terminal."),
        (["authentication failed", "could not read username", "could not read password"],
         "The server needs credentials. Sign in once with Git in Terminal (or set up a credential helper), then try again."),
        (["gh auth login", "not logged into any github hosts", "authentication required"],
         "The GitHub CLI isn't signed in. Run `gh auth login` in a terminal, then try again."),
        (["operation not permitted"],
         "macOS blocked access to this folder. Allow Grove in System Settings → Privacy & Security → Files and Folders (or Full Disk Access), then try again."),
    ]
    static func explain(_ raw: String) -> String {
        let lower = raw.lowercased()
        guard let rule = rules.first(where: { $0.needles.contains(where: lower.contains) }) else { return raw }
        let details = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? rule.advice : rule.advice + "\n\nDetails:\n" + details
    }
}
