//
//  MiniZip.swift
//  PkpassKit
//
//  A tiny, dependency-free ZIP reader. A `.pkpass` file is a standard ZIP
//  archive, so all we need is enough of the format to pull individual entries
//  out (pass.json + images). Decompression uses Apple's `Compression`
//  framework — `COMPRESSION_ZLIB` decodes raw DEFLATE, which is exactly the
//  algorithm ZIP method 8 uses, so we avoid third-party dependencies entirely.
//

import Foundation
import Compression

/// Errors thrown while reading a ZIP / `.pkpass` container.
public enum MiniZipError: Error, CustomStringConvertible, Sendable {
    case notAZipArchive
    case corrupted(String)
    case decompressionFailed(String)

    public var description: String {
        switch self {
        case .notAZipArchive:
            return "This file is not a valid ZIP / .pkpass archive."
        case .corrupted(let detail):
            return "The archive appears corrupted: \(detail)"
        case .decompressionFailed(let detail):
            return "Could not decompress an entry: \(detail)"
        }
    }
}

/// Minimal ZIP central-directory reader.
public enum MiniZip {

    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50

    /// Hard ceiling on a single decompressed entry. A real pass is a few hundred
    /// KB at most; this guards against decompression bombs where an attacker
    /// claims a huge `uncompressedSize` to force a giant allocation.
    private static let maxEntrySize = 64 * 1024 * 1024
    /// Hard ceiling on the combined decompressed size of every entry, so an
    /// archive full of small bombs can't add up to an exhaustion either.
    private static let maxTotalSize = 256 * 1024 * 1024

    /// Extracts every file entry from a ZIP archive held in memory.
    /// - Returns: A dictionary mapping the entry path to its decompressed bytes.
    public static func entries(from data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 22 else { throw MiniZipError.notAZipArchive }

        guard let eocd = locateEOCD(in: bytes) else { throw MiniZipError.notAZipArchive }

        let totalEntries = Int(readU16(bytes, eocd + 10))
        let centralSize = Int(readU32(bytes, eocd + 12))
        let centralOffset = Int(readU32(bytes, eocd + 16))
        guard centralOffset >= 0, centralSize >= 0,
              centralOffset + 46 <= count,
              centralOffset + centralSize <= count,
              centralOffset + centralSize <= eocd else {
            throw MiniZipError.corrupted("bad central directory bounds")
        }
        let centralEnd = centralOffset + centralSize

        var result: [String: Data] = [:]
        var totalDecompressed = 0
        var cursor = centralOffset
        var seen = 0

        while seen < totalEntries, cursor + 46 <= centralEnd {
            guard readU32(bytes, cursor) == centralSignature else { break }

            let method = readU16(bytes, cursor + 10)
            let compressedSize = Int(readU32(bytes, cursor + 20))
            let uncompressedSize = Int(readU32(bytes, cursor + 24))
            let nameLength = Int(readU16(bytes, cursor + 28))
            let extraLength = Int(readU16(bytes, cursor + 30))
            let commentLength = Int(readU16(bytes, cursor + 32))
            let localOffset = Int(readU32(bytes, cursor + 42))

            guard cursor + 46 + nameLength <= count else {
                throw MiniZipError.corrupted("filename length out of bounds")
            }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)

            // Directory entries have a trailing slash and no payload — skip them.
            if !name.hasSuffix("/") {
                let payload = try extractPayload(
                    bytes: bytes,
                    name: name,
                    localOffset: localOffset,
                    centralOffset: centralOffset,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
                totalDecompressed += payload.count
                guard totalDecompressed <= maxTotalSize else {
                    throw MiniZipError.decompressionFailed("archive decompresses to more than \(maxTotalSize / (1024 * 1024)) MiB")
                }
                result[name] = payload
            }

            cursor += 46 + nameLength + extraLength + commentLength
            seen += 1
        }

        guard !result.isEmpty else { throw MiniZipError.corrupted("no readable entries") }
        return result
    }

    // MARK: - Payload extraction

    private static func extractPayload(
        bytes: [UInt8],
        name: String,
        localOffset: Int,
        centralOffset: Int,
        method: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        // The local header must sit before the central directory — a crafted
        // entry must not point its payload into or past the directory.
        guard localOffset >= 0, localOffset + 30 <= bytes.count,
              localOffset + 30 <= centralOffset,
              readU32(bytes, localOffset) == localSignature else {
            throw MiniZipError.corrupted("bad local header for \(name)")
        }

        let localNameLength = Int(readU16(bytes, localOffset + 26))
        let localExtraLength = Int(readU16(bytes, localOffset + 28))
        let dataStart = localOffset + 30 + localNameLength + localExtraLength

        guard dataStart >= 0, dataStart + compressedSize <= bytes.count else {
            throw MiniZipError.corrupted("payload out of bounds for \(name)")
        }

        let compressed = Array(bytes[dataStart..<(dataStart + compressedSize)])

        switch method {
        case 0: // Stored, no compression.
            guard compressed.count <= maxEntrySize else {
                throw MiniZipError.decompressionFailed("stored entry \(name) exceeds \(maxEntrySize / (1024 * 1024)) MiB")
            }
            return Data(compressed)
        case 8: // DEFLATE.
            return try inflate(compressed, expectedSize: uncompressedSize)
        default:
            throw MiniZipError.decompressionFailed("unsupported compression method \(method) for \(name)")
        }
    }

    // MARK: - End of Central Directory

    private static func locateEOCD(in bytes: [UInt8]) -> Int? {
        let count = bytes.count
        // EOCD is 22 bytes plus an optional comment (max 65535).
        let minimum = max(0, count - 22 - 65_535)
        var index = count - 22
        while index >= minimum {
            if readU32(bytes, index) == eocdSignature {
                return index
            }
            index -= 1
        }
        return nil
    }

    // MARK: - DEFLATE

    private static func inflate(_ input: [UInt8], expectedSize: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }

        // Fast path: we know (and trust) the output size from the central
        // directory. Only honour it when it's within the per-entry ceiling so a
        // bogus huge size can't trigger a giant eager allocation.
        if expectedSize > 0, expectedSize <= maxEntrySize {
            var destination = [UInt8](repeating: 0, count: expectedSize)
            let written = input.withUnsafeBufferPointer { source in
                destination.withUnsafeMutableBufferPointer { dest in
                    compression_decode_buffer(
                        dest.baseAddress!, expectedSize,
                        source.baseAddress!, input.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if written == expectedSize {
                return Data(destination)
            }
        }

        // Fallback: stream when the size is unknown, implausible, or mismatched.
        // A hard limit stops a bomb that lies about (or omits) its size.
        return try streamInflate(input, limit: maxEntrySize)
    }

    private static func streamInflate(_ input: [UInt8], limit: Int) throws -> Data {
        let chunk = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }

        return try input.withUnsafeBufferPointer { source -> Data in
            var stream = compression_stream(
                dst_ptr: destination, dst_size: chunk,
                src_ptr: source.baseAddress!, src_size: source.count,
                state: nil
            )
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
                throw MiniZipError.decompressionFailed("could not initialise decompression stream")
            }
            defer { compression_stream_destroy(&stream) }

            var output = Data()
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.dst_ptr = destination
                stream.dst_size = chunk
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = chunk - stream.dst_size
                    if produced > 0 {
                        guard output.count + produced <= limit else {
                            throw MiniZipError.decompressionFailed("entry exceeds \(limit / (1024 * 1024)) MiB decompression limit")
                        }
                        output.append(destination, count: produced)
                    }
                default:
                    throw MiniZipError.decompressionFailed("stream processing error")
                }
            } while status == COMPRESSION_STATUS_OK
            return output
        }
    }

    // MARK: - Little-endian readers

    private static func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
