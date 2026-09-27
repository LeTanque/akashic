import SwiftUI

/// Full-window “breathing” lens-flare reward when a todo is marked complete (overlay-style pulse).
struct CompletionBreathOverlay: View {
    var celebrationID: UUID?

    @State private var breath: CGFloat = 0
    @State private var fade: CGFloat = 1
    @State private var playingID: UUID?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.22 * fade),
                        CyberpunkTheme.neonCyan.opacity(0.35 * fade),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )
                .scaleEffect(0.88 + breath * 0.18)
                .blendMode(.screen)

                lensFlare(at: CGPoint(x: geo.size.width * 0.12, y: geo.size.height * 0.18), geo: geo)
                lensFlare(at: CGPoint(x: geo.size.width * 0.88, y: geo.size.height * 0.82), geo: geo)

                LinearGradient(
                    colors: [
                        CyberpunkTheme.neonCyan.opacity(0.45 * breath * fade),
                        Color.clear,
                        CyberpunkTheme.neonOrange.opacity(0.25 * breath * fade),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)

                NeonWindowShellShape()
                    .stroke(CyberpunkTheme.neonCyan.opacity(0.55 * breath * fade), lineWidth: 2 + breath * 3)
                    .blur(radius: 6 + breath * 10)
                    .blendMode(.screen)
            }
        }
        .opacity(fade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: celebrationID) { _, newID in
            guard let newID, newID != playingID else { return }
            startPlayback(id: newID)
        }
    }

    private func lensFlare(at center: CGPoint, geo: GeometryProxy) -> some View {
        let span = max(geo.size.width, geo.size.height)
        return RadialGradient(
            colors: [
                Color.white.opacity(0.5 * breath * fade),
                CyberpunkTheme.neonCyan.opacity(0.35 * breath * fade),
                Color.clear,
            ],
            center: UnitPoint(
                x: center.x / max(geo.size.width, 1),
                y: center.y / max(geo.size.height, 1)
            ),
            startRadius: 0,
            endRadius: span * 0.35
        )
        .scaleEffect(0.75 + breath * 0.45)
        .blendMode(.screen)
    }

    private func startPlayback(id: UUID) {
        playbackTask?.cancel()
        playingID = id
        breath = 0
        fade = 0

        playbackTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.12)) {
                fade = 1
            }
            try? await Task.sleep(for: .milliseconds(120))

            withAnimation(.easeInOut(duration: 0.52).repeatCount(3, autoreverses: true)) {
                breath = 1
            }
            try? await Task.sleep(for: .milliseconds(520 * 3 + 80))

            withAnimation(.easeOut(duration: 0.45)) {
                fade = 0
                breath = 0
            }
            try? await Task.sleep(for: .milliseconds(460))
            if playingID == id {
                playingID = nil
            }
        }
    }
}
