import AppKit
import UserNotifications

/// Posts "waiting for input" notifications and routes clicks back to the
/// worktree. Notifications carry only the branch and repository names, never
/// terminal text.
@MainActor final class AttentionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AttentionNotifier()
    weak var workspace: Workspace?

    /// UNUserNotificationCenter requires a real app bundle; `swift run`,
    /// `swift test` and verification launches without one must not touch it.
    static var available: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// Install the click handler early, so a click that launches Grove still lands.
    func attach(_ workspace: Workspace) {
        self.workspace = workspace
        guard Self.available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        guard Self.available else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func post(path: String, branch: String, repository: String) {
        guard Self.available else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(branch) is waiting for input"
        content.body = "A terminal in \(repository) is asking a question."
        content.sound = .default
        content.threadIdentifier = path
        content.userInfo = ["path": path]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "awaiting-input:" + path, content: content, trigger: nil))
    }

    /// Remove delivered notifications for worktrees that are no longer waiting.
    func withdraw(paths: [String]) {
        guard Self.available, !paths.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: paths.map { "awaiting-input:" + $0 })
    }

    func setBadge(_ label: String?) { NSApp?.dockTile.badgeLabel = label }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        await MainActor.run { self.workspace?.reveal(path: path) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
