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
        // Closing either side of a nested split must preserve all surviving IDs.
        let thirdPane = PaneRecord()
        let nested = TabRecord(panes: [oldPane, newPane, thirdPane], layout: .split(vertical: true, first: .pane(oldPane.id), second: .split(vertical: false, first: .pane(newPane.id), second: .pane(thirdPane.id))))
        for removedID in nested.panes.map(\.id) {
            let reduced = nested.removingPane(removedID)!
            precondition(reduced.id == nested.id)
            var fixture = first; fixture.tabs["/tmp/project"] = [reduced]
            try fixture.validate()
            precondition(reduced.panes.map(\.id) == nested.panes.filter { $0.id != removedID }.map(\.id))
            let survivor = reduced.removingPane(reduced.panes[0].id)!
            fixture.tabs["/tmp/project"] = [survivor]; try fixture.validate()
            precondition(survivor.panes.count == 1 && survivor.removingPane(survivor.panes[0].id) == nil)
            try WorkspacePersistence.save(fixture, to: defaults)
            let loadedSurvivor = try WorkspacePersistence.load(from: defaults)!.state.tabs["/tmp/project"]![0]
            precondition(loadedSurvivor.panes[0].id == survivor.panes[0].id)
        }
        if case .split(let vertical, .pane(let left), .pane(let right)) = nested.removingPane(oldPane.id)!.layout! {
            precondition(!vertical && left == newPane.id && right == thirdPane.id)
        } else { fatalError("Nested sibling layout was not promoted") }
        precondition(nested.removingPane(UUID()) == nil)
        var legacySplit = nested; legacySplit.layout = nil
        precondition(legacySplit.removingPane(newPane.id)!.panes.count == 2)
        // Restore the original backup fixture after the pane-removal round trips.
        try WorkspacePersistence.save(first, to: defaults)
        try WorkspacePersistence.save(second, to: defaults)
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
        print("PASS: workspace round-trip, backup recovery, corrupt preservation, schema migration, invalid pane/layout rejection, nested split removal/collapse/restoration, no startup-command replay")
    }
}
