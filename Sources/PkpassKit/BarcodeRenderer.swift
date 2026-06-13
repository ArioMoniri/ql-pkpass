//
//  BarcodeRenderer.swift
//  PkpassKit
//
//  Renders a pass's barcode into a crisp PNG using Core Image's built-in
//  generators. No special entitlements are required, so it works inside the
//  sandboxed Quick Look extension.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

public enum BarcodeRenderer {

    /// Renders the given barcode to PNG data, scaled up for a sharp preview.
    /// - Returns: PNG bytes, or `nil` if the format/message can't be rendered.
    public static func pngData(for barcode: PassBarcode, targetSize: CGFloat = 720) -> Data? {
        guard let message = barcode.message, !message.isEmpty else { return nil }
        guard let base = ciImage(format: barcode.format, message: message, encoding: barcode.messageEncoding) else {
            return nil
        }

        let extent = base.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // Scale with an integer factor where possible to keep edges crisp.
        let factor = max(1, (targetSize / max(extent.width, extent.height)).rounded(.down))
        let scaled = base.transformed(by: CGAffineTransform(scaleX: factor, y: factor))

        // Use the CPU renderer: a sandboxed Quick Look extension can stall on
        // GPU/Metal initialisation, and a barcode is tiny so software is instant.
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Core Image generation

    private static func ciImage(format: String?, message: String, encoding: String?) -> CIImage? {
        let stringEncoding: String.Encoding = (encoding == "utf-8" || encoding == "UTF-8") ? .utf8 : .isoLatin1
        let data = message.data(using: stringEncoding) ?? Data(message.utf8)

        switch format {
        case "PKBarcodeFormatQR":
            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            filter.correctionLevel = "M"
            return filter.outputImage

        case "PKBarcodeFormatPDF417":
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = data
            return filter.outputImage

        case "PKBarcodeFormatAztec":
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = data
            return filter.outputImage

        case "PKBarcodeFormatCode128":
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            filter.quietSpace = 2
            return filter.outputImage

        default:
            // Unknown format — try QR as a sensible default.
            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            filter.correctionLevel = "M"
            return filter.outputImage
        }
    }
}
