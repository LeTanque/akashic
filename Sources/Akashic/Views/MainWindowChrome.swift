import AppKit
import SwiftUI

/// Configures the main Akashic document window: no title bar, no traffic lights, opaque black fill.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            configureMainWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureMainWindow(for: nsView)
        }
    }

    private func configureMainWindow(for view: NSView) {
        guard let window = view.window, window.title == "Akashic" else { return }

        // SwiftUI / NavigationSplitView may attach a toolbar with a sidebar toggle — strip it every pass.
        window.toolbar = nil

        let token = ObjectIdentifier(window)
        guard !MainWindowChromeState.configured.contains(token) else { return }
        MainWindowChromeState.configured.insert(token)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor.black
        window.isOpaque = true
        window.contentView?.clipsToBounds = false

        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
    }
}

private enum MainWindowChromeState {
    static var configured = Set<ObjectIdentifier>()
}

/// Drag the window from the header strip (`performDrag` on mouse down).
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
