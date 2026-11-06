import AkashicCore
import SwiftUI

/// Main window root: cyberpunk unlock / first-run wizard, or full app when `vault` is `.ready`.
struct AkashicVaultRootView: View {
    @ObservedObject var root: AkashicRootModel

    var body: some View {
        Group {
            switch root.vault.presentation {
            case .loading:
                CyberpunkLoadingView()
            case .firstRun:
                AkashicFirstRunView(vault: root.vault)
            case .unlock:
                AkashicUnlockView(vault: root.vault)
            case .ready:
                if let todo = root.vault.todoStore, let note = root.vault.noteStore {
                    MainWindowView()
                        .environmentObject(root)
                        .environmentObject(todo)
                        .environmentObject(note)
                        .environmentObject(root.editorSession)
                        .environmentObject(root.noteEditorSession)
                        .environmentObject(root.textZoom)
                        .environmentObject(root.sidebarVisibility)
                        .environmentObject(root.mainSectionVisibility)
                        .environmentObject(root.settings)
                        .akashicTextZoom(root.textZoom)
                } else {
                    CyberpunkLoadingView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CyberpunkTheme.background)
    }
}

private struct CyberpunkLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("AKASHIC")
                .font(.custom("Menlo-Bold", size: 22))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            ProgressView()
                .controlSize(.regular)
                .tint(CyberpunkTheme.neonCyan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
