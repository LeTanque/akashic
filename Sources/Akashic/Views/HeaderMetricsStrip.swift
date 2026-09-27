import SwiftUI

/// Compact, display-only HUD in the main-window top header chrome
/// (`CyberHeaderStrip`, leading-aligned to the left of the wordmark).
/// Two rows: DISK/SYS/CPU machine stats, then Cursor $ + CM + OM + BOT. Not a side panel or
/// bottom inset; not shown in the menu-bar popover.
struct HeaderMetricsStrip: View {
    @StateObject private var live = LiveMetricsMonitor()
    @StateObject private var cursorQuota = CursorQuotaMonitor()

    var body: some View {
        let lines = MetricsStripText.make(
            diskFree: live.snapshot.diskFree,
            diskUsed: live.snapshot.diskUsed,
            sysUsed: live.snapshot.sysUsed,
            sysTotal: live.snapshot.sysTotal,
            cpuPercent: live.snapshot.cpuPercent,
            cursorIncludedRemainingUSD: cursorQuota.snapshot.cursorIncludedRemainingUSD,
            cursorBonusSpendUSD: cursorQuota.snapshot.cursorBonusSpendUSD,
            cursorModelsUsedPercent: cursorQuota.snapshot.cursorModelsUsedPercent,
            otherModelsUsedPercent: cursorQuota.snapshot.otherModelsUsedPercent,
            grokBotRemainingPercent: cursorQuota.snapshot.grokBotRemainingPercent
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
            row(rows.bottom)
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
