import XCTest
import SwiftUI
import AppKit
@testable import Grove

final class FolderPickerTests: XCTestCase {
    @MainActor func testRepositoryButtonOpensFolderPicker() throws {
        guard ProcessInfo.processInfo.environment["GROVE_RUN_FOLDER_PICKER_CHECK"] == "1" else {
            throw XCTSkip("Requires a logged-in macOS GUI session")
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-picker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = Workspace(verificationPath: root.path)
        model.saved = SavedWorkspace()
        let host = NSHostingView(rootView: ContentView().environmentObject(model).frame(minWidth: 1000, minHeight: 640))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        var sawPanel = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let panel = app.windows.compactMap({ $0 as? NSOpenPanel }).first(where: { $0.isVisible }) {
                sawPanel = true
                panel.cancel(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        DispatchQueue.main.async {
            // Fixed 1000×700 content: exercise the padded area left of the
            // plus glyph, which the old plain image button did not accept.
            let point = NSPoint(x: 420, y: 528)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                app.sendEvent(event)
            }
        }
        let end = Date().addingTimeInterval(3)
        while !sawPanel && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(sawPanel, "Repository add did not display a folder picker")
    }
}
