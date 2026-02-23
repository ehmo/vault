import Foundation
import Compression

enum ShareLinkEncoder {
    // Bitcoin base58 alphabet — excludes 0, O, I, l
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let base = UInt(alphabet.count) // 58

    private static let shareHost = "vaultaire.app"
    private static let sharePath = "/s"
    private static let customScheme = "vaultaire"
    private static let customSchemeHost = "s"

    // Version bytes
    private static let versionRaw: UInt8 = 0x01
    private static let versionDeflate: UInt8 = 0x02

    // MARK: - Public API

    static func shareURL(for phrase: String) -> URL? {
        let encoded = encode(phrase)
        var components = URLComponents()
        components.scheme = "https"
        components.host = shareHost
        components.path = sharePath
        components.fragment = encoded
        return components.url
    }

    static func phrase(from url: URL) -> String? {
        guard isSupportedShareURL(url) else {
            return nil
        }

        if let fragment = url.fragment, !fragment.isEmpty {
            return decode(fragment)
        }

        // Optional compatibility path if fragment gets stripped by some handoff flows.
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let encoded = components.queryItems?.first(where: { $0.name == "p" })?.value,
           !encoded.isEmpty {
            return decode(encoded)
        }

        return nil
    }

    private static func isSupportedShareURL(_ url: URL) -> Bool {
        let path = url.path

        if let scheme = url.scheme?.lowercased(), scheme == "https" {
            guard let host = url.host,
                  host == shareHost || host.hasSuffix("." + shareHost) else {
                return false
            }
            return path == sharePath || path == sharePath + "/"
        }

        if let scheme = url.scheme?.lowercased(), scheme == customScheme {
            if let host = url.host?.lowercased(), host == customSchemeHost {
                return path.isEmpty || path == "/"
            }
            return path == sharePath || path == sharePath + "/"
        }

        return false
    }

    static func encode(_ phrase: String) -> String {
        let raw = Array(phrase.utf8)

        // Try deflate compression
        if let compressed = deflateCompress(Data(raw)), compressed.count < raw.count {
            let payload = [versionDeflate] + Array(compressed)
            return base58Encode(payload)
        }

        // Fallback: raw encoding
        let payload = [versionRaw] + raw
        return base58Encode(payload)
    }

    static func decode(_ encoded: String) -> String? {
        guard let payload = base58Decode(encoded), !payload.isEmpty else { return nil }

        let version = payload[0]
        let data = Array(payload.dropFirst())

        if version == versionRaw {
            return String(bytes: data, encoding: .utf8)
        } else if version == versionDeflate {
            guard let decompressed = deflateDecompress(Data(data)) else { return nil }
            return String(data: decompressed, encoding: .utf8)
        } else {
            return nil
        }
    }

    // MARK: - Base58

    private static func base58Encode(_ bytes: [UInt8]) -> String {
        // Count leading zeros
        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count

        // Convert to big integer (array of UInt, little-endian digits in base 58)
        var digits: [UInt] = [0]
        for byte in bytes {
            var carry = UInt(byte)
            for i in 0..<digits.count {
                carry += digits[i] << 8
                digits[i] = carry % base
                carry /= base
            }
            while carry > 0 {
                digits.append(carry % base)
                carry /= base
            }
        }

        // Build result: leading '1's for zero bytes, then encoded digits in reverse
        var result = String(repeating: "1", count: leadingZeros)
        for digit in digits.reversed() {
            result.append(alphabet[Int(digit)])
        }

        // Strip leading '1' that came from the big-integer [0] init (unless it represents a real zero byte)
        if leadingZeros == 0, result.first == "1" {
            result.removeFirst()
        }

        return result
    }

    private static func base58Decode(_ string: String) -> [UInt8]? {
        // Build reverse lookup
        var lookup = [Character: UInt]()
        for (i, c) in alphabet.enumerated() {
            lookup[c] = UInt(i)
        }

        let leadingOnes = string.prefix(while: { $0 == "1" }).count

        var bytes: [UInt] = [0]
        for char in string {
            guard let value = lookup[char] else { return nil }
            var carry = value
            for i in 0..<bytes.count {
                carry += bytes[i] * base
                bytes[i] = carry & 0xFF
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(carry & 0xFF)
                carry >>= 8
            }
        }

        // Leading zeros from '1' characters
        let leadingZeros = Array(repeating: UInt8(0), count: leadingOnes)

        // Drop trailing zeros from big-integer representation, reverse to get big-endian
        let significant = bytes.reversed().drop(while: { $0 == 0 })
        return leadingZeros + significant.map { UInt8($0) }
    }

    // MARK: - Compression

    private static func deflateCompress(_ data: Data) -> Data? {
        let sourceSize = data.count
        // Worst case: deflate can expand slightly
        let destinationSize = sourceSize + 512
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_encode_buffer(
                destination, destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self), sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destination, count: compressedSize)
    }

    private static func deflateDecompress(_ data: Data) -> Data? {
        // Allocate generous buffer for decompressed data (phrases are small)
        let destinationSize = 4096
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self), data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destination, count: decompressedSize)
    }
}
