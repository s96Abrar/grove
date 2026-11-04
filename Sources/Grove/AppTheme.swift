import SwiftUI
import AppKit

struct AppTheme {
    let sidebarBackground: Color
    let panelBackground: Color
    let mainBackground: Color
    let accent: Color
    let terminalBackground: NSColor
    /// Ultra-thin vibrancy in the HighPerformance tier; nil → opaque surfaces.
    let material: Material?
    let animationsEnabled: Bool

    static func resolved(tier: PerformanceTier, animationsEnabled: Bool,
                         scheme: ColorScheme, reduceTransparency: Bool, reduceMotion: Bool) -> AppTheme {
        let dark = scheme == .dark
        let allowMaterial = tier == .highPerformance && !reduceTransparency && !reduceMotion
        return AppTheme(
            sidebarBackground: dark ? Color(red: 0.085, green: 0.095, blue: 0.09) : Color(nsColor: .controlBackgroundColor),
            panelBackground: dark ? Color(red: 0.085, green: 0.095, blue: 0.09) : Color(nsColor: .controlBackgroundColor),
            mainBackground: dark ? Color(red: 0.055, green: 0.065, blue: 0.06) : Color(nsColor: .windowBackgroundColor),
            accent: Color(red: 0.68, green: 0.88, blue: 0.51),
            terminalBackground: dark ? NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.06, alpha: 1) : .textBackgroundColor,
            material: allowMaterial ? .ultraThinMaterial : nil,
            animationsEnabled: animationsEnabled && !reduceMotion && !reduceTransparency)
    }

    static let `default` = AppTheme(
        sidebarBackground: Color(red: 0.085, green: 0.095, blue: 0.09),
        panelBackground: Color(red: 0.085, green: 0.095, blue: 0.09),
        mainBackground: Color(red: 0.055, green: 0.065, blue: 0.06),
        accent: Color(red: 0.68, green: 0.88, blue: 0.51),
        terminalBackground: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.06, alpha: 1),
        material: nil,
        animationsEnabled: false)
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.default
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// Runs `body` with a spring animation only when the active profile tier
/// allows it (HighPerformance and accessibility preferences permitting).
func withProfileAnimation<T>(_ body: () throws -> T) rethrows -> T {
    let enabled = MainActor.assumeIsolated { PerformanceProfileManager.shared.animationsEnabled }
    if enabled {
        return try withAnimation(.spring(response: 0.22, dampingFraction: 0.88), body)
    }
    return try withTransaction(Transaction(animation: nil), body)
}
