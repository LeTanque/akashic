import AppKit

/// Dock icon and Cmd-Tab visibility (macOS ties Cmd-Tab to Dock presence).
enum AkashicActivationPolicy {
    static func apply(showInDockAndAppSwitcher: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDockAndAppSwitcher ? .regular : .accessory
        // NSApp is nil in unit tests (no NSApplication); skip instead of crashing.
        guard let app = NSApp else { return }
        app.setActivationPolicy(policy)
    }
}
