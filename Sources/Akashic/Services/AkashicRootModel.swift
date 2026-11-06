import AkashicCore
import Combine
import Foundation
import SwiftUI

/// Top-level app state: vault, sessions, and settings (stores come from the vault when unlocked).
@MainActor
final class AkashicRootModel: ObservableObject {
    let api = AkashicAPIService()
    let vault: AkashicVaultController
    let settings = AkashicSettingsStore()
    let textZoom = TextZoomStore()
    let sidebarVisibility = SidebarVisibilityStore()
    let mainSectionVisibility = MainSectionVisibilityStore()
    let editorSession = TodoEditorSession()
    let noteEditorSession = NoteEditorSession()

    private var vaultForward: AnyCancellable?

    init() {
        vault = AkashicVaultController(apiService: api)
        vaultForward = vault.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
