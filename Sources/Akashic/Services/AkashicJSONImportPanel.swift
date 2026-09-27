import AppKit
import UniformTypeIdentifiers

enum AkashicJSONImportPanel {
    static func pickFileURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Import seed JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
