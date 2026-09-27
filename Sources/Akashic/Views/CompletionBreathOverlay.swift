import SwiftUI

/// Border-origin cyan pulse when a todo is marked complete (no center fill).
struct CompletionBreathOverlay: View {
    var celebrationID: UUID?

    @State private var breath: CGFloat = 0
    @State private var playingID: UUID?
    @State private var playbackTask: Task<Void, Never>?

    private let borderColor = CyberpunkTheme.neonCyan

    var body: some View {
        GeometryReader { _ in
            ZStack {
                borderRing(inset: 0, lineWidth: 1 + breath * 2.5)
                borderRing(inset: 0, lineWidth: 5 + breath * 10)
                    .blur(radius: 3 + breath * 14)
                borderRing(inset: 2 + breath * 10, lineWidth: 1.5 + breath * 2)
                borderRing(inset: 6 + breath * 18, lineWidth: 1 + breath * 1.5)
                    .blur(radius: 1 + breath * 4)
            }
        }
        .opacity(breath > 0.001 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: celebrationID) { _, newID in
            guard let newID, newID != playingID else { return }
            startPlayback(id: newID)
        }
    }

    private func borderRing(inset: CGFloat, lineWidth: CGFloat) -> some View {
        NeonWindowShellShape()
            .inset(by: inset)
            .stroke(borderColor, lineWidth: lineWidth)
    }

    private func startPlayback(id: UUID) {
        playbackTask?.cancel()
        playingID = id
        breath = 0

        playbackTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.22).repeatCount(2, autoreverses: true)) {
                breath = 1
            }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.08)) {
                breath = 0
            }
            try? await Task.sleep(for: .milliseconds(90))
            if playingID == id {
                playingID = nil
            }
        }
    }
}
