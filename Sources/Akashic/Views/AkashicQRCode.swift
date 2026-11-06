import AppKit
import CoreImage
import Foundation
import SwiftUI

enum AkashicQRCode {
    static func image(from string: String, dimension: CGFloat = 160) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: transformed)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

struct AkashicQRImageView: View {
    let payload: String
    var dimension: CGFloat = 160

    var body: some View {
        Group {
            if let ns = AkashicQRCode.image(from: payload, dimension: dimension) {
                Image(nsImage: ns)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: dimension, height: dimension)
            } else {
                Text("QR unavailable")
                    .font(.caption)
                    .foregroundStyle(CyberpunkTheme.readableMutedCyan)
            }
        }
    }
}
