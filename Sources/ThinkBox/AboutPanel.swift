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

    /// The icon's marks (the flower and the corner dot) without the white tile, as a template
    /// image so the toolbar tints it like every other icon. Dark pixels of the tile become opaque
    /// and light ones transparent, then the result is cropped to the marks so they fill the
    /// button. Read from the bundle's .icns at a fixed 512 px so it never depends on macOS caches.
    @MainActor static let badge: NSImage? = {
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
        // Keep only the ink: alpha from darkness, inside the opaque tile; colour black.
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                let alpha = Int(pixels[i + 3])
                var ink = 0
                if alpha > 200 {
                    // Un-premultiply, then luminance; anything lighter than mid-grey fades out.
                    let r = Int(pixels[i]) * 255 / alpha, g = Int(pixels[i + 1]) * 255 / alpha, b = Int(pixels[i + 2]) * 255 / alpha
                    let luma = (r * 299 + g * 587 + b * 114) / 1000
                    ink = max(0, min(255, (200 - luma) * 255 / 120))
                }
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = UInt8(ink)
                if ink > 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX > minX, maxY > minY, let full = context.makeImage() else { return nil }
        let extent = max(maxX - minX, maxY - minY) + 9
        let crop = CGRect(x: (minX + maxX + 1 - extent) / 2, y: (minY + maxY + 1 - extent) / 2, width: extent, height: extent)
        guard let marks = full.cropping(to: crop) else { return nil }
        let image = NSImage(cgImage: marks, size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()
}

/// Small toolbar button showing the app icon. Opens the «Acerca de» panel.
struct AboutButton: View {
    var body: some View {
        Button { AboutPresenter.shared.visible = true } label: {
            Label {
                Text("Acerca de \(AppInfo.name)")
            } icon: {
                if let badge = AppInfo.badge {
                    Image(nsImage: badge).renderingMode(.template)
                        .resizable().interpolation(.high).frame(width: 16, height: 16)
                } else {
                    Image(nsImage: AppInfo.icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                }
            }
        }
        .labelStyle(.iconOnly)
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
