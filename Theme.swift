import SwiftUI
import AppKit

/// Design tokens for MyWispr's interface.
///
/// Everything the UI draws routes through here, for two reasons:
///
/// 1. **Light and dark.** Every value is either a macOS semantic colour or a
///    SwiftUI `Material`, so the whole app follows the system appearance
///    instead of being pinned to one. Nothing here is a fixed shade.
/// 2. **One place to tune.** Retuning the look is a change to this file rather
///    than a sweep across ~1,500 lines of view code.
///
/// The visual language matches the overlay notch: translucent materials,
/// continuous-curvature corners and hairline strokes rather than opaque panels
/// with solid 1px borders.
enum Theme {

    // MARK: - Surfaces

    /// Card and panel background. A translucent material, so panels pick up the
    /// desktop and window behind them the way Apple's own inspectors do.
    static let panelMaterial: Material = .regularMaterial

    /// Background for controls sitting *inside* a panel (text fields, editors),
    /// which need to read as recessed against the panel material.
    static let fieldMaterial: Material = .thinMaterial

    /// Opaque fallback for the few places a material cannot be used
    /// (`List` row backgrounds, which composite badly over vibrancy).
    static let surface = Color(NSColor.controlBackgroundColor)

    /// Subtle inset tint for recessed regions (list columns, read-only boxes).
    ///
    /// Deliberately a translucent tint rather than `underPageBackgroundColor`,
    /// which renders as a heavy mid-grey slab in light mode. This layers over
    /// the window vibrancy and stays subtle in both appearances.
    static let recessed = Color.primary.opacity(0.05)

    // MARK: - Lines

    /// Dividers and separators between regions.
    static let separator = Color(NSColor.separatorColor)

    /// Hairline outlining a glass panel. Deliberately faint: on a material the
    /// edge should suggest a boundary, not draw a box around it.
    static let hairline = Color.primary.opacity(0.12)

    /// Slightly stronger outline for interactive controls.
    static let controlStroke = Color.primary.opacity(0.20)

    // MARK: - Text

    /// Primary text. Black in light mode, white in dark — flips automatically.
    static let label = Color.primary
    /// Captions, hints, section headers.
    static let secondaryLabel = Color.secondary
    /// Faintest tier: version strings, footnotes.
    static let tertiaryLabel = Color(NSColor.tertiaryLabelColor)

    // MARK: - Accent

    /// Fill for primary buttons and selected rows.
    ///
    /// `Color.primary` inverts with the appearance, which preserves the app's
    /// monochrome look: black-on-white in light mode becomes white-on-black in
    /// dark, rather than collapsing into a mid grey.
    static let accent = Color.primary

    /// Text drawn *on top of* `accent`. The inverse of `label`.
    static let onAccent = Color(NSColor.controlBackgroundColor)

    /// Subtle fill for unselected chips and secondary buttons.
    static let accentMuted = Color.primary.opacity(0.06)

    // MARK: - Status

    /// Status colours are system colours, which already adapt per appearance.
    /// Kept as named tokens so contrast can be tuned in one place if needed.
    static let success = Color.green
    static let warning = Color.orange
    static let danger  = Color.red

    // MARK: - Metrics

    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6
    static let chipRadius: CGFloat = 4
}

// MARK: - Glass Panel

/// Gives a view the standard translucent panel treatment: material fill,
/// continuous-curvature corners and a hairline edge.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = Theme.panelRadius
    var material: Material = Theme.panelMaterial

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}

/// Recessed field treatment for text fields and editors inside a panel.
struct GlassField: ViewModifier {
    var radius: CGFloat = Theme.controlRadius

    func body(content: Content) -> some View {
        content
            .background(Theme.fieldMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.controlStroke, lineWidth: 0.5)
            )
    }
}

extension View {
    /// Standard translucent panel: use for cards and grouped sections.
    func glassPanel(radius: CGFloat = Theme.panelRadius, material: Material = Theme.panelMaterial) -> some View {
        modifier(GlassPanel(radius: radius, material: material))
    }

    /// Recessed control surface: use for text fields, editors and search bars.
    func glassField(radius: CGFloat = Theme.controlRadius) -> some View {
        modifier(GlassField(radius: radius))
    }
}

// MARK: - Vibrancy

/// Bridges `NSVisualEffectView` so the sidebar and window background get real
/// AppKit vibrancy, which SwiftUI's `Material` cannot provide behind a window.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Appearance

/// User-selectable window appearance.
///
/// Exposed in the dashboard so the app is not at the mercy of the system
/// setting, and so light/dark can be checked without leaving the app.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `nil` means "inherit from the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the choice to the whole app.
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
