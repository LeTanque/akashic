import SwiftUI

/// Compact, display-only HUD in the main-window top header chrome
/// (`CyberHeaderStrip`, leading-aligned to the left of the wordmark).
/// Three rows: DISK/SYS, CPU/CA (+ BOT), CM/OM Cursor quota. Not a side panel or
/// bottom inset; not shown in the menu-bar popover.
struct HeaderMetricsStrip: View {
    @StateObject private var live = LiveMetricsMonitor()
    @StateObject private var cursorQuota = CursorQuotaMonitor()
    @ObservedObject private var agents = AgentMetricsStore.shared

    var body: some View {
        let lines = MetricsStripText.make(
            diskFree: live.snapshot.diskFree,
            sysUsed: live.snapshot.sysUsed,
            sysTotal: live.snapshot.sysTotal,
            cpuPercent: live.snapshot.cpuPercent,
            cloudAgents: agents.displayedCloudAgentCount(),
            bots: agents.displayedBotCount(),
            cursorModelsUsedPercent: cursorQuota.snapshot.cursorModelsUsedPercent,
            otherModelsUsedPercent: cursorQuota.snapshot.otherModelsUsedPercent
        )

        stacked(lines.full)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.spoken)
            .allowsHitTesting(false)
            .onAppear {
                live.start()
                cursorQuota.start()
            }
            .onDisappear {
                live.stop()
                cursorQuota.stop()
            }
    }

    private func stacked(_ rows: MetricsStripText.Rows) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            row(rows.top)
            row(rows.middle)
            row(rows.quota)
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
