import SwiftUI
import AppKit

struct OpenMenu: View {
    @EnvironmentObject var model: Workspace
    let path: String
    @AppStorage("openApplication") private var preferred = OpenTarget.vscode.rawValue
    @State private var applications: [OpenTarget: URL] = [:]
    private var primary: OpenTarget {
        if let saved = OpenTarget(rawValue: preferred), saved == .finder || applications[saved] != nil { return saved }
        return OpenTarget.allCases.first { applications[$0] != nil } ?? .finder
    }
    var body: some View {
        Menu {
            ForEach(OpenTarget.allCases) { target in
                Button {
                    preferred = target.rawValue
                    open(target)
                } label: {
                    Label(target.title + (target != .finder && applications[target] == nil ? " (not installed)" : ""), systemImage: target.symbol)
                }.disabled(target != .finder && applications[target] == nil)
            }
        } label: {
            Label("Open", systemImage: primary.symbol)
        } primaryAction: {
            open(primary)
        }
        .help("Open selected worktree in \(primary.title); use the arrow to choose another app")
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        applications = Dictionary(uniqueKeysWithValues: OpenTarget.allCases.compactMap { target in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier).map { (target, $0) }
        })
    }
    private func open(_ target: OpenTarget) {
        do {
            let url = try target.url(at: path)
            if target == .finder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            // Resolve again at launch in case an app was installed/moved/removed.
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
                refresh(); model.error = "\(target.title) is not installed or cannot be located by macOS."; return
            }
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    let message = "Could not open \(target.title): \(error.localizedDescription)"
                    Task { @MainActor in model.error = message }
                }
            }
        } catch { model.error = "Could not open this worktree: \(error.localizedDescription)" }
    }
}
