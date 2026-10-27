import AppKit
import UniformTypeIdentifiers

enum AkashicJSONExportPanel {
    static func pickSaveURL(suggestedName: String = "akashic-todos.json") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.message = "Export todos as JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
