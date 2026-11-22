import SwiftUI

enum DesignTokens {
    static let divider: CGFloat = 1
    static let rowRadius: CGFloat = 6
    static let buttonRadius: CGFloat = 4
    static let icon: CGFloat = 14
    static let buttonHitSize: CGFloat = 27
    static let windowInset: CGFloat = 28
    static let headerHeight: CGFloat = 64
    static let writingPanelHeaderHeight: CGFloat = 30
    static let paletteWidth: CGFloat = 520
    static let paletteHeight: CGFloat = 340
    static let palettePadding: CGFloat = 12
}

struct WindowPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }

    var sidebar: Color { dark ? color(0x141415) : color(0xEDEDEB) }
    var workspace: Color { dark ? color(0x181818) : color(0xF8F8F7) }
    var selection: Color { dark ? color(0x2A2D35) : color(0xDBDBDA) }
    var border: Color { dark ? color(0x2A2A2D) : color(0xDEDEDC) }
    var tint: Color { dark ? color(0x84AEFF) : color(0x475466) }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct ChromeSymbol: View {
    var name: String
    var size: CGFloat = DesignTokens.icon

    var body: some View {
        Image(systemName: name).font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome).accessibilityHidden(true)
    }
}

struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .frame(minWidth: DesignTokens.buttonHitSize, minHeight: DesignTokens.buttonHitSize)
            .foregroundStyle(Color.primary.opacity(enabled ? 0.76 : 0.32))
            .background(configuration.isPressed ? WindowPalette(scheme: scheme).selection : .clear, in: .rect(cornerRadius: DesignTokens.buttonRadius))
            .contentShape(Rectangle())
    }
}
