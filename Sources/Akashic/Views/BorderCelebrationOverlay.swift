import SwiftUI

/// Border-origin glow for todo completion (cyan) and deletion (orange → cyan).
struct BorderCelebrationOverlay: View {
    var completionCelebrationID: UUID?
    var deletionCelebrationID: UUID?

    @State private var pulse: CGFloat = 0
    @State private var orangeMix: CGFloat = 0
    @State private var playingCompletionID: UUID?
    @State private var playingDeletionID: UUID?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { _ in
            NeonWindowShellShape()
                .inset(by: -pulse * 6)
                .stroke(borderGlowColor, lineWidth: 14 + pulse * 32)
                .blur(radius: 22 + pulse * 48)
        }
        .opacity(pulse > 0.001 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: completionCelebrationID) { _, newID in
            guard let newID, newID != playingCompletionID else { return }
            startCompletionPlayback(id: newID)
        }
        .onChange(of: deletionCelebrationID) { _, newID in
            guard let newID, newID != playingDeletionID else { return }
            startDeletionPlayback(id: newID)
        }
    }

    private var borderGlowColor: Color {
        Self.blend(CyberpunkTheme.neonCyan, CyberpunkTheme.neonOrange, amount: orangeMix)
    }

    private static func blend(_ cyan: Color, _ orange: Color, amount: CGFloat) -> Color {
        let t = min(max(amount, 0), 1)
        let u = 1 - t
        return Color(
            red: u * 0 + t * 1,
            green: u * (217 / 255) + t * (122 / 255),
            blue: u * 1 + t * (26 / 255)
        )
    }

    private func startCompletionPlayback(id: UUID) {
        playbackTask?.cancel()
        playingCompletionID = id
        playingDeletionID = nil
        pulse = 0
        orangeMix = 0

        playbackTask = Task { @MainActor in
            withAnimation(.easeIn(duration: 0.16)) {
                pulse = 1
            }
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(.easeOut(duration: 0.48)) {
                pulse = 0
            }
            try? await Task.sleep(for: .milliseconds(500))
            if playingCompletionID == id {
                playingCompletionID = nil
            }
        }
    }

    private func startDeletionPlayback(id: UUID) {
        playbackTask?.cancel()
        playingDeletionID = id
        playingCompletionID = nil
        pulse = 0
        orangeMix = 0

        playbackTask = Task { @MainActor in
            withAnimation(.easeIn(duration: 0.14)) {
                pulse = 1
                orangeMix = 1
            }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.easeOut(duration: 0.38)) {
                pulse = 0
                orangeMix = 0
            }
            try? await Task.sleep(for: .milliseconds(400))
            if playingDeletionID == id {
                playingDeletionID = nil
            }
        }
    }
}
