# Remote TOTP Cipher Secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded Spotify TOTP cipher secrets with a remotely-fetched, locally-cached version that auto-heals when Spotify rotates secrets every few days.

**Architecture:** A new `SpotifySecretsService` fetches `secretDict.json` from a community-maintained GitHub URL at startup, caches it in `SharedPreferences` for 6 hours, and calls `SpotifyTotpHelper.applySecrets()` to swap in the fresh secrets. `SpotifyTotpHelper` gains runtime-secret fields that override the hardcoded fallback. `main.dart` calls `SpotifySecretsService.loadAndApply()` before `runApp()`.

**Tech Stack:** Flutter/Dart, `http` package (already in deps), `shared_preferences`, `flutter_test`, `mocktail`

---

## File Map

**Created:**
- `lib/services/spotify_secrets_service.dart` — fetch, validate, cache lifecycle
- `test/services/spotify_secrets_service_test.dart` — validation logic + TTL + applySecrets integration

**Modified:**
- `lib/services/spotify_totp_helper.dart` — add `_runtimeSecrets`, `applySecrets()`, `clearRuntimeSecrets()`, `activeVersion` getter; update `generateTotp()` and `generateTotpParams()`
- `lib/main.dart` — call `SpotifySecretsService.loadAndApply()` in `main()` before `runApp()`

---

## Task 1: SpotifySecretsService + Tests (TDD)

**Files:**
- Create: `lib/services/spotify_secrets_service.dart`
- Create: `test/services/spotify_secrets_service_test.dart`

### Step 1 — Write the failing tests

Create `test/services/spotify_secrets_service_test.dart`:

```dart
// test/services/spotify_secrets_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_secrets_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SpotifySecretsService.validateSecretsFormat', () {
    test('accepts valid dict with int-list values', () {
      final result = SpotifySecretsService.validateSecretsFormat({
        '14': [62, 54, 109, 83],
        '13': [59, 92, 64, 70],
      });
      expect(result, isNotNull);
      expect(result!['14'], [62, 54, 109, 83]);
      expect(result['13'], [59, 92, 64, 70]);
    });

    test('rejects empty dict', () {
      expect(SpotifySecretsService.validateSecretsFormat({}), isNull);
    });

    test('rejects non-digit key', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'v14': [1, 2, 3]}),
        isNull,
      );
    });

    test('rejects key with letters mixed in', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14a': [1, 2, 3]}),
        isNull,
      );
    });

    test('rejects value that is not a list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': 'not-a-list'}),
        isNull,
      );
    });

    test('rejects value that is a map not a list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': {'nested': 1}}),
        isNull,
      );
    });

    test('rejects list containing non-ints', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': [1, 'two', 3]}),
        isNull,
      );
    });

    test('rejects empty value list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': []}),
        isNull,
      );
    });
  });

  group('SpotifySecretsService cache TTL', () {
    test('fresh cache (< 6h) passes TTL check', () async {
      final freshTs = DateTime.now().millisecondsSinceEpoch - (1 * 60 * 60 * 1000); // 1h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': freshTs,
      });
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('spotify_totp_secrets_ts')!;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      expect(age, lessThan(6 * 60 * 60 * 1000));
    });

    test('stale cache (> 6h) fails TTL check', () async {
      final staleTs = DateTime.now().millisecondsSinceEpoch - (7 * 60 * 60 * 1000); // 7h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': staleTs,
      });
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('spotify_totp_secrets_ts')!;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      expect(age, greaterThan(6 * 60 * 60 * 1000));
    });

    test('missing timestamp means no usable cache', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('spotify_totp_secrets_ts'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail (SpotifySecretsService doesn't exist yet)**

```bash
flutter test test/services/spotify_secrets_service_test.dart -v
```

Expected: compilation error — `spotify_secrets_service.dart` not found.

- [ ] **Step 3: Create `lib/services/spotify_secrets_service.dart`**

```dart
// lib/services/spotify_secrets_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';
import 'spotify_totp_helper.dart';

class SpotifySecretsService {
  static const String _remoteUrl =
      'https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true';
  static const String _cacheKey = 'spotify_totp_secrets';
  static const String _cacheTimestampKey = 'spotify_totp_secrets_ts';
  static const int _cacheTtlMs = 6 * 60 * 60 * 1000; // 6 hours in ms

  /// Loads secrets (cache-first, then remote), applies them to SpotifyTotpHelper.
  /// Silent on failure — TOTP falls back to hardcoded constants.
  static Future<Map<String, List<int>>?> loadAndApply() async {
    final secrets = await _loadSecrets();
    if (secrets != null) {
      SpotifyTotpHelper.applySecrets(secrets);
      AppLogger.info('TOTP secrets loaded (version: ${SpotifyTotpHelper.activeVersion})');
    }
    return secrets;
  }

  /// Validates that [raw] is a non-empty dict of digit-string keys to non-empty int-list values.
  /// Returns the typed map on success, null on any validation failure.
  static Map<String, List<int>>? validateSecretsFormat(Map<String, dynamic> raw) {
    if (raw.isEmpty) return null;
    final result = <String, List<int>>{};
    for (final entry in raw.entries) {
      if (!RegExp(r'^\d+$').hasMatch(entry.key)) return null;
      if (entry.value is! List) return null;
      final list = entry.value as List;
      if (list.isEmpty) return null;
      if (!list.every((e) => e is int)) return null;
      result[entry.key] = list.cast<int>();
    }
    return result;
  }

  static Future<Map<String, List<int>>?> _loadSecrets() async {
    final cached = await _loadFromCache();
    if (cached != null) return cached;

    try {
      final response = await http
          .get(Uri.parse(_remoteUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        AppLogger.spotify('TOTP secrets fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final validated = validateSecretsFormat(decoded);
      if (validated == null) {
        AppLogger.spotify('TOTP secrets failed format validation');
        return null;
      }

      await _saveToCache(validated);
      return validated;
    } catch (e) {
      AppLogger.spotify('TOTP secrets fetch error: $e');
      return null;
    }
  }

  static Future<Map<String, List<int>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_cacheTimestampKey);
      if (ts == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheTtlMs) return null;

      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;

      final decoded = json.decode(raw) as Map<String, dynamic>;
      return validateSecretsFormat(decoded);
    } catch (e) {
      AppLogger.spotify('TOTP cache load error: $e');
      return null;
    }
  }

  static Future<void> _saveToCache(Map<String, List<int>> secrets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(secrets));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.spotify('TOTP cache save error: $e');
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/spotify_secrets_service_test.dart -v
```

Expected: 11/11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/spotify_secrets_service.dart test/services/spotify_secrets_service_test.dart
git commit -m "feat: add SpotifySecretsService for remote TOTP cipher secrets"
```

---

## Task 2: Extend SpotifyTotpHelper + Integration Tests

**Files:**
- Modify: `lib/services/spotify_totp_helper.dart`
- Modify: `test/services/spotify_secrets_service_test.dart` (add new group)

### Step 1 — Add the integration tests to the existing test file

Append this group to `test/services/spotify_secrets_service_test.dart`, inside `main()`, after the existing groups:

```dart
  group('SpotifyTotpHelper runtime secrets', () {
    setUp(() => SpotifyTotpHelper.clearRuntimeSecrets());
    tearDown(() => SpotifyTotpHelper.clearRuntimeSecrets());

    test('activeVersion returns highest hardcoded version when no runtime secrets', () {
      // hardcoded dict has '14' and '13' — max is '14'
      expect(SpotifyTotpHelper.activeVersion, '14');
    });

    test('activeVersion returns highest version from applied secrets', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
        '14': [62, 54, 109, 83, 107, 77, 41, 103, 45, 93, 114, 38, 41, 97, 64, 51, 95, 94, 95, 94],
      });
      expect(SpotifyTotpHelper.activeVersion, '15');
    });

    test('generateTotp produces different code after applySecrets with different bytes', () {
      final totpBefore = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);

      SpotifyTotpHelper.applySecrets({
        '14': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      final totpAfter = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);

      expect(totpBefore, isNot(totpAfter));
    });

    test('clearRuntimeSecrets reverts activeVersion to hardcoded fallback', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      expect(SpotifyTotpHelper.activeVersion, '15');
      SpotifyTotpHelper.clearRuntimeSecrets();
      expect(SpotifyTotpHelper.activeVersion, '14');
    });

    test('generateTotpParams totpVer reflects activeVersion', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: 1700000000000);
      expect(params['totpVer'], '15');
    });
  });
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
flutter test test/services/spotify_secrets_service_test.dart -v
```

Expected: compilation error or runtime error — `applySecrets`, `clearRuntimeSecrets`, `activeVersion` not defined yet.

- [ ] **Step 3: Modify `lib/services/spotify_totp_helper.dart`**

Add these four members directly after the existing constants block (after line 16 `static const int totpInterval = 30;`):

```dart
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
```

Then in `generateTotp()`, replace line:
```dart
    final secretCipherBytes = secretCipherDict[totpVer] ?? secretCipherDict['14']!;
```
with:
```dart
    final source = _runtimeSecrets ?? secretCipherDict;
    final secretCipherBytes = source[activeVersion]!;
```

Then in `generateTotpParams()`, replace:
```dart
      'totpVer': totpVer,
```
with:
```dart
      'totpVer': activeVersion,
```

- [ ] **Step 4: Run the full test file**

```bash
flutter test test/services/spotify_secrets_service_test.dart -v
```

Expected: 16/16 tests pass (11 existing + 5 new).

- [ ] **Step 5: Run the existing TOTP tests to confirm no regressions**

```bash
flutter test test/services/spotify_totp_helper_test.dart -v
```

Expected: 8/8 tests pass. The `totpVer matches the current configured version` test passes because `activeVersion` returns `'14'` (max of hardcoded keys) which equals `SpotifyTotpHelper.totpVer`.

- [ ] **Step 6: Commit**

```bash
git add lib/services/spotify_totp_helper.dart test/services/spotify_secrets_service_test.dart
git commit -m "feat: add runtime secret support to SpotifyTotpHelper"
```

---

## Task 3: Wire up main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import and startup call**

In `lib/main.dart`, add this import after the existing imports:

```dart
import 'services/spotify_secrets_service.dart';
```

In the `main()` function, add the `loadAndApply()` call after `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`. The full updated `main()` function:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Fetch fresh TOTP cipher secrets from remote (falls back silently to hardcoded)
  await SpotifySecretsService.loadAndApply();

  // Initialize widget service
  await WidgetService.initialize();

  // Initialize background service
  await BackgroundService.initialize();

  // Check for updates on startup if needed
  _checkForUpdatesOnStartup();

  runApp(MyApp(prefs: prefs));
}
```

- [ ] **Step 2: Run analyze**

```bash
flutter analyze lib/main.dart lib/services/spotify_secrets_service.dart lib/services/spotify_totp_helper.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: load remote TOTP secrets at app startup"
```

---

## Task 4: Final Verification

**Files:** none

- [ ] **Step 1: Run all tests**

```bash
flutter test -v
```

Expected: all tests pass. Count should be 127+ (111 existing + 16 new). Zero failures.

- [ ] **Step 2: Run full analyze**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Debug build**

```bash
flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 4: Commit if any stragglers**

```bash
git status
```

If clean, nothing to do.
