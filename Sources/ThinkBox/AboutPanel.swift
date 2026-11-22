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
}

/// Small toolbar button showing the app icon. Opens the «Acerca de» panel.
struct AboutButton: View {
    var body: some View {
        Button { AboutPresenter.shared.visible = true } label: {
            Image(nsImage: AppInfo.icon).resizable().interpolation(.high).frame(width: 18, height: 18)
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
            Text(AppInfo.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .padding(.top, 4)
            Text(AppInfo.tagline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            Text("Versión \(AppInfo.version)").font(.system(size: 11)).monospacedDigit()
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
