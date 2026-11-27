import AppKit
import SwiftTerm

/// SwiftTerm's process view, able to show a blinking cursor steady. In the
/// Efficient profile and with Reduce Motion a blinking cursor only costs
/// redraws. Programs still choose their cursor shape (DECSCUSR); only the
/// blink is dropped from what is displayed, and the program's requested style
/// in terminal state is never changed.
final class GroveTerminalView: LocalProcessTerminalView {
    /// Read from SwiftTerm's parser thread, written on the main actor.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
    private let steady = Flag()

    var steadyCursor: Bool {
        get { steady.value }
        set {
            guard newValue != steady.value else { return }
            steady.value = newValue
            // Re-send the program's current style so the displayed caret
            // follows the new setting; the terminal ends on the same style.
            let current = terminalStateSnapshot().cursorStyle
            setCursorStyle(current == .steadyBar ? .steadyBlock : .steadyBar)
            setCursorStyle(current)
        }
    }

    nonisolated override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: steady.value ? Self.steadyStyle(newStyle) : newStyle)
    }

    nonisolated static func steadyStyle(_ style: CursorStyle) -> CursorStyle {
        switch style {
        case .blinkBlock: return .steadyBlock
        case .blinkUnderline: return .steadyUnderline
        case .blinkBar: return .steadyBar
        default: return style
        }
    }
}
