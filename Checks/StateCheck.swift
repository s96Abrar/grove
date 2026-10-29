import Foundation

@main struct StateCheck {
    static func main() throws {
        let suite = "grove-state-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = SavedWorkspace()
        first.roots = ["/tmp/project"]
        first.tabs["/tmp/project"] = [TabRecord()]
        first.activeTabs = ["/tmp/project": first.tabs["/tmp/project"]![0].id]
        try WorkspacePersistence.save(first, to: defaults)
        var second = first
        let newPane = PaneRecord()
        let oldPane = second.tabs["/tmp/project"]![0].panes[0]
        second.tabs["/tmp/project"]![0].panes.append(newPane)
        second.tabs["/tmp/project"]![0].layout = .split(vertical: true, first: .pane(oldPane.id), second: .pane(newPane.id))
        try WorkspacePersistence.save(second, to: defaults)
        let restored = try WorkspacePersistence.load(from: defaults)!
        precondition(restored.state.activeTabs?["/tmp/project"] == first.activeTabs?["/tmp/project"])
        precondition(restored.state.tabs["/tmp/project"]![0].panes.count == 2)
        let broken = Data("{incomplete".utf8)
        defaults.set(broken, forKey: WorkspacePersistence.currentKey)
        let backup = try WorkspacePersistence.load(from: defaults)!
        precondition(backup.recoveredBackup)
        precondition(backup.state.tabs["/tmp/project"]![0].panes.count == 1)
        precondition(defaults.data(forKey: WorkspacePersistence.unreadableKey) == broken)
        defaults.removeObject(forKey: WorkspacePersistence.backupKey)
        do { _ = try WorkspacePersistence.load(from: defaults); fatalError("Unreadable state silently accepted") } catch {}
        var invalid = first
        invalid.tabs["/tmp/project"]![0].panes = []
        do { try invalid.validate(); fatalError("Empty pane list accepted") } catch {}
        invalid = first
        invalid.tabs["/tmp/project"]![0].layout = .pane(UUID())
        do { try invalid.validate(); fatalError("Dangling layout identity accepted") } catch {}
        invalid = first; invalid.schemaVersion = 99
        do { try invalid.validate(); fatalError("Future schema accepted") } catch {}
        let launch = PaneRecord(command: "do-not-replay-on-restore")
        let encodedLaunch = try JSONEncoder().encode(launch)
        precondition(!String(decoding: encodedLaunch, as: UTF8.self).contains("do-not-replay"))
        var legacyLaunch = try JSONSerialization.jsonObject(with: encodedLaunch) as! [String: Any]
        legacyLaunch["command"] = "do-not-replay-on-restore"
        let decodedLaunch = try JSONDecoder().decode(PaneRecord.self, from: JSONSerialization.data(withJSONObject: legacyLaunch))
        precondition(decodedLaunch.command == nil)
        // Version 0.2 state has no schemaVersion or activeTabs; it must still migrate.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        legacy.removeValue(forKey: "schemaVersion"); legacy.removeValue(forKey: "activeTabs")
        _ = try WorkspacePersistence.decode(JSONSerialization.data(withJSONObject: legacy))
        print("PASS: workspace round-trip, backup recovery, corrupt preservation, schema migration, invalid pane/layout rejection, no startup-command replay")
    }
}
