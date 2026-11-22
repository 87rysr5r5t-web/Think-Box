import AppKit
import SwiftUI

/// Arc-style colour for the window chrome: tints the side panels (navigation and inspector) and
/// the toolbar strip, with an optional film grain. Editor, list and preview keep the palette.
struct ChromeTintOptions: Codable, Equatable {
    var enabled = false
    /// Position on the colour wheel: hue is the angle, saturation the distance from the centre.
    var hue = 0.58
    var saturation = 0.45
    /// How much of the colour shows over the panel surface.
    var intensity = 0.5
    /// Film grain over the tinted surfaces, 0 (none) to 1.
    var noise = 0.0

    /// Arc-like starting points.
    static let presets: [(hue: Double, saturation: Double)] = [
        (0.58, 0.45), (0.66, 0.40), (0.75, 0.35), (0.88, 0.35),
        (0.00, 0.40), (0.07, 0.50), (0.13, 0.45), (0.30, 0.35), (0.45, 0.40),
    ]

    func color(dark: Bool) -> Color {
        Color(hue: hue, saturation: saturation, brightness: dark ? 0.55 : 0.92)
    }
}

/// The surface of a tinted area: palette surface, the chosen colour over it and the grain.
struct TintedSurface: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WindowPalette(scheme: scheme)
        let tint = settings.tint
        ZStack {
            palette.surface
            if tint.enabled {
                tint.color(dark: scheme == .dark).opacity(tint.intensity * (scheme == .dark ? 0.45 : 0.6))
                if tint.noise > 0 {
                    Rectangle()
                        .fill(ImagePaint(image: Image(nsImage: Grain.image), scale: 0.5))
                        .opacity(tint.noise * (scheme == .dark ? 0.22 : 0.3))
                        .blendMode(scheme == .dark ? .plusLighter : .multiply)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension TintedSurface {
    /// The same surface as a repeating tile, for places that take a single paint (the full
    /// screen toolbar): palette surface, colour and grain baked into one image.
    @MainActor static func paint(_ tint: ChromeTintOptions, dark: Bool) -> ImagePaint {
        let side: CGFloat = 128
        let surface = dark ? NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x15 / 255, alpha: 1)
            : NSColor(srgbRed: 0xED / 255, green: 0xED / 255, blue: 0xEB / 255, alpha: 1)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(surface.cgColor)
            context.fill(rect)
            if tint.enabled {
                let color = NSColor(Color(hue: tint.hue, saturation: tint.saturation, brightness: dark ? 0.55 : 0.92))
                context.setFillColor(color.withAlphaComponent(tint.intensity * (dark ? 0.45 : 0.6)).cgColor)
                context.fill(rect)
                if tint.noise > 0, let grain = Grain.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.setBlendMode(dark ? .plusLighter : .multiply)
                    context.setAlpha(tint.noise * (dark ? 0.22 : 0.3))
                    context.draw(grain, in: rect)
                }
            }
            return true
        }
        return ImagePaint(image: Image(nsImage: image), scale: 0.5)
    }
}

/// A fixed tile of monochrome noise, generated once.
private enum Grain {
    @MainActor static let image: NSImage = {
        let side = 128
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            let value = UInt8.random(in: 0...255, using: &generator)
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
            bytes[index * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }()
}

/// Toolbar button that opens the colour panel.
struct ChromeTintButton: View {
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { Label("Color de la ventana", line: "paintpalette") }
            .buttonStyle(.automatic)
            .help("Color de los paneles laterales y de la barra de herramientas")
            .popover(isPresented: $open, arrowEdge: .bottom) { ChromeTintPanel() }
    }
}

/// The colour panel: presets, a wheel with a draggable dot, intensity and grain.
struct ChromeTintPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    private let wheel: CGFloat = 180

    var body: some View {
        @Bindable var settings = settings
        let palette = WindowPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Color de la ventana").uiFont(0, bold: true)
                Spacer()
                Toggle("Activar color", isOn: $settings.tint.enabled).toggleStyle(.switch).labelsHidden()
                    .controlSize(.small)
            }
            colorWheel.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                ForEach(Array(ChromeTintOptions.presets.enumerated()), id: \.offset) { _, preset in
                    let chosen = abs(settings.tint.hue - preset.hue) < 0.005 && abs(settings.tint.saturation - preset.saturation) < 0.005
                    Button {
                        settings.tint.hue = preset.hue
                        settings.tint.saturation = preset.saturation
                        settings.tint.enabled = true
                    } label: {
                        Circle().fill(Color(hue: preset.hue, saturation: preset.saturation, brightness: scheme == .dark ? 0.6 : 0.9))
                            .frame(width: 18, height: 18)
                            .overlay { Circle().strokeBorder(chosen ? palette.textPrimary : palette.border, lineWidth: chosen ? 2 : 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color predefinido")
                }
            }
            slider("Intensidad", value: $settings.tint.intensity)
            slider("Ruido", value: $settings.tint.noise)
        }
        .padding(16)
        .frame(width: 260)
        .disabled(false)
    }

    /// Hue around the circle, saturation towards the edge; drag the dot to choose.
    private var colorWheel: some View {
        let tint = settings.tint
        let radius = wheel / 2
        let angle = tint.hue * 2 * .pi
        let knob = CGPoint(x: radius + cos(angle) * tint.saturation * radius,
                           y: radius - sin(angle) * tint.saturation * radius)
        return ZStack {
            Circle().fill(AngularGradient(
                colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                    Color(hue: 1 - $0, saturation: 1, brightness: scheme == .dark ? 0.75 : 0.95)
                },
                center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
            Circle().fill(RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: radius))
            Circle()
                .fill(tint.color(dark: scheme == .dark))
                .frame(width: 20, height: 20)
                .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .position(knob)
        }
        .frame(width: wheel, height: wheel)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - radius
            let dy = radius - value.location.y
            var hue = atan2(dy, dx) / (2 * .pi)
            if hue < 0 { hue += 1 }
            settings.tint.hue = hue
            settings.tint.saturation = min(1, sqrt(dx * dx + dy * dy) / radius)
            settings.tint.enabled = true
        })
        .accessibilityElement()
        .accessibilityLabel("Rueda de color")
        .accessibilityValue("Tono \(Int(tint.hue * 360)) grados, saturación \(Int(tint.saturation * 100)) %")
        .accessibilityAdjustableAction { direction in
            settings.tint.hue = (settings.tint.hue + (direction == .increment ? 1.0 / 36 : -1.0 / 36) + 1)
                .truncatingRemainder(dividingBy: 1)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).uiFont(-1)
                Spacer()
                Text("\(Int(value.wrappedValue * 100)) %").uiFont(-2).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1).controlSize(.small).accessibilityLabel(title)
        }
    }
}
