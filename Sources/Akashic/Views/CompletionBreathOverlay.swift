import SwiftUI

/// Soft border-origin glow when a todo is marked complete (single pulse, tri-color cycle).
struct CompletionBreathOverlay: View {
    var celebrationID: UUID?

    @State private var pulse: CGFloat = 0
    @State private var colorPhase: CGFloat = 0
    @State private var playingID: UUID?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { _ in
            NeonWindowShellShape()
                .inset(by: -pulse * 6)
                .stroke(completionGlowColor, lineWidth: 14 + pulse * 32)
                .blur(radius: 22 + pulse * 48)
        }
        .opacity(pulse > 0.001 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: celebrationID) { _, newID in
            guard let newID, newID != playingID else { return }
            startPlayback(id: newID)
        }
    }

    private var completionGlowColor: Color {
        switch colorPhase {
        case ..<0.34:
            return CyberpunkTheme.neonCyan
        case ..<0.67:
            return CyberpunkTheme.neonGreen
        default:
            return CyberpunkTheme.neonRed
        }
    }

    private func startPlayback(id: UUID) {
        playbackTask?.cancel()
        playingID = id
        pulse = 0
        colorPhase = 0

        playbackTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.42)) {
                pulse = 1
            }
            withAnimation(.linear(duration: 0.42)) {
                colorPhase = 1
            }
            try? await Task.sleep(for: .milliseconds(450))
            pulse = 0
            colorPhase = 0
            if playingID == id {
                playingID = nil
            }
        }
    }
}
