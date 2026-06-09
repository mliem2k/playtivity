import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

const Map<String, List<int>> _cipher = {
  '59': [123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72],
  '60': [79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87],
  '61': [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78],
};
const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

String _totp() {
  final ver = _cipher.keys.map(int.parse).reduce((a, b) => a > b ? a : b).toString();
  final cipher = _cipher[ver]!;
  final t = List.generate(cipher.length, (i) => cipher[i] ^ ((i % 33) + 9));
  final hex = t.map((n) => n.toString()).join().codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bytes = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  var bits = 0, len = 0;
  final b32 = StringBuffer();
  for (final b in bytes) {
    bits = (bits << 8) | b;
    len += 8;
    while (len >= 5) {
      len -= 5;
      b32.write(chars[(bits >> len) & 0x1f]);
    }
  }
  if (len > 0) b32.write(chars[(bits << (5 - len)) & 0x1f]);
  final secret = b32.toString();
  final step = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final msg = Uint8List(8)..buffer.asByteData().setInt64(0, step);
  final pad = (4 - secret.length % 4) % 4;
  final padded = secret + '=' * pad;
  var bits2 = 0, len2 = 0;
  final key = <int>[];
  for (final c in padded.toUpperCase().split('')) {
    if (c == '=') break;
    final v = chars.indexOf(c);
    if (v < 0) continue;
    bits2 = (bits2 << 5) | v;
    len2 += 5;
    if (len2 >= 8) { len2 -= 8; key.add((bits2 >> len2) & 0xff); }
  }
  final hmac = Hmac(sha1, key).convert(msg).bytes;
  final off = hmac[hmac.length - 1] & 0x0f;
  final code = ((hmac[off] & 0x7f) << 24 | (hmac[off+1] & 0xff) << 16 | (hmac[off+2] & 0xff) << 8 | (hmac[off+3] & 0xff)) % 1000000;
  return code.toString().padLeft(6, '0');
}

Future<void> main() async {
  final spDc = Platform.environment['SPOTIFY_SP_DC']!;
  final totp = _totp();

  // Fetch token
  final c1 = HttpClient();
  final url = 'https://open.spotify.com/api/token?reason=transport&productType=web-player&totp=$totp&totpServer=$totp&totpVer=61';
  final r1 = await c1.getUrl(Uri.parse(url));
  r1.headers.set('Cookie', 'sp_dc=$spDc');
  r1.headers.set('User-Agent', ua);
  r1.headers.set('Accept', 'application/json');
  r1.headers.set('App-Platform', 'WebPlayer');
  final rr1 = await r1.close();
  final body1 = await rr1.transform(utf8.decoder).join();
  c1.close();
  final tokenJson = jsonDecode(body1) as Map<String, dynamic>;
  final token = tokenJson['accessToken'] as String?;
  if (token == null) { print('No token: $body1'); return; }
  print('Token fetched (len=${token.length})');

  // Full spclient /me response
  final c2 = HttpClient();
  final r2 = await c2.getUrl(Uri.parse('https://guc-spclient.spotify.com/user-profile-view/v3/profile/me'));
  r2.headers.set('Authorization', 'Bearer $token');
  r2.headers.set('Accept', 'application/json');
  r2.headers.set('App-Platform', 'WebPlayer');
  r2.headers.set('User-Agent', ua);
  final rr2 = await r2.close();
  final body2 = await rr2.transform(utf8.decoder).join();
  c2.close();
  print('\n=== guc-spclient /me FULL (${rr2.statusCode}) ===');
  try {
    final data = jsonDecode(body2) as Map<String, dynamic>;
    data.forEach((k, v) {
      final val = v is String && v.length > 120 ? '${v.substring(0, 120)}...' : v;
      print('  $k: $val');
    });
  } catch (_) { print(body2); }
}
