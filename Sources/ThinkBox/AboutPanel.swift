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
        let side = 256
        guard let source = icon.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let alpha = pixels[index + 3]
                let luminance = (Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])) / 3
                let ink = alpha > 128 && luminance < 110
                // Keep only the glyph: opaque black, everything else transparent.
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0
                pixels[index + 3] = ink ? 255 : 0
                if ink { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX > minX, maxY > minY, let masked = context.makeImage() else { return nil }
        // Square crop centred on the glyph, so it sits in the middle of the button.
        let width = maxX - minX + 1, height = maxY - minY + 1
        let extent = max(width, height)
        // Loop rows are memory rows, which are the image's rows top-down.
        let crop = CGRect(x: minX - (extent - width) / 2, y: minY - (extent - height) / 2,
                          width: extent, height: extent)
        guard let cropped = masked.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: cropped, size: NSSize(width: 16, height: 16))
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
                    .frame(width: 17, height: 17)
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
