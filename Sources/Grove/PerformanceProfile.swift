import AppKit
import SwiftUI

enum PerformanceProfile: String, CaseIterable, Identifiable {
    case auto, highPerformance, efficient
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (System-Aware)"
        case .highPerformance: return "High Performance"
        case .efficient: return "Efficient"
        }
    }
}

enum PerformanceTier {
    case highPerformance, efficient
}

/// Dual performance profile system. Manual overrides always win; Auto mode
/// downgrades to the Efficient tier only after a trigger (Low Power Mode,
/// sustained thermal pressure) has held for a dwell interval, and upgrades
/// back only after triggers have cleared — so transient blips never thrash
/// the visual tier. App-inactive never downgrades the tier; it gates
/// animations only (see `animationsEnabled`).
@MainActor
final class PerformanceProfileManager: ObservableObject {
    static let shared = PerformanceProfileManager()
    @Published var profile: PerformanceProfile {
        didSet { UserDefaults.standard.set(profile.rawValue, forKey: "performanceProfile"); evaluate() }
    }
    @Published private(set) var effectiveTier: PerformanceTier = .highPerformance
    @Published private(set) var activeTriggers: [String] = []
    private var downgradeSince: Date?
    private var upgradeSince: Date?
    private var evalTask: Task<Void, Never>?
    private static let downgradeDwell: TimeInterval = 15
    private static let upgradeDwell: TimeInterval = 10

    private init() {
        profile = PerformanceProfile(rawValue: UserDefaults.standard.string(forKey: "performanceProfile") ?? "") ?? .auto
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        center.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        center.addObserver(forName: .init("NSProcessInfoThermalStateDidChange"), object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    var animationsEnabled: Bool { effectiveTier == .highPerformance && NSApp?.isActive != false }

    /// Tier-gated status polling cadence in seconds.
    var statusPollInterval: TimeInterval { effectiveTier == .efficient ? 15 : 5 }

    private var thermalTriggers: [String] {
        var triggers: [String] = []
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { triggers.append("Low Power Mode enabled") }
        if info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { triggers.append("Thermal pressure") }
        return triggers
    }

    func evaluate() {
        let triggers = thermalTriggers
        let now = Date()
        if triggers.isEmpty {
            downgradeSince = nil
            if upgradeSince == nil { upgradeSince = now }
        } else {
            upgradeSince = nil
            if downgradeSince == nil { downgradeSince = now }
        }
        var tier: PerformanceTier
        if profile == .efficient { tier = .efficient }
        else if profile == .highPerformance { tier = .highPerformance }
        else if let since = downgradeSince, now.timeIntervalSince(since) >= Self.downgradeDwell { tier = .efficient }
        else if let since = upgradeSince, now.timeIntervalSince(since) >= Self.upgradeDwell { tier = .highPerformance }
        else { tier = effectiveTier }
        if tier != effectiveTier { effectiveTier = tier }
        activeTriggers = triggers
        objectWillChange.send()
        if profile == .auto && downgradeSince != nil && now.timeIntervalSince(downgradeSince!) < Self.downgradeDwell {
            scheduleReevaluation()
        }
    }

    private func scheduleReevaluation() {
        evalTask?.cancel()
        evalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
