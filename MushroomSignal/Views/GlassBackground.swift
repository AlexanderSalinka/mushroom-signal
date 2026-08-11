import SwiftUI
import AppKit
import MushroomSignalCore

/// A translucent, green-tinted glass background for the app's main screens — lets the real
/// desktop wallpaper show through behind the window, tinted with forest green.
///
/// SwiftUI's `.background(.ultraThinMaterial)` alone is NOT enough for this: on macOS it
/// defaults to blending with content *inside* the window, and since there's nothing behind
/// it in the view hierarchy it just renders as a flat tinted fill — no real desktop
/// passthrough. True behind-window vibrancy needs an `NSVisualEffectView` with
/// `blendingMode = .behindWindow`, plus the window itself set non-opaque — neither of which
/// SwiftUI's `Material` API exposes, hence the AppKit interop below.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Configures the hosting `NSWindow` to be non-opaque so `VisualEffectBackground`'s
/// behind-window blending actually reaches the real desktop instead of a window-manager-
/// filled opaque backdrop. Attach once, near the root of the view hierarchy.
struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func mushroomGlassBackground() -> some View {
        background(
            ZStack {
                VisualEffectBackground()
                DesignSystem.Colors.forestDeep.opacity(0.25)
                CanopyLightView()
                    .opacity(DesignSystem.canopyLightIntensity)
            }
        )
    }
}
