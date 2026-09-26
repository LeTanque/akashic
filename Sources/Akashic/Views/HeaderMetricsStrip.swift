import SwiftUI

/// Compact, display-only HUD in the main-window top header chrome
/// (`CyberHeaderStrip`, between the wordmark and +/import/close).
/// Not a side panel or bottom inset; not shown in the menu-bar popover.
struct HeaderMetricsStrip: View {
    @StateObject private var live = LiveMetricsMonitor()
    @ObservedObject private var agents = AgentMetricsStore.shared

    var body: some View {
        let lines = MetricsStripText.make(
            appRSS: live.snapshot.appRSS,
            sysUsed: live.snapshot.sysUsed,
            sysTotal: live.snapshot.sysTotal,
            cpuPercent: live.snapshot.cpuPercent,
            cloudAgents: agents.displayedCloudAgentCount(),
            bots: agents.displayedBotCount()
        )

        ViewThatFits(in: .horizontal) {
            strip(lines.full)
            strip(lines.compact)
            strip(lines.short)
            strip(lines.minimal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.full)
        .allowsHitTesting(false)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private func strip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AkashicFont.caption, weight: .medium, design: .monospaced))
            .foregroundStyle(CyberpunkTheme.neonCyan)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, 4)
    }
}
