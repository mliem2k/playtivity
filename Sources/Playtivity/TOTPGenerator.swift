/// Pure-Swift port of lib/services/spotify_totp_helper.dart.
/// Deliberately uses no CryptoKit and no Foundation crypto APIs, only
/// arithmetic/bit operations, so it can be validated for Skip Lite
/// transpilation before the rest of the app is built on top of it.
enum TOTPGenerator {
    // NOTE: declared as separate top-level [UInt8]-typed constants, rather than
    // inline array literals nested directly inside the dictionary literal below.
    // Skip Lite's Swift-to-Kotlin transpiler does not reliably propagate the
    // [UInt8] element type two levels deep (through both the Dictionary literal
    // and the nested Array literal at once), which otherwise produces a
    // Kotlin `Dictionary<String, Array<Int>>` instead of the required
    // `Dictionary<String, Array<UByte>>`. Byte values are unchanged from the
    // original vectors.
    // NOTE: `.map { UInt8($0) }` rather than a direct `[UInt8] = [123, 105, ...]`
    // literal. Skip Lite's transpiler emits integer-literal arrays via Kotlin's
    // `arrayOf(123, 105, ...)`, which infers `Array<Int>` regardless of the
    // declared Swift element type, mismatching the `Array<UByte>` the constant
    // is declared as ("Initializer type mismatch"). Mapping through UInt8(...)
    // (a pattern already proven to transpile correctly elsewhere in this file,
    // e.g. `activeVersion`'s `.compactMap`/`.map` chain) forces element-wise
    // conversion. Byte values are unchanged from the original vectors.
    private static let cipher59: [UInt8] = [123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72].map { UInt8($0) }
    private static let cipher60: [UInt8] = [79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87].map { UInt8($0) }
    private static let cipher61: [UInt8] = [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78].map { UInt8($0) }

    private static let hardcodedSecretCipherDict: [String: [UInt8]] = ["59": cipher59, "60": cipher60, "61": cipher61]

    // Runtime-applied secrets from SpotifySecretsService, taking over from the hardcoded
    // fallback above once set. `nonisolated(unsafe)` because Swift 6's strict concurrency mode
    // rejects a plain mutable static var as unsynchronized global state; writes only happen via
    // applySecrets/clearRuntimeSecrets, an infrequent, non-hot-path operation (a periodic secrets
    // refresh, or a test resetting state), not a value read/written from a tight concurrent loop.
    nonisolated(unsafe) private static var runtimeSecretCipherDict: [String: [UInt8]]?

    /// The active cipher dictionary: runtime-applied secrets if `applySecrets` has been called,
    /// else the hardcoded fallback baked in at build time.
    static var secretCipherDict: [String: [UInt8]] {
        runtimeSecretCipherDict ?? hardcodedSecretCipherDict
    }

    /// Applies a freshly fetched secrets dictionary, taking over from the hardcoded fallback.
    /// Mirrors `SpotifyTotpHelper.applySecrets` in the original Dart. After this call,
    /// `activeVersion`/`generateCode`/`generateParams` all reflect the newly applied secrets.
    static func applySecrets(_ secrets: [String: [UInt8]]) {
        runtimeSecretCipherDict = secrets
    }

    /// Reverts to the hardcoded fallback dictionary, discarding any applied secrets. Mirrors the
    /// Dart `clearRuntimeSecrets`; primarily useful for test isolation between cases that call
    /// `applySecrets`.
    static func clearRuntimeSecrets() {
        runtimeSecretCipherDict = nil
    }

    static let totpInterval: Int64 = 30

    static var activeVersion: String {
        secretCipherDict.keys.compactMap { Int($0) }.max().map { String($0) } ?? "0"
    }

    static func generateCode(timestampMillis: Int64) -> String {
        let seconds = timestampMillis / 1000
        let secretCipherBytes = secretCipherDict[activeVersion]!

        var transformed = [UInt8]()
        transformed.reserveCapacity(secretCipherBytes.count)
        for i in 0..<secretCipherBytes.count {
            transformed.append(secretCipherBytes[i] ^ UInt8((i % 33) + 9))
        }

        let joined = transformed.map { String($0) }.joined()
        let hexStr = asciiToHex(joined)
        let preBytes = hexToBytes(hexStr)
        let secretBase32 = base32Encode(preBytes)
        let keyBytes = base32Decode(secretBase32)

        let timeStep = seconds / totpInterval
        let message = intToBytes8(timeStep)
        let digest = hmacSha1(key: keyBytes, message: message)

        let offset = Int(digest[digest.count - 1] & UInt8(0x0f))
        let code = ((UInt32(digest[offset] & UInt8(0x7f)) << 24) |
                    (UInt32(digest[offset + 1]) << 16) |
                    (UInt32(digest[offset + 2]) << 8) |
                    UInt32(digest[offset + 3])) % UInt32(1_000_000)

        var codeStr = String(code)
        while codeStr.count < 6 {
            codeStr = "0" + codeStr
        }
        return codeStr
    }

    static func generateParams(timestampMillis: Int64) -> [String: String] {
        let totp = generateCode(timestampMillis: timestampMillis)
        return ["totp": totp, "totpServer": totp, "totpVer": activeVersion]
    }

    // MARK: - Encoding helpers (mirror spotify_totp_helper.dart exactly,
    // including the base32 encode-then-decode round trip, which is not a
    // no-op: it zero-pads the key to a multiple of 5 bytes)

    // NOTE: iterates Characters directly (rather than String.unicodeScalars,
    // which Skip Lite's transpiler does not support: "Unresolved reference
    // 'unicodeScalars'") and reads each Character's ASCII code via
    // .asciiValue!, widened to UInt32 for the shift/mask arithmetic.
    private static func asciiToHex(_ s: String) -> String {
        let hexChars: [Character] = "0123456789abcdef".map { $0 }
        var result = ""
        for c in s {
            let v = UInt32(c.asciiValue!)
            // NOTE: string concatenation (+) rather than String.append(Character).
            // Skip Lite transpiles `var result = ""` to a plain immutable Kotlin
            // String, which has no .append() (that only exists on skip.lib's
            // Array<UByte> wrapper); += / + concatenation is the supported idiom
            // (already used elsewhere in this file, e.g. "0" + codeStr).
            result = result + String(hexChars[Int((v >> 4) & UInt32(0xf))])
            result = result + String(hexChars[Int(v & UInt32(0xf))])
        }
        return result
    }

    // NOTE: uses numeric ASCII-code comparisons rather than Character range
    // pattern matching (`case "0"..."9":`). Skip Lite's transpiler mistranslates
    // Character literals inside such range patterns as Kotlin String literals
    // instead of Char literals, producing "actual type is Char, but String was
    // expected" errors. This is behaviorally identical: '0'-'9' is ASCII 48-57,
    // 'a'-'f' is 97-102, 'A'-'F' is 65-70.
    private static func hexDigitValue(_ c: Character) -> UInt8 {
        let v = UInt32(c.asciiValue!)
        if v >= UInt32(48) && v <= UInt32(57) {
            return UInt8(v - UInt32(48))
        } else if v >= UInt32(97) && v <= UInt32(102) {
            return UInt8(v - UInt32(97) + UInt32(10))
        } else if v >= UInt32(65) && v <= UInt32(70) {
            return UInt8(v - UInt32(65) + UInt32(10))
        } else {
            return UInt8(0)
        }
    }

    private static func hexToBytes(_ hex: String) -> [UInt8] {
        let chars: [Character] = hex.map { $0 }
        var bytes = [UInt8]()
        var i = 0
        while i + 1 < chars.count {
            let hi = hexDigitValue(chars[i])
            let lo = hexDigitValue(chars[i + 1])
            // NOTE: widen to UInt32 before shifting. Kotlin's UByte does not
            // define shl/shr (only and/or/xor), so shifting a UInt8 directly
            // fails to transpile ("Unresolved reference 'shl'").
            bytes.append(UInt8((UInt32(hi) << 4) | UInt32(lo)))
            i += 2
        }
        return bytes
    }

    private static let base32Alphabet: [Character] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".map { $0 }

    private static func base32Encode(_ data: [UInt8]) -> String {
        var result = ""
        var i = 0
        while i < data.count {
            var block = [UInt8](repeating: UInt8(0), count: 5)
            let count = min(5, data.count - i)
            for j in 0..<count { block[j] = data[i + j] }

            var n: UInt64 = UInt64(0)
            for b in block { n = (n << 8) | UInt64(b) }

            var j = 7
            while j >= 0 {
                let index = Int((n >> (j * 5)) & UInt64(31))
                result = result + String(base32Alphabet[index])
                j -= 1
            }
            i += 5
        }
        return result
    }

    private static func base32Decode(_ s: String) -> [UInt8] {
        var bits = 0
        var value: UInt32 = UInt32(0)
        var out = [UInt8]()
        for ch in s.uppercased() {
            guard let index = base32Alphabet.firstIndex(of: ch) else { continue }
            value = (value << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & UInt32(0xff)))
                bits -= 8
            }
        }
        return out
    }

    private static func intToBytes8(_ value: Int64) -> [UInt8] {
        var bytes = [UInt8](repeating: UInt8(0), count: 8)
        for i in 0..<8 {
            bytes[7 - i] = UInt8((value >> (8 * i)) & Int64(0xff))
        }
        return bytes
    }

    // MARK: - HMAC-SHA1 (pure Swift, no CryptoKit/Foundation crypto)

    private static func hmacSha1(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let blockSize = 64
        var keyBytes = key
        if keyBytes.count > blockSize {
            keyBytes = sha1(keyBytes)
        }
        if keyBytes.count < blockSize {
            keyBytes.append(contentsOf: [UInt8](repeating: UInt8(0), count: blockSize - keyBytes.count))
        }
        var oKeyPad = [UInt8](repeating: UInt8(0x5c), count: blockSize)
        var iKeyPad = [UInt8](repeating: UInt8(0x36), count: blockSize)
        for i in 0..<blockSize {
            oKeyPad[i] = oKeyPad[i] ^ keyBytes[i]
            iKeyPad[i] = iKeyPad[i] ^ keyBytes[i]
        }
        let innerHash = sha1(iKeyPad + message)
        return sha1(oKeyPad + innerHash)
    }

    private static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = UInt32(0x67452301)
        var h1: UInt32 = UInt32(0xEFCDAB89)
        var h2: UInt32 = UInt32(0x98BADCFE)
        var h3: UInt32 = UInt32(0x10325476)
        var h4: UInt32 = UInt32(0xC3D2E1F0)

        var msg = message
        let mlBits = UInt64(message.count) * UInt64(8)
        msg.append(UInt8(0x80))
        while msg.count % 64 != 56 {
            msg.append(UInt8(0))
        }
        var shift = 56
        while shift >= 0 {
            msg.append(UInt8((mlBits >> shift) & UInt64(0xff)))
            shift -= 8
        }

        var chunkStart = 0
        while chunkStart < msg.count {
            var w = [UInt32](repeating: UInt32(0), count: 80)
            for i in 0..<16 {
                let base = chunkStart + i * 4
                w[i] = (UInt32(msg[base]) << 24) | (UInt32(msg[base + 1]) << 16) | (UInt32(msg[base + 2]) << 8) | UInt32(msg[base + 3])
            }
            for i in 16..<80 {
                let val = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (val << 1) | (val >> 31)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for i in 0..<80 {
                var f: UInt32
                var k: UInt32
                if i < 20 {
                    f = (b & c) | (~b & d)
                    k = UInt32(0x5A827999)
                } else if i < 40 {
                    f = b ^ c ^ d
                    k = UInt32(0x6ED9EBA1)
                } else if i < 60 {
                    f = (b & c) | (b & d) | (c & d)
                    k = UInt32(0x8F1BBCDC)
                } else {
                    f = b ^ c ^ d
                    k = UInt32(0xCA62C1D6)
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e

            chunkStart += 64
        }

        var result = [UInt8]()
        for h in [h0, h1, h2, h3, h4] {
            result.append(UInt8((h >> 24) & UInt32(0xff)))
            result.append(UInt8((h >> 16) & UInt32(0xff)))
            result.append(UInt8((h >> 8) & UInt32(0xff)))
            result.append(UInt8(h & UInt32(0xff)))
        }
        return result
    }
}
