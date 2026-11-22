import AppKit
import SwiftUI

enum DesignTokens {
    static let divider: CGFloat = 1
    static let rowRadius: CGFloat = 6
    static let popoverRadius: CGFloat = 8
    static let buttonRadius: CGFloat = 4
    static let icon: CGFloat = 16
    static let buttonHitSize: CGFloat = 27
    static let windowInset: CGFloat = 28
    static let headerHeight: CGFloat = 64
    static let writingPanelHeaderHeight: CGFloat = 30
    static let pathBarHeight: CGFloat = 30
    /// Visible border around a sheet in paginated views: about 3 mm.
    static let pageBorder: CGFloat = 8.5
    static let paletteWidth: CGFloat = 520
    static let paletteHeight: CGFloat = 340
    static let palettePadding: CGFloat = 12
}

/// Single colour palette for every surface, Cursor-style: neutral greys and one accent.
/// Contrast targets (WCAG AA): primary and secondary text ≥ 4.5:1 on `surface` and `background`;
/// tertiary text ≥ 4.5:1 on `background`; `accent` ≥ 3:1 against both the background and white,
/// so system checkmarks and switch knobs drawn in white stay legible on it.
struct WindowPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    /// Editor and main workspace.
    var background: Color { dark ? color(0x181818) : color(0xF8F8F7) }
    /// Side panels: navigation, inspector, tab strip.
    var surface: Color { dark ? color(0x141415) : color(0xEDEDEB) }
    /// Floating elements: menus, popovers, palette, sheets.
    var elevated: Color { dark ? color(0x1F1F20) : color(0xFFFFFF) }
    var border: Color { dark ? color(0x2A2A2D) : color(0xDEDEDC) }
    var selection: Color { dark ? color(0x2B2B2E) : color(0xDBDBDA) }
    var hover: Color { dark ? color(0x232325) : color(0xE4E4E2) }
    var textPrimary: Color { dark ? color(0xE4E4E4) : color(0x1F1F1F) }
    var textSecondary: Color { dark ? color(0xA0A0A0) : color(0x5C5C5C) }
    var textTertiary: Color { dark ? color(0x808080) : color(0x6A6A6A) }
    /// The only accent in the app. Neutral, never the system blue.
    var accent: Color { dark ? color(0x8C8C8C) : color(0x555555) }

    // Former names kept so existing call sites read naturally.
    var workspace: Color { background }
    var sidebar: Color { surface }
    var tint: Color { accent }

    /// Surface colour as an appearance-aware NSColor, for AppKit chrome such as the toolbar area.
    static let nativeSurface = NSColor(name: "ThinkBoxSurface") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x15 / 255, alpha: 1)
            : NSColor(srgbRed: 0xED / 255, green: 0xED / 255, blue: 0xEB / 255, alpha: 1)
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// Replaces the system accent (blue by default) inside Think Box with the graphite one, which is
/// what AppKit draws for focus rings, list and text selection and native checkboxes. SwiftUI
/// controls receive `WindowPalette.accent` through `themedWindow()`.
enum AppAccent {
    static func install(defaults: UserDefaults = .standard) {
        // -1 is the graphite accent; the highlight value is the matching grey text selection.
        defaults.set(-1, forKey: "AppleAccentColor")
        defaults.set("0.847059 0.847059 0.862745 Graphite", forKey: "AppleHighlightColor")
    }
}

private struct ThemedWindow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = WindowPalette(scheme: scheme)
        content.tint(palette.accent).accentColor(palette.accent)
            .buttonStyle(ChromePushButtonStyle())
    }
}

extension View {
    /// Applies the single Think Box accent to a window, sheet or panel and everything it presents.
    func themedWindow() -> some View { modifier(ThemedWindow()) }
}

/// Segmented selector drawn with palette tokens instead of the system-accented NSSegmentedControl.
struct ChromeSegmented<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [(value: Value, label: String)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WindowPalette(scheme: scheme)
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let active = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label).lineLimit(1).frame(maxWidth: .infinity, minHeight: 22)
                        .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                        .background(active ? palette.elevated : .clear, in: .rect(cornerRadius: DesignTokens.buttonRadius))
                        .overlay {
                            if active { RoundedRectangle(cornerRadius: DesignTokens.buttonRadius).strokeBorder(palette.border) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .background(palette.selection.opacity(0.5), in: .rect(cornerRadius: DesignTokens.rowRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Icon and toolbar buttons: transparent at rest, `hover` background and primary text under
/// the pointer, `selection` while pressed or when `active` (a toggled panel, a chosen layout).
struct ChromeButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        ChromeButtonBody(configuration: configuration, active: active)
    }
}

private struct ChromeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let active: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let palette = WindowPalette(scheme: scheme)
        let lit = enabled && (hovering || active || configuration.isPressed)
        configuration.label
            .padding(.horizontal, 5)
            .frame(minWidth: DesignTokens.buttonHitSize, minHeight: DesignTokens.buttonHitSize)
            .foregroundStyle(!enabled ? palette.textTertiary.opacity(0.6) : lit ? palette.textPrimary : palette.textSecondary)
            .background(background(palette), in: .rect(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    private func background(_ palette: WindowPalette) -> Color {
        guard enabled else { return .clear }
        if configuration.isPressed || active { return palette.selection }
        return hovering ? palette.hover : .clear
    }
}

/// Text buttons (actions in forms, empty states, sheets): elevated fill, 1 px border, 4 px radius.
/// Applied scene-wide through `themedWindow()`, so every button without its own style uses it.
struct ChromePushButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChromePushButtonBody(configuration: configuration)
    }
}

private struct ChromePushButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let palette = WindowPalette(scheme: scheme)
        configuration.label
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minHeight: 22)
            .foregroundStyle(enabled ? palette.textPrimary : palette.textTertiary)
            .background(configuration.isPressed ? palette.selection : hovering && enabled ? palette.hover : palette.elevated,
                        in: .rect(cornerRadius: DesignTokens.buttonRadius))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.buttonRadius).strokeBorder(palette.border) }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
