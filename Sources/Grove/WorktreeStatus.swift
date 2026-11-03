import SwiftUI

/// Semantic agent/worktree status. Derived at runtime from `Session.state`
/// strings — never persisted (no workspace.v2 schema migration).
enum WorktreeStatus: Int {
    case awaitingInput = 0, failed = 1, completed = 2, running = 3, idle = 4, ended = 5, starting = 6

    /// Triage precedence per council review: failed first (needs action),
    /// then awaiting input, then completed (ready for review), then running.
    var sortRank: Int {
        switch self {
        case .failed: return 0
        case .awaitingInput: return 1
        case .completed: return 2
        case .running: return 3
        case .idle, .ended, .starting: return 4
        }
    }

    var symbol: String {
        switch self {
        case .awaitingInput: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.circle.fill"
        case .running: return "bolt.fill"
        case .idle: return "circle"
        case .ended: return "moon.fill"
        case .starting: return "circle.dotted"
        }
    }

    var color: Color {
        switch self {
        case .awaitingInput: return .orange
        case .failed: return .red
        case .completed: return .green
        case .running: return Color(red: 0.68, green: 0.88, blue: 0.51)
        case .idle: return .secondary
        case .ended: return .secondary
        case .starting: return .secondary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .awaitingInput: return "Awaiting input"
        case .failed: return "Failed"
        case .completed: return "Completed, ready for review"
        case .running: return "Running"
        case .idle: return "Idle"
        case .ended: return "Ended"
        case .starting: return "Starting"
        }
    }

    /// Exhaustive mapping of every `Session.state` string value.
    /// Inventory: "Starting", "Shell", bare "Exited", "Ended",
    /// "Exited N", "Exited signal", "Launch failed: …", "Program active".
    static func parse(_ state: String) -> WorktreeStatus {
        if state == "Starting" { return .starting }
        if state == "Shell" { return .idle }
        if state == "Ended" { return .ended }
        if state == "Program active" { return .running }
        if state.hasPrefix("Launch failed") { return .failed }
        if state == "Exited" { return .idle }
        if state.hasPrefix("Exited ") {
            let code = state.dropFirst("Exited ".count)
            if code == "signal" { return .failed }
            if let value = Int(code) { return value == 0 ? .completed : .failed }
            return .failed
        }
        return .idle
    }
}

struct DiffSummary: Equatable {
    var dirty: Bool
    var additions: Int
    var deletions: Int
}
