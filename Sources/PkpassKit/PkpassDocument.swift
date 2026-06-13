//
//  PkpassDocument.swift
//  PkpassKit
//
//  High-level entry point: give it the bytes of a `.pkpass` file and it hands
//  back the decoded pass plus its images. This is the type both Quick Look
//  extensions talk to.
//

import Foundation

/// Errors thrown while interpreting a `.pkpass` document.
public enum PkpassError: Error, CustomStringConvertible, Sendable {
    case missingPassJSON
    case invalidPassJSON(String)

    public var description: String {
        switch self {
        case .missingPassJSON:
            return "The archive does not contain a pass.json file."
        case .invalidPassJSON(let detail):
            return "pass.json could not be decoded: \(detail)"
        }
    }
}

/// Where a parsed pass came from.
public enum PassSource: String, Sendable {
    case applePkpass
    case googleWallet
    case samsungWallet

    public var displayName: String {
        switch self {
        case .applePkpass: return "Apple Wallet"
        case .googleWallet: return "Google Wallet"
        case .samsungWallet: return "Samsung Wallet"
        }
    }

    public var rawLabel: String {
        switch self {
        case .applePkpass: return "Raw pass.json"
        case .googleWallet: return "Raw Google Wallet JSON"
        case .samsungWallet: return "Raw Samsung Wallet JSON"
        }
    }
}

/// A single entry inside the `.pkpass` archive (for the file listing).
public struct PkpassFile: Sendable, Equatable {
    public let name: String
    public let size: Int

    /// A human-readable byte size, e.g. "3.1 KB".
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// A fully parsed `.pkpass` document.
public struct PkpassDocument: Sendable {
    /// The decoded pass.json.
    public let pass: Pass
    /// Pretty-printed pass.json for the "raw" disclosure.
    public let rawPassJSON: String
    /// Every PNG image in the bundle, keyed by filename (e.g. `logo@2x.png`).
    public let images: [String: Data]
    /// Every entry inside the archive, sorted by name (for the file listing).
    public let files: [PkpassFile]
    /// Whether the archive carried a signature (a hint about authenticity).
    public let isSigned: Bool
    /// Which wallet platform this pass came from.
    public let source: PassSource

    /// Builds a document from already-parsed parts. Used by the Google/Samsung
    /// parsers, which synthesise a `Pass` from their own JSON.
    public init(
        pass: Pass,
        rawPassJSON: String,
        images: [String: Data],
        files: [PkpassFile],
        isSigned: Bool,
        source: PassSource
    ) {
        self.pass = pass
        self.rawPassJSON = rawPassJSON
        self.images = images
        self.files = files
        self.isSigned = isSigned
        self.source = source
    }

    /// Parses an Apple `.pkpass` document from in-memory bytes.
    public init(data: Data) throws {
        let entries = try MiniZip.entries(from: data)

        guard let passData = entries["pass.json"] else {
            throw PkpassError.missingPassJSON
        }

        do {
            self.pass = try JSONDecoder().decode(Pass.self, from: passData)
        } catch {
            throw PkpassError.invalidPassJSON(String(describing: error))
        }

        self.rawPassJSON = PkpassDocument.prettyPrint(passData)

        var collected: [String: Data] = [:]
        for (name, payload) in entries where name.lowercased().hasSuffix(".png") {
            collected[name] = payload
        }
        self.images = collected
        self.files = entries
            .map { PkpassFile(name: $0.key, size: $0.value.count) }
            .sorted { $0.name < $1.name }
        self.isSigned = entries["signature"] != nil
        self.source = .applePkpass
    }

    /// The largest `.pkpass` file we'll even attempt to read.
    public static let maxFileSize = 64 * 1024 * 1024

    /// Parses a document from a file URL.
    public init(contentsOf url: URL) throws {
        // A pass is a small bundle; refuse anything implausibly large up front.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > PkpassDocument.maxFileSize {
            throw MiniZipError.corrupted("file too large (\(size) bytes)")
        }
        // Read (don't memory-map) so a truncated/removed backing file surfaces as
        // a catchable Swift error instead of a SIGBUS inside the extension.
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    /// Returns the highest-resolution variant for a base image name.
    /// - Parameter base: e.g. `"logo"`, `"icon"`, `"strip"`.
    public func image(named base: String) -> Data? {
        for suffix in ["@3x", "@2x", ""] {
            if let data = images["\(base)\(suffix).png"] {
                return data
            }
        }
        return nil
    }

    /// Convenience accessors for the well-known image slots.
    public var logo: Data? { image(named: "logo") }
    public var icon: Data? { image(named: "icon") }
    public var thumbnail: Data? { image(named: "thumbnail") }
    public var strip: Data? { image(named: "strip") }
    public var background: Data? { image(named: "background") }
    public var footer: Data? { image(named: "footer") }

    // MARK: - Helpers

    private static func prettyPrint(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: pretty, encoding: .utf8) else {
            return String(decoding: data, as: UTF8.self)
        }
        return string
    }
}
