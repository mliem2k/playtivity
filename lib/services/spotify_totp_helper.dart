import 'package:crypto/crypto.dart';

/// Helper class for generating Spotify TOTP codes
/// Spotify added TOTP requirement in March 2025 for token extraction
class SpotifyTotpHelper {
  /// Current TOTP secrets (v59-v61) - these expire periodically and are updated via
  /// SpotifySecretsService.loadAndApply() at startup. These hardcoded values are
  /// the last-known-good fallback if the remote fetch fails.
  static const Map<String, List<int>> secretCipherDict = {
    '59': [123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72],
    '60': [79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87],
    '61': [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78],
  };

  /// Current TOTP version (highest in secretCipherDict, used as hardcoded fallback)
  static const String totpVer = '61';

  /// TOTP time interval in seconds
  static const int totpInterval = 30;

  // Runtime secrets — set by SpotifySecretsService.loadAndApply(), override hardcoded fallback
  static Map<String, List<int>>? _runtimeSecrets;

  /// Applies remotely-fetched cipher secrets. Called once at startup.
  static void applySecrets(Map<String, List<int>> secrets) {
    _runtimeSecrets = secrets;
  }

  /// Clears runtime secrets, reverting generateTotp to the hardcoded fallback.
  static void clearRuntimeSecrets() {
    _runtimeSecrets = null;
  }

  /// Highest version key present in the active secrets source.
  static String get activeVersion {
    final source = _runtimeSecrets ?? secretCipherDict;
    return source.keys
        .map(int.parse)
        .reduce((a, b) => a > b ? a : b)
        .toString();
  }

  /// Generates TOTP using XOR transformation
  ///
  /// [timestampMillis] Optional timestamp in milliseconds (defaults to current time)
  /// Returns a 6-digit TOTP code
  static String generateTotp({int? timestampMillis}) {
    final t = timestampMillis ?? DateTime.now().millisecondsSinceEpoch;
    final seconds = (t / 1000).floor();

    // XOR transformation based on index
    final source = _runtimeSecrets ?? secretCipherDict;
    final secretCipherBytes = source[activeVersion]!;
    final transformed = List.generate(
      secretCipherBytes.length,
      (i) => secretCipherBytes[i] ^ ((i % 33) + 9),
    );

    // Convert to string, then hex, then base32
    final joined = transformed.map((n) => n.toString()).join('');
    final hexStr = _asciiToHex(joined);
    final secret = _base32Encode(hexStr);

    // Generate TOTP
    final timeStep = seconds ~/ totpInterval;
    final hmac = _hmacSha1(secret, _intToBytes(timeStep));
    final offset = hmac[hmac.length - 1] & 0x0f;
    final code = ((hmac[offset] & 0x7f) << 24 |
                  (hmac[offset + 1] & 0xff) << 16 |
                  (hmac[offset + 2] & 0xff) << 8 |
                  (hmac[offset + 3] & 0xff)) %
                 1000000;

    return code.toString().padLeft(6, '0');
  }

  /// Generates TOTP parameters map for API requests
  ///
  /// [timestampMillis] Optional timestamp in milliseconds (defaults to current time)
  /// Returns a map with totp, totpServer, and totpVer keys
  static Map<String, String> generateTotpParams({int? timestampMillis}) {
    final t = timestampMillis ?? DateTime.now().millisecondsSinceEpoch;
    final totp = generateTotp(timestampMillis: t);

    return {
      'totp': totp,
      'totpServer': totp, // Spotify requires totpServer == totp (same 6-digit code)
      'totpVer': activeVersion,
    };
  }

  /// Converts ASCII string to hex string
  static String _asciiToHex(String ascii) {
    return ascii.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Converts hex string to Base32 encoded string
  static String _base32Encode(String hexString) {
    final bytes = _hexToBytes(hexString);
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final result = StringBuffer();

    for (int i = 0; i < bytes.length; i += 5) {
      final block = List<int>.filled(5, 0);
      for (int j = 0; j < 5 && i + j < bytes.length; j++) {
        block[j] = bytes[i + j];
      }

      // Convert 5 bytes to 8 base32 characters
      var n = BigInt.zero;
      for (int j = 0; j < 5; j++) {
        n = (n << 8) | BigInt.from(block[j]);
      }

      for (int j = 7; j >= 0; j--) {
        final shiftAmount = j * 5;
        final index = ((n >> shiftAmount) & BigInt.from(31)).toInt();
        result.write(alphabet[index]);
      }
    }

    // Remove padding
    String resultStr = result.toString();
    while (resultStr.endsWith('=')) {
      resultStr = resultStr.substring(0, resultStr.length - 1);
    }

    return resultStr;
  }

  /// Converts hex string to bytes
  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Converts integer to 8-byte big-endian representation (RFC 6238 standard).
  /// The high 4 bytes are always zero for time steps within the current era.
  static List<int> _intToBytes(int value) {
    return [
      0, 0, 0, 0,
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  /// Computes HMAC-SHA1 hash
  static List<int> _hmacSha1(String key, List<int> message) {
    final keyBytes = _base32DecodeToBytes(key);

    // Use crypto package for proper HMAC-SHA1
    final hmac = Hmac(sha1, keyBytes);
    final digest = hmac.convert(message);

    return digest.bytes.toList();
  }

  /// Decodes Base32 string to bytes
  static List<int> _base32DecodeToBytes(String encoded) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final buffer = <int>[];
    int bits = 0;
    int value = 0;

    for (final char in encoded.toUpperCase().split('')) {
      if (char.isEmpty) continue;
      final index = alphabet.indexOf(char);
      if (index == -1) continue;

      value = (value << 5) | index;
      bits += 5;

      if (bits >= 8) {
        buffer.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }

    return buffer;
  }
}
