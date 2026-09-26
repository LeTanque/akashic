import SwiftUI

/// Compact, display-only HUD in the main-window top header chrome
/// (`CyberHeaderStrip`, leading-aligned to the left of the wordmark).
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
            stacked(lines.full)
            stacked(lines.compact)
            stacked(lines.short)
            stacked(MetricsStripText.Rows(top: lines.minimal, bottom: ""))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.spoken)
        .allowsHitTesting(false)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private func stacked(_ rows: MetricsStripText.Rows) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            row(rows.top)
            if !rows.bottom.isEmpty {
                row(rows.bottom)
            }
        }
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AkashicFont.caption, weight: .medium, design: .monospaced))
            .foregroundStyle(CyberpunkTheme.neonCyan)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: true)
    }
}
