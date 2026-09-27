import SwiftUI

/// Stationary Matrix-style glyph grid with a downward illumination wave (Nebuchadnezzar monitor).
struct MatrixDigitalRainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { timeline in
                MatrixRainCanvas(
                    size: geometry.size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    reduceMotion: reduceMotion
                )
            }
        }
        .background(MatrixRainStyle.background)
    }

    private var frameInterval: TimeInterval {
        reduceMotion ? 1.0 / 4 : 1.0 / 30
    }
}

private enum MatrixRainStyle {
    static let background = Color(red: 0.01, green: 0.03, blue: 0.015)
    static let matrixGreen = Color(red: 0, green: 1, blue: 65 / 255)
    static let dimGlyph = Color(red: 0, green: 0.12, blue: 0.04)
    static let headHighlight = Color(red: 0.92, green: 1, blue: 0.94)

    static let fontSize: CGFloat = 14
    static let columnWidth: CGFloat = fontSize * 0.62
    static let rowHeight: CGFloat = fontSize * 1.12
    static let trailLength: Double = 18
    static let trailDecay: Double = 0.38

    /// Half-width katakana, digits, and sparse Latin (Matrix-style glyph soup).
    static let glyphPool: [Character] = Array(
        "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )
}

private struct MatrixRainCanvas: View {
    let size: CGSize
    let time: TimeInterval
    let reduceMotion: Bool

    @State private var layout: MatrixRainLayout?

    var body: some View {
        Canvas { context, canvasSize in
            guard let layout, layout.columns > 0, layout.rows > 0 else { return }

            let effectiveTime = reduceMotion ? 0 : time
            let font = Font.system(size: MatrixRainStyle.fontSize, design: .monospaced)

            for column in 0 ..< layout.columns {
                let headRow = layout.headRow(forColumn: column, time: effectiveTime)
                for row in 0 ..< layout.rows {
                    let delta = headRow - Double(row)
                    let intensity = layout.trailIntensity(delta: delta)
                    let color = layout.color(forIntensity: intensity)
                    let glyph = layout.glyph(column: column, row: row)
                    let point = CGPoint(
                        x: CGFloat(column) * MatrixRainStyle.columnWidth + 2,
                        y: CGFloat(row) * MatrixRainStyle.rowHeight + 2
                    )
                    context.draw(
                        Text(String(glyph))
                            .font(font)
                            .foregroundColor(color),
                        at: point,
                        anchor: .topLeading
                    )
                }
            }
        }
        .onAppear { refreshLayoutIfNeeded(for: size) }
        .onChange(of: size) { _, newSize in
            refreshLayoutIfNeeded(for: newSize)
        }
    }

    private func refreshLayoutIfNeeded(for newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        if layout?.matches(size: newSize) == true { return }
        layout = MatrixRainLayout(size: newSize)
    }
}

private struct MatrixRainLayout {
    let canvasSize: CGSize
    let columns: Int
    let rows: Int
    private let glyphs: [[Character]]
    private let columnPhases: [Double]
    private let columnSpeeds: [Double]

    init(size: CGSize) {
        canvasSize = size
        columns = max(1, Int(size.width / MatrixRainStyle.columnWidth))
        rows = max(1, Int(size.height / MatrixRainStyle.rowHeight))
        let pool = MatrixRainStyle.glyphPool

        var grid = [[Character]]()
        grid.reserveCapacity(columns)
        for column in 0 ..< columns {
            var columnGlyphs = [Character]()
            columnGlyphs.reserveCapacity(rows)
            for row in 0 ..< rows {
                let seed = column &* 31_415 &+ row &* 2_718
                columnGlyphs.append(pool[abs(seed) % pool.count])
            }
            grid.append(columnGlyphs)
        }
        glyphs = grid

        var phases = [Double]()
        var speeds = [Double]()
        phases.reserveCapacity(columns)
        speeds.reserveCapacity(columns)
        for column in 0 ..< columns {
            var generator = SeededRandomNumberGenerator(seed: UInt64(column &* 9_001 &+ 42))
            phases.append(Double.random(in: 0 ..< Double(rows), using: &generator))
            speeds.append(Double.random(in: 2.4 ... 5.8, using: &generator))
        }
        columnPhases = phases
        columnSpeeds = speeds
    }

    func matches(size: CGSize) -> Bool {
        canvasSize == size
    }

    func glyph(column: Int, row: Int) -> Character {
        glyphs[column][row]
    }

    func headRow(forColumn column: Int, time: TimeInterval) -> Double {
        let cycle = Double(rows) + MatrixRainStyle.trailLength
        let raw = time * columnSpeeds[column] + columnPhases[column]
        let wrapped = raw.truncatingRemainder(dividingBy: cycle)
        return wrapped >= 0 ? wrapped : wrapped + cycle
    }

    func trailIntensity(delta: Double) -> Double {
        guard delta >= 0, delta < MatrixRainStyle.trailLength else { return 0 }
        return exp(-delta * MatrixRainStyle.trailDecay)
    }

    func color(forIntensity intensity: Double) -> Color {
        if intensity <= 0.001 {
            return MatrixRainStyle.dimGlyph
        }
        if intensity > 0.92 {
            return MatrixRainStyle.headHighlight
        }
        return MatrixRainStyle.matrixGreen.opacity(0.25 + intensity * 0.75)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
