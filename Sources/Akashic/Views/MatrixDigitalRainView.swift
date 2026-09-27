import AppKit
import CoreText
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
        reduceMotion ? 1.0 / 6 : 1.0 / 60
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

    static let backgroundFill = NSColor(red: 0.01, green: 0.03, blue: 0.015, alpha: 1)
    static let dimGlyphFill = NSColor(red: 0, green: 0.12, blue: 0.04, alpha: 1)
    static let matrixGreenFill = NSColor(red: 0, green: 1, blue: 65 / 255, alpha: 1)
    static let headHighlightFill = NSColor(red: 0.92, green: 1, blue: 0.94, alpha: 1)
}

// MARK: - Glyph atlas (one-time text rasterization, fast per-frame mask fills)

private final class MatrixGlyphAtlas {
    static let shared = MatrixGlyphAtlas()

    let cellWidth: CGFloat
    let cellHeight: CGFloat
    private let masks: [CGImage]

    private init() {
        cellWidth = MatrixRainStyle.columnWidth
        cellHeight = MatrixRainStyle.rowHeight
        masks = MatrixRainStyle.glyphPool.map { character in
            Self.renderMask(for: character, cellWidth: cellWidth, cellHeight: cellHeight)
        }
    }

    func drawGlyph(
        in context: CGContext,
        poolIndex: Int,
        destRect: CGRect,
        fillColor: CGColor,
        alpha: CGFloat = 1
    ) {
        guard poolIndex >= 0, poolIndex < masks.count else { return }
        context.saveGState()
        if alpha < 0.999 {
            context.setAlpha(alpha)
        }
        context.clip(to: destRect, mask: masks[poolIndex])
        context.setFillColor(fillColor)
        context.fill(destRect)
        context.restoreGState()
    }

    private static func renderMask(for character: Character, cellWidth: CGFloat, cellHeight: CGFloat) -> CGImage {
        let pixelWidth = max(1, Int(ceil(cellWidth * 2)))
        let pixelHeight = max(1, Int(ceil(cellHeight * 2)))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return emptyMask(width: pixelWidth, height: pixelHeight)
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)

        let font = CTFontCreateWithName("Menlo" as CFString, MatrixRainStyle.fontSize * 2, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let attributed = CFAttributedStringCreate(nil, String(character) as CFString, attributes as CFDictionary)
        guard let attributed, let line = CTLineCreateWithAttributedString(attributed) else {
            return context.makeImage() ?? emptyMask(width: pixelWidth, height: pixelHeight)
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let x = (CGFloat(pixelWidth) - width) / 2
        let y = (CGFloat(pixelHeight) - (ascent + descent)) / 2 + descent
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)

        return context.makeImage() ?? emptyMask(width: pixelWidth, height: pixelHeight)
    }

    private static func emptyMask(width: Int, height: Int) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else {
            fatalError("Matrix glyph atlas could not allocate fallback mask")
        }
        return image
    }
}

// MARK: - Static dim grid (rebuilt only on layout changes)

private enum MatrixRainDimLayerRenderer {
    static func makeDimLayer(layout: MatrixRainLayout, atlas: MatrixGlyphAtlas) -> CGImage? {
        let pixelWidth = max(1, Int(ceil(layout.canvasSize.width)))
        let pixelHeight = max(1, Int(ceil(layout.canvasSize.height)))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Match SwiftUI Canvas top-left origin.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(MatrixRainStyle.backgroundFill.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        let dimColor = MatrixRainStyle.dimGlyphFill.cgColor
        for column in 0 ..< layout.columns {
            for row in 0 ..< layout.rows {
                let dest = layout.destRect(forColumn: column, row: row, atlas: atlas)
                atlas.drawGlyph(
                    in: context,
                    poolIndex: layout.glyphIndex(column: column, row: row),
                    destRect: dest,
                    fillColor: dimColor
                )
            }
        }
        return context.makeImage()
    }
}

private struct MatrixRainCanvas: View {
    let size: CGSize
    let time: TimeInterval
    let reduceMotion: Bool

    @State private var layout: MatrixRainLayout?
    @State private var dimLayer: CGImage?

    var body: some View {
        Canvas { context, canvasSize in
            guard let layout, layout.columns > 0, layout.rows > 0 else { return }

            let effectiveTime = reduceMotion ? 0 : time
            let atlas = MatrixGlyphAtlas.shared

            context.withCGContext { cgContext in
                if let dimLayer {
                    cgContext.draw(dimLayer, in: CGRect(origin: .zero, size: canvasSize))
                }

                let green = MatrixRainStyle.matrixGreenFill.cgColor
                let head = MatrixRainStyle.headHighlightFill.cgColor

                for column in 0 ..< layout.columns {
                    let headRow = layout.headRow(forColumn: column, time: effectiveTime)
                    let lastRow = min(layout.rows - 1, Int(floor(headRow)))
                    var firstRow = Int(floor(headRow - MatrixRainStyle.trailLength)) + 1
                    if firstRow < 0 { firstRow = 0 }
                    guard firstRow <= lastRow else { continue }

                    for row in firstRow ... lastRow {
                        let delta = headRow - Double(row)
                        let intensity = layout.trailIntensity(delta: delta)
                        guard intensity > 0.001 else { continue }

                        let dest = layout.destRect(forColumn: column, row: row, atlas: atlas)
                        let poolIndex = layout.glyphIndex(column: column, row: row)

                        if intensity > 0.92 {
                            atlas.drawGlyph(
                                in: cgContext,
                                poolIndex: poolIndex,
                                destRect: dest,
                                fillColor: head
                            )
                        } else {
                            let alpha = CGFloat(0.25 + intensity * 0.75)
                            atlas.drawGlyph(
                                in: cgContext,
                                poolIndex: poolIndex,
                                destRect: dest,
                                fillColor: green,
                                alpha: alpha
                            )
                        }
                    }
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
        let newLayout = MatrixRainLayout(size: newSize)
        layout = newLayout
        dimLayer = MatrixRainDimLayerRenderer.makeDimLayer(
            layout: newLayout,
            atlas: MatrixGlyphAtlas.shared
        )
    }
}

private struct MatrixRainLayout {
    let canvasSize: CGSize
    let columns: Int
    let rows: Int
    private let glyphIndices: [[Int]]
    private let columnPhases: [Double]
    private let columnSpeeds: [Double]

    init(size: CGSize) {
        canvasSize = size
        columns = max(1, Int(size.width / MatrixRainStyle.columnWidth))
        rows = max(1, Int(size.height / MatrixRainStyle.rowHeight))
        let poolCount = MatrixRainStyle.glyphPool.count

        var grid = [[Int]]()
        grid.reserveCapacity(columns)
        for column in 0 ..< columns {
            var columnIndices = [Int]()
            columnIndices.reserveCapacity(rows)
            for row in 0 ..< rows {
                let seed = column &* 31_415 &+ row &* 2_718
                columnIndices.append(abs(seed) % poolCount)
            }
            grid.append(columnIndices)
        }
        glyphIndices = grid

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

    func glyphIndex(column: Int, row: Int) -> Int {
        glyphIndices[column][row]
    }

    func destRect(forColumn column: Int, row: Int, atlas: MatrixGlyphAtlas) -> CGRect {
        CGRect(
            x: CGFloat(column) * MatrixRainStyle.columnWidth + 2,
            y: CGFloat(row) * MatrixRainStyle.rowHeight + 2,
            width: atlas.cellWidth,
            height: atlas.cellHeight
        )
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
