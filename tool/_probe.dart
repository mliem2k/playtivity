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
  for (final b in bytes) { bits = (bits << 8) | b; len += 8; while (len >= 5) { len -= 5; b32.write(chars[(bits >> len) & 0x1f]); } }
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

Future<({int status, String body})> _get(String url, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.followRedirects = true;
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  } finally {
    client.close();
  }
}

Future<void> main() async {
  final spDc = Platform.environment['SPOTIFY_SP_DC']!;
  final totp = _totp();

  final t1 = await _get(
    'https://open.spotify.com/api/token?reason=transport&productType=web-player&totp=$totp&totpServer=$totp&totpVer=61',
    {'Cookie': 'sp_dc=$spDc', 'User-Agent': ua, 'Accept': 'application/json', 'App-Platform': 'WebPlayer'},
  );
  final tokenJson = jsonDecode(t1.body) as Map<String, dynamic>;
  final token = tokenJson['accessToken'] as String? ?? '';
  if (token.isEmpty) { print('No token: ${t1.body}'); return; }
  print('Token OK (len=${token.length})');

  // Test api.spotify.com/v1/me — the correct current-user endpoint
  final me = await _get('https://api.spotify.com/v1/me', {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'App-Platform': 'WebPlayer',
    'User-Agent': ua,
  });
  print('\n=== api.spotify.com/v1/me === status=${me.status}');
  if (me.status == 200) {
    final d = jsonDecode(me.body) as Map<String, dynamic>;
    print('id: ${d['id']}');
    print('display_name: ${d['display_name']}');
    print('country: ${d['country']}');
    print('followers: ${d['followers']?['total']}');
    final images = d['images'] as List? ?? [];
    print('image: ${images.isNotEmpty ? images[0]['url'] : null}');
  } else {
    print(me.body.substring(0, me.body.length.clamp(0, 300)));
  }

  // Also probe buddylist to confirm token works for spclient
  final bl = await _get('https://guc-spclient.spotify.com/presence-view/v1/buddylist', {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'App-Platform': 'WebPlayer',
    'User-Agent': ua,
  });
  print('\n=== buddylist === status=${bl.status}');
  if (bl.status == 200) {
    final d = jsonDecode(bl.body) as Map<String, dynamic>;
    final friends = d['friends'] as List? ?? [];
    print('${friends.length} friends returned');
  } else {
    print(bl.body.substring(0, bl.body.length.clamp(0, 300)));
  }
}
