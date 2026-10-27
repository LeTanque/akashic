import AppKit

enum AkashicUnsavedChangesConfirmations {
    static func confirm() -> UnsavedChangesChoice {
        let alert = NSAlert()
        alert.messageText = "Save changes?"
        alert.informativeText = "This todo has unsaved changes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}
