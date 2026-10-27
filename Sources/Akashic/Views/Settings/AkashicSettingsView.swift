import SwiftUI

enum AkashicSettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case importExport = "Import/Export"

    var id: String { rawValue }
}

struct AkashicSettingsView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var settings: AkashicSettingsStore
    let onDone: () -> Void

    @State private var tab: AkashicSettingsTab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            ScrollView {
                tabContent
                    .padding(14)
            }
            .akashicScrollers()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SETTINGS")
                    .font(AkashicSettingsChrome.font(14, bold: true))
                    .foregroundStyle(Color.white)
                Text("Appearance and data")
                    .font(AkashicSettingsChrome.font(10, bold: true))
                    .foregroundStyle(AkashicSettingsChrome.label)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.black.opacity(0.35))
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(AkashicSettingsTab.allCases) { candidate in
                tabButton(candidate)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
    }

    private func tabButton(_ candidate: AkashicSettingsTab) -> some View {
        let selected = tab == candidate
        return Button {
            tab = candidate
        } label: {
            Text(candidate.rawValue.uppercased())
                .font(AkashicSettingsChrome.font(10, bold: true))
                .tracking(1.2)
                .foregroundStyle(selected ? AkashicSettingsChrome.accent : AkashicSettingsChrome.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Rectangle().fill(Color.black.opacity(selected ? 0.45 : 0.2)))
                .overlay(
                    Rectangle()
                        .stroke(
                            AkashicSettingsChrome.accent.opacity(selected ? 0.9 : 0.25),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .appearance:
            appearanceTab
        case .importExport:
            importExportTab
        }
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("MENU BAR")
            menuBarIconGrid

            sectionTitle("MAIN WINDOW HEADER")
            toggleRow(
                title: "Show system information",
                subtitle: "Disk, memory, CPU, and agent usage in the header",
                isOn: $settings.showSystemInformation
            )
            toggleRow(
                title: "Show Akashic logo",
                subtitle: "Wildstyle wordmark in the center header slot",
                isOn: $settings.showAkashicLogo
            )
            toggleRow(
                title: "Show in Dock and app switcher",
                subtitle: "Dock icon and Cmd-Tab entry (macOS ties switcher to Dock presence)",
                isOn: $settings.showInDockAndAppSwitcher
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuBarIconGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 88), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(AkashicSettingsStore.menuBarSymbolChoices, id: \.self) { symbol in
                let selected = settings.menuBarSymbolName == symbol
                Button {
                    settings.menuBarSymbolName = symbol
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(selected ? AkashicSettingsChrome.accent : AkashicSettingsChrome.label)
                        Text(symbol)
                            .font(AkashicSettingsChrome.font(8))
                            .foregroundStyle(AkashicSettingsChrome.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(Color.black.opacity(selected ? 0.5 : 0.25)))
                    .overlay(
                        Rectangle()
                            .stroke(
                                AkashicSettingsChrome.accent.opacity(selected ? 1 : 0.35),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var importExportTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("IMPORT")
            Text("Both import actions replace every todo in your local database.")
                .font(AkashicSettingsChrome.font(10))
                .foregroundStyle(AkashicSettingsChrome.label)
            HStack(spacing: 10) {
                AkashicSettingsButton(title: "IMPORT DEMO SEED…", action: importBundledSeed)
                AkashicSettingsButton(title: "IMPORT JSON…", action: importJSON)
            }

            sectionTitle("EXPORT")
            Text("Save todos as seed JSON (same shape as import).")
                .font(AkashicSettingsChrome.font(10))
                .foregroundStyle(AkashicSettingsChrome.label)
            AkashicSettingsButton(title: "EXPORT TO JSON…", action: exportJSON)

            if let message = store.lastImportMessage {
                Text(message)
                    .font(AkashicSettingsChrome.font(10))
                    .foregroundStyle(AkashicSettingsChrome.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AkashicSettingsChrome.font(10, bold: true))
            .tracking(1.5)
            .foregroundStyle(AkashicSettingsChrome.label)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AkashicSettingsChrome.font(11, bold: true))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(AkashicSettingsChrome.font(9))
                    .foregroundStyle(AkashicSettingsChrome.label)
            }
        }
        .toggleStyle(.checkbox)
        .tint(AkashicSettingsChrome.accent)
    }

    private var footer: some View {
        HStack {
            Text("ESC TO CLOSE  ·  DRAG BACKGROUND TO MOVE")
                .font(AkashicSettingsChrome.font(9))
                .foregroundStyle(AkashicSettingsChrome.label)
            Spacer()
            AkashicSettingsButton(title: "DONE", action: onDone)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
    }

    private func importBundledSeed() {
        guard AkashicImportConfirmations.confirmReplaceWithBundledSeed() == .confirmed else { return }
        store.importSeedFromBundle(replaceExisting: true)
    }

    private func importJSON() {
        guard AkashicImportConfirmations.confirmReplaceWithJSONFile() == .confirmed else { return }
        guard let url = AkashicJSONImportPanel.pickFileURL() else { return }
        store.importSeedFromFile(url: url)
    }

    private func exportJSON() {
        guard let url = AkashicJSONExportPanel.pickSaveURL() else { return }
        do {
            let data = try store.exportSeedJSON()
            try data.write(to: url, options: .atomic)
            store.lastImportMessage = "Exported \(store.todos.count) todos to \(url.lastPathComponent)."
        } catch {
            store.lastImportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
