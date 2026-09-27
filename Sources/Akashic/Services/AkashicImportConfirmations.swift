import AppKit

enum AkashicImportConfirmations {
    enum Choice {
        case confirmed
        case cancelled
    }

    static func confirmReplaceWithBundledSeed() -> Choice {
        confirmDestructiveImport(
            informativeText:
                "Importing the bundled demo seed deletes every todo in your local database and loads the sample list.",
            confirmButtonTitle: "Replace All Todos"
        )
    }

    static func confirmReplaceWithJSONFile() -> Choice {
        confirmDestructiveImport(
            informativeText:
                "Importing a JSON seed file deletes every todo in your local database and loads todos from the file you select.",
            confirmButtonTitle: "Choose JSON File…"
        )
    }

    private static func confirmDestructiveImport(
        informativeText: String,
        confirmButtonTitle: String
    ) -> Choice {
        let alert = NSAlert()
        alert.messageText = "Replace all todos?"
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .confirmed : .cancelled
    }
}
