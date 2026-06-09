/// Standalone auth endpoint tester — no Flutter, pure Dart.
///
/// Usage:
///   dart run tool/test_auth_endpoints.dart <bearer_token>
///
/// Or set env var:
///   SPOTIFY_TOKEN=xxx dart run tool/test_auth_endpoints.dart
///
/// How to get a bearer token for testing:
///   1. Install the prod APK and attempt login
///   2. From ADB logcat filter "AUTH": adb logcat | grep "AUTH"
///      Look for "loginComplete: token len=" — token is already in memory at that point.
///   OR capture from an intercepting proxy during the webview login.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ── TOTP (inlined from SpotifyTotpHelper) ────────────────────────────────────

const Map<String, List<int>> _secretCipherDict = {
  '59': [123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72],
  '60': [79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87],
  '61': [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78],
};

String _activeVersion() {
  return _secretCipherDict.keys.map(int.parse).reduce((a, b) => a > b ? a : b).toString();
}

String _generateTotp({int? timestampMillis}) {
  final t = timestampMillis ?? DateTime.now().millisecondsSinceEpoch;
  final seconds = (t / 1000).floor();
  final ver = _activeVersion();
  final cipher = _secretCipherDict[ver]!;
  final transformed = List.generate(cipher.length, (i) => cipher[i] ^ ((i % 33) + 9));
  final joined = transformed.map((n) => n.toString()).join('');
  final hexStr = joined.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final secret = _base32Encode(hexStr);
  final timeStep = seconds ~/ 30;
  final hmac = _hmacSha1(secret, _intToBytes(timeStep));
  final offset = hmac[hmac.length - 1] & 0x0f;
  final code = ((hmac[offset] & 0x7f) << 24 |
                (hmac[offset + 1] & 0xff) << 16 |
                (hmac[offset + 2] & 0xff) << 8 |
                (hmac[offset + 3] & 0xff)) %
               1000000;
  return code.toString().padLeft(6, '0');
}

Map<String, String> _totpParams({int? ts}) {
  final totp = _generateTotp(timestampMillis: ts);
  return {'totp': totp, 'totpServer': totp, 'totpVer': _activeVersion()};
}

String _base32Encode(String hex) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  var bits = 0, bitsLen = 0;
  final result = StringBuffer();
  for (final b in bytes) {
    bits = (bits << 8) | b;
    bitsLen += 8;
    while (bitsLen >= 5) {
      bitsLen -= 5;
      result.write(chars[(bits >> bitsLen) & 0x1f]);
    }
  }
  if (bitsLen > 0) result.write(chars[(bits << (5 - bitsLen)) & 0x1f]);
  return result.toString();
}

List<int> _intToBytes(int n) {
  final b = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    b[i] = n & 0xff;
    n >>= 8;
  }
  return b;
}

List<int> _hmacSha1(String base32Secret, List<int> msg) {
  final pad = (4 - base32Secret.length % 4) % 4;
  final padded = base32Secret + '=' * pad;
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0, bitsLen = 0;
  final keyBytes = <int>[];
  for (final c in padded.toUpperCase().split('')) {
    if (c == '=') break;
    final v = chars.indexOf(c);
    if (v < 0) continue;
    bits = (bits << 5) | v;
    bitsLen += 5;
    if (bitsLen >= 8) {
      bitsLen -= 8;
      keyBytes.add((bits >> bitsLen) & 0xff);
    }
  }
  final hmac = Hmac(sha1, keyBytes);
  return hmac.convert(msg).bytes;
}

// ── JWT decode ────────────────────────────────────────────────────────────────

String? _extractUserIdFromJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) payload += '=';
    final decoded = utf8.decode(Uint8List.fromList(base64.decode(payload)));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final sub = json['sub'] as String?;
    if (sub == null || sub.isEmpty) return null;
    return sub.startsWith('spotify:user:') ? sub.substring('spotify:user:'.length) : sub;
  } catch (e) {
    return null;
  }
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────

const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

Future<({int status, String body})> _get(String url, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  } finally {
    client.close();
  }
}

// ── Token fetch ───────────────────────────────────────────────────────────────

Future<String?> _fetchBearerToken(String spDc) async {
  print('\n[token] Fetching server time...');
  final timeClient = HttpClient();
  int serverTime;
  try {
    final req = await timeClient.getUrl(Uri.parse('https://open.spotify.com/'));
    final res = await req.close();
    await res.drain<void>();
    final dateStr = res.headers.value('date');
    serverTime = dateStr != null
        ? HttpDate.parse(dateStr).millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;
    print('[token] Server time: $dateStr');
  } finally {
    timeClient.close();
  }

  final params = _totpParams(ts: serverTime);
  final tokenUrl = Uri.parse('https://open.spotify.com/api/token').replace(
    queryParameters: {
      'reason': 'transport',
      'productType': 'web-player',
      ...params,
    },
  );

  print('[token] Fetching token from $tokenUrl');
  final r = await _get(tokenUrl.toString(), {
    'Cookie': 'sp_dc=$spDc',
    'User-Agent': _ua,
    'Accept': 'application/json',
    'App-Platform': 'WebPlayer',
    'Content-Type': 'application/json',
    'Referer': 'https://open.spotify.com/',
    'Origin': 'https://open.spotify.com',
  });
  print('[token] Status: ${r.status}');
  if (r.status != 200) {
    print('[token] Body: ${r.body}');
    return null;
  }
  final json = jsonDecode(r.body) as Map<String, dynamic>;
  if (json['isAnonymous'] == true) {
    print('[token] Got anonymous token — sp_dc is expired or invalid');
    return null;
  }
  final token = json['accessToken'] as String?;
  print('[token] Got token: ${token != null ? "${token.substring(0, 20)}... (len=${token.length})" : "null"}');
  return token;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void _section(String title) {
  print('\n${'─' * 60}');
  print('  $title');
  print('─' * 60);
}

Future<void> _testWithBearerToken(String token) async {
  _section('1. Token info');
  print('Length: ${token.length}');
  print('Is JWT: ${token.contains(".")}');
  print('Prefix: ${token.substring(0, token.length.clamp(0, 10))}...');

  _section('2. Spclient /me (guc-spclient.spotify.com)');
  try {
    final r = await _get(
      'https://guc-spclient.spotify.com/user-profile-view/v3/profile/me',
      {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'App-Platform': 'WebPlayer',
        'User-Agent': _ua,
      },
    );
    print('Status: ${r.status}');
    if (r.status == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      print('Name:      ${data['name']}');
      print('URI:       ${data['uri']}');
      print('Followers: ${data['followers_count']}');
      print('RESULT: ✅ SUCCESS');
    } else {
      print('Body: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
      print('RESULT: ❌ FAILED');
    }
  } catch (e) {
    print('Error: $e');
    print('RESULT: ❌ FAILED');
  }

  _section('3. Official API (/v1/me)');
  try {
    final r = await _get('https://api.spotify.com/v1/me', {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    print('Status: ${r.status}');
    if (r.status == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      print('display_name: ${data['display_name']}');
      print('id: ${data['id']}');
      print('RESULT: ✅ SUCCESS');
    } else {
      print('Body: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
      print('RESULT: ❌ FAILED');
    }
  } catch (e) {
    print('Error: $e');
    print('RESULT: ❌ FAILED');
  }
}

Future<void> main(List<String> args) async {
  String? token = args.isNotEmpty ? args[0] : Platform.environment['SPOTIFY_TOKEN'];
  String? spDc = args.length > 1 ? args[1] : Platform.environment['SPOTIFY_SP_DC'];

  if (token == null && spDc == null) {
    print('Usage:');
    print('  dart run tool/test_auth_endpoints.dart <bearer_token>');
    print('  dart run tool/test_auth_endpoints.dart <bearer_token> <sp_dc>');
    print('  SPOTIFY_TOKEN=xxx dart run tool/test_auth_endpoints.dart');
    print('  SPOTIFY_SP_DC=xxx dart run tool/test_auth_endpoints.dart  (will fetch token first)');
    exit(1);
  }

  print('Spotify Auth Endpoint Tester');
  print('Time: ${DateTime.now()}');

  if (token == null && spDc != null) {
    _section('0. Fetching bearer token from sp_dc');
    token = await _fetchBearerToken(spDc);
    if (token == null) {
      print('\n❌ Could not get bearer token. Check sp_dc value.');
      exit(1);
    }
  }

  await _testWithBearerToken(token!);
  print('\n${'─' * 60}\nDone.\n');
}
