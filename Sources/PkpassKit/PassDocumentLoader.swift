//
//  PassDocumentLoader.swift
//  PkpassKit
//
//  Single entry point that sniffs the input and routes it to the right parser:
//  Apple `.pkpass` (a ZIP), Google Wallet JSON/JWT, or Samsung Wallet card JSON.
//  Both Quick Look extensions and the host app use this.
//

import Foundation

public enum PassDocumentLoader {

    /// Loads and renders a pass from a file URL (pkpass / Google / Samsung).
    public static func document(contentsOf url: URL) throws -> PkpassDocument {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > PkpassDocument.maxFileSize {
            throw MiniZipError.corrupted("file too large (\(size) bytes)")
        }
        let data = try Data(contentsOf: url)
        return try document(from: data)
    }

    /// Loads and renders a pass from in-memory bytes.
    public static func document(from data: Data) throws -> PkpassDocument {
        // Apple .pkpass is a ZIP — it starts with the local-file-header "PK\x03\x04".
        if looksLikeZip(data) {
            return try PkpassDocument(data: data)
        }

        // Otherwise treat as JSON and detect the wallet platform.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if SamsungWalletParser.matches(object) {
                return try SamsungWalletParser.makeDocument(from: data)
            }
            if GoogleWalletParser.matches(object) {
                return try GoogleWalletParser.makeDocument(from: data)
            }
        }

        // A bare JWT string (Google "Save to Google Wallet" token).
        if let doc = try? GoogleWalletParser.makeDocument(from: data) {
            return doc
        }

        // Fall back to the pkpass path so the user gets a meaningful error.
        return try PkpassDocument(data: data)
    }

    private static func looksLikeZip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = [UInt8](data.prefix(4))
        // PK\x03\x04 (local header), PK\x05\x06 (empty archive EOCD), PK\x07\x08.
        return prefix[0] == 0x50 && prefix[1] == 0x4B
            && (prefix[2] == 0x03 || prefix[2] == 0x05 || prefix[2] == 0x07)
    }
}
