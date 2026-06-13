//
//  ThumbnailProvider.swift
//  PkpassThumbnailExtension
//
//  Draws a card-style thumbnail for `.pkpass` files in Finder and Quick Look.
//

import QuickLookThumbnailing
import AppKit
import PkpassKit

final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let document = try PkpassDocument(contentsOf: request.fileURL)
            let renderer = PassThumbnailRenderer(document: document)
            let size = request.maximumSize

            let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
                renderer.draw(in: CGRect(origin: .zero, size: size))
                return true
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}
