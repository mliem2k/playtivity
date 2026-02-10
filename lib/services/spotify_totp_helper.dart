import 'package:crypto/crypto.dart';

/// Helper class for generating Spotify TOTP codes
/// Spotify added TOTP requirement in March 2025 for token extraction
class SpotifyTotpHelper {
  /// Current TOTP secrets (v13, v14) - these expire periodically
  static const Map<String, List<int>> secretCipherDict = {
    '14': [62, 54, 109, 83, 107, 77, 41, 103, 45, 93, 114, 38, 41, 97, 64, 51, 95, 94, 95, 94],
    '13': [59, 92, 64, 70, 99, 78, 117, 75, 99, 103, 116, 67, 103, 51, 87, 63, 93, 59, 70, 45, 32],
  };

  /// Current TOTP version
  static const String totpVer = '14';

  /// TOTP time interval in seconds
  static const int totpInterval = 30;

  /// Generates TOTP using XOR transformation
  ///
  /// [timestampMillis] Optional timestamp in milliseconds (defaults to current time)
  /// Returns a 6-digit TOTP code
  static String generateTotp({int? timestampMillis}) {
    final t = timestampMillis ?? DateTime.now().millisecondsSinceEpoch;
    final seconds = (t / 1000).floor();

    // XOR transformation based on index
    final secretCipherBytes = secretCipherDict[totpVer] ?? secretCipherDict['14']!;
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
    final totpServer = (t ~/ 1000).toString();

    return {
      'totp': totp,
      'totpServer': totpServer,
      'totpVer': totpVer,
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

  /// Converts integer to 4-byte big-endian representation
  static List<int> _intToBytes(int value) {
    return [
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
