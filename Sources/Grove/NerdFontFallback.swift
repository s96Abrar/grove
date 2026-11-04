import AppKit
import CoreText
import SwiftTerm

/// Draws Nerd Font and Powerline icon glyphs (private-use codepoints emitted
/// by prompt themes such as Powerlevel10k or Starship) with the best patched
/// font installed on the system when the selected terminal font lacks them.
///
/// SwiftTerm consults the provider only for scalars the terminal's own face
/// is missing (direct cmap query), so a user-selected patched font like
/// MesloLGS NF always keeps priority. When no suitable face is installed the
/// provider resolves to nil and rendering is unchanged.
///
/// The claimed candidate set is the Basic Multilingual Plane private-use
/// area, 0xE000–0xF8FF: where Nerd Fonts place every icon set (plus the
/// Apple logo). A terminal font that ships its own private-use glyphs is
/// unaffected because it is always tried first.
final class NerdFontFallback: TerminalGlyphFallbackProvider, @unchecked Sendable {
    static let shared = NerdFontFallback()

    /// Representative icons of the sets prompt themes use; a face covering
    /// most of these renders the common themes correctly.
    private static let probes: [UniChar] = [0xE0B0, 0xE0B2, 0xE725, 0xE0A0, 0xE0A2, 0xF00C, 0xF015, 0xF1D6, 0xE641]
    private static let probeMinimum = 7
    /// Patched faces tried first. Other installed fonts whose names suggest
    /// Nerd Font or Powerline coverage are scanned afterwards, by coverage.
    private static let preferredNames = ["Symbols Nerd Font Mono", "Symbols Nerd Font", "MesloLGS NF",
                                         "SauceCodePro Nerd Font Mono", "JetBrainsMono Nerd Font Mono",
                                         "FiraCode Nerd Font Mono", "Hack Nerd Font Mono",
                                         "CaskaydiaCove Nerd Font Mono"]

    private let lock = NSLock()
    private var resolutionAttempted = false
    private var baseFace: CTFont?
    private var faces: [CGFloat: CTFont] = [:]

    // The resolved face never changes after first use; one app run serves one
    // font set. Installing fonts takes effect on next launch.
    var generation: UInt64 { 1 }

    func placementPolicy (for scalar: Unicode.Scalar) -> TerminalGlyphPlacementPolicy? {
        let value = scalar.value
        guard (0xE000...0xF8FF).contains(value) else { return nil }
        // Powerline segment separators are full-cell shapes designed to butt
        // against neighbouring cells; other icons fit and center.
        if (0xE0B0...0xE0DF).contains(value) { return TerminalGlyphPlacementPolicy(placement: .stretch) }
        return TerminalGlyphPlacementPolicy(placement: .icon)
    }

    func fallbackFont (forPointSize size: CGFloat) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        if let face = faces[size] { return face }
        resolveLocked()
        guard let base = baseFace else { return nil }
        let face = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        faces[size] = face
        return face
    }

    /// Number of probe icons `name` contains. CoreText substitutes a system
    /// font for unknown names, so coverage — not resolution success — is
    /// what proves the patched face actually exists.
    private static func coverage (forName name: String) -> Int {
        let font = CTFontCreateWithName(name as CFString, 13, nil)
        var units = probes
        var glyphs = [CGGlyph](repeating: 0, count: probes.count)
        CTFontGetGlyphsForCharacters(font, &units, &glyphs, probes.count)
        return glyphs.filter { $0 != 0 }.count
    }

    private func resolveLocked () {
        guard !resolutionAttempted else { return }
        resolutionAttempted = true
        var candidates = Self.preferredNames
        let scanned = Set(NSFontManager.shared.availableFonts).subtracting(candidates).filter { name in
            let lower = name.lowercased()
            return lower.contains("nerd") || lower.contains("powerline") || lower.hasSuffix(" nf")
        }.sorted()
        candidates.append(contentsOf: scanned)
        for name in candidates where Self.coverage(forName: name) >= Self.probeMinimum {
            baseFace = CTFontCreateWithName(name as CFString, 13, nil)
            return
        }
    }
}
