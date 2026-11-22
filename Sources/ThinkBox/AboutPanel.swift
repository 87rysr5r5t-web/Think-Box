import AppKit
import SwiftUI

/// Shared switch for the «Acerca de» panel, so the toolbar button and the app menu item
/// (MN-APP-01) open the very same panel (F2-R06).
@MainActor @Observable
final class AboutPresenter {
    static let shared = AboutPresenter()
    var visible = false
}

enum AppInfo {
    static let name = "Think-Box"
    static let tagline = "A writing tool"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    /// The app icon from the bundle (CFBundleIconFile); the generic app icon when run unbundled.
    @MainActor static var icon: NSImage { NSApp.applicationIconImage ?? NSImage() }

    /// The dark glyph of the app icon, cropped to its bounds and turned into a template image,
    /// so the small toolbar button shows the mark without the icon's white tile and takes the
    /// text colour like the other toolbar icons.
    @MainActor static let mark: NSImage? = {
        // Sample the bundle icon at high resolution; the generic app icon has no usable glyph.
        let source: NSImage = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) ?? icon
        let side = 512
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgSource = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgSource, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Keep only the dark glyph, with soft (anti-aliased) edges from its luminance.
        var minX = side, minY = side, maxX = -1, maxY = -1
        var sumX = 0.0, sumY = 0.0, mass = 0.0
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let alpha = Double(pixels[index + 3]) / 255
                // Premultiplied: recover colour before judging how dark it is.
                let luminance = alpha > 0 ? (Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])) / (3 * alpha) : 255
                let ink = max(0, min(1, (200 - luminance) / 150)) * alpha
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0
                pixels[index + 3] = UInt8((ink * 255).rounded())
                if ink > 0.5 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    sumX += Double(x); sumY += Double(y); mass += 1
                }
            }
        }
        guard mass > 0, let masked = context.makeImage() else { return nil }
        // Centre on the glyph's mass rather than its bounding box, so the main shape — not the
        // shape plus its satellite dot — sits in the middle of the button like the other icons.
        let centerX = sumX / mass, centerY = sumY / mass
        let half = max(centerX - Double(minX), Double(maxX) - centerX, centerY - Double(minY), Double(maxY) - centerY) + 2
        let extent = Int((half * 2).rounded(.up))
        guard let canvas = CGContext(data: nil, width: extent, height: extent, bitsPerComponent: 8, bytesPerRow: extent * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Loop rows are the image's rows top-down; CGContext drawing runs bottom-up.
        let originX = half - centerX
        let originY = half - (Double(side) - centerY)
        canvas.draw(masked, in: CGRect(x: originX, y: originY, width: Double(side), height: Double(side)))
        guard let glyph = canvas.makeImage() else { return nil }
        let image = NSImage(cgImage: glyph, size: NSSize(width: DesignTokens.icon, height: DesignTokens.icon))
        image.isTemplate = true
        return image
    }()
}

/// Small toolbar button showing the app icon. Opens the «Acerca de» panel.
struct AboutButton: View {
    var body: some View {
        Button { AboutPresenter.shared.visible = true } label: {
            if let mark = AppInfo.mark {
                Image(nsImage: mark).renderingMode(.template).resizable().interpolation(.high)
                    .frame(width: DesignTokens.icon, height: DesignTokens.icon)
            } else {
                Image(nsImage: AppInfo.icon).resizable().interpolation(.high).frame(width: 18, height: 18)
            }
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Acerca de \(AppInfo.name)")
        .help("Acerca de \(AppInfo.name)")
    }
}

/// Centred miniature panel with icon, name, tagline and version. Closes with Esc or a click outside.
struct AboutOverlay: View {
    @Bindable var presenter = AboutPresenter.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if presenter.visible {
                Color.black.opacity(scheme == .dark ? 0.35 : 0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                card.transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: presenter.visible)
        .allowsHitTesting(presenter.visible)
    }

    private var card: some View {
        let palette = WindowPalette(scheme: scheme)
        return VStack(spacing: 6) {
            Image(nsImage: AppInfo.icon).resizable().interpolation(.high)
                .frame(width: 72, height: 72).accessibilityHidden(true)
            Text(AppInfo.name).uiFont(2, bold: true).foregroundStyle(palette.textPrimary)
                .padding(.top, 4)
            Text(AppInfo.tagline).uiFont(-1).foregroundStyle(palette.textSecondary)
            Text("Versión \(AppInfo.version)").uiFont(-2).monospacedDigit()
                .foregroundStyle(palette.textTertiary).textSelection(.enabled)
            // Esc closes the panel while the window is key.
            Button("Cerrar", action: close).keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(width: 240)
        .background(palette.elevated, in: .rect(cornerRadius: DesignTokens.popoverRadius))
        .overlay { RoundedRectangle(cornerRadius: DesignTokens.popoverRadius).strokeBorder(palette.border) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Acerca de \(AppInfo.name). \(AppInfo.tagline). Versión \(AppInfo.version)")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Cerrar") { close() }
    }

    private func close() { presenter.visible = false }
}
