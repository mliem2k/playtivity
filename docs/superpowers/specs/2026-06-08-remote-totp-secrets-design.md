# Remote TOTP Cipher Secrets Design

**Date:** 2026-06-08
**Scope:** Replace hardcoded Spotify TOTP cipher secrets with a remotely-fetched, locally-cached version that auto-heals when Spotify rotates secrets.

---

## Context

Playtivity uses an unofficial Spotify API (`guc-spclient.spotify.com/presence-view/v1/buddylist`) to show friends' listening activity. Accessing it requires a web-player access token fetched from `https://open.spotify.com/api/token` using TOTP parameters generated from cipher secrets (`secretCipherDict`).

Since December 2025, Spotify rotates these cipher secrets every few days. The app currently hardcodes them in `SpotifyTotpHelper.secretCipherDict`, causing token fetch failures every rotation until a new app build is published.

The community maintains a regularly-updated `secretDict.json` at:
```
https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true
```

The format is identical to the hardcoded map: `{"14": [62, 54, ...], "13": [59, 92, ...]}`.

---

## Architecture

Three focused changes:

### 1. New `SpotifySecretsService` (`lib/services/spotify_secrets_service.dart`)

Single-responsibility service (~60 lines) that owns the fetch-and-cache lifecycle:

- Fetches from the xyloflake URL with a 5-second timeout
- Validates format: non-empty dict, all keys are digit strings, all values are `List<int>`
- Caches raw JSON string in `SharedPreferences` under key `spotify_secrets_cache` alongside `spotify_secrets_fetched_at` (epoch ms)
- TTL: 6 hours
- Returns `Map<String, List<int>>?` — null on any failure

**Fallback chain:**
```
Remote fetch succeeds                   → use remote secrets
Remote fetch fails + cache < 6h old    → use cached secrets
Remote fetch fails + no usable cache   → return null (caller uses hardcoded)
```

### 2. Modified `SpotifyTotpHelper` (`lib/services/spotify_totp_helper.dart`)

- Add `static Map<String, List<int>>? _runtimeSecrets`
- Add `static void applySecrets(Map<String, List<int>> secrets)` — sets `_runtimeSecrets`
- Add `static String get activeVersion` — highest digit key in `_runtimeSecrets ?? secretCipherDict`
- Change `generateTotp()` to use `(_runtimeSecrets ?? secretCipherDict)[activeVersion]`
- `generateTotpParams()` uses `activeVersion` instead of hardcoded `totpVer`
- Hardcoded `secretCipherDict` and `totpVer` remain as fallback constants

### 3. App startup (`lib/main.dart`)

Call `SpotifySecretsService.loadAndApply()` before `runApp()`. This is fire-and-forget for failures — the app still starts even if fetch fails.

---

## Data Flow

```
main() 
  → SpotifySecretsService.loadAndApply()
      → check SharedPreferences (fetched_at + secrets_cache)
      → if stale/missing: GET github raw URL (5s timeout)
      → validate JSON
      → persist to SharedPreferences
      → SpotifyTotpHelper.applySecrets(parsed map)
  → runApp()

Later: SpotifyTotpHelper.generateTotp()
  → uses _runtimeSecrets[activeVersion] ?? secretCipherDict[totpVer]
```

---

## SharedPreferences Keys

| Key | Type | Value |
|---|---|---|
| `spotify_secrets_cache` | String | Raw JSON of the secrets dict |
| `spotify_secrets_fetched_at` | int | Epoch milliseconds of last successful fetch |

---

## Error Handling

- Network timeout (5s): fall back to cache or hardcoded
- Invalid JSON: log warning, fall back to cache or hardcoded
- Validation failure (wrong key/value types): log warning, fall back to cache or hardcoded
- All failures are silent to the user — TOTP generation always produces a code (may be stale but is never broken structurally)

---

## Testing

New `test/services/spotify_secrets_service_test.dart`:

- `validateSecretsFormat`: valid dict passes, empty dict fails, non-digit key fails, non-int-list value fails
- Cache TTL: fresh cache (< 6h) returns cached value without fetching; stale cache triggers fetch
- `applySecrets` + `activeVersion`: after applying `{"15": [...]}`, `activeVersion` returns `'15'`
- TOTP uses runtime secrets: after `applySecrets`, `generateTotp` uses the new secrets

---

## Completion Definition

1. `SpotifySecretsService` fetches, validates, and caches secrets from the remote URL
2. `SpotifyTotpHelper` uses fetched secrets when available, falls back to hardcoded
3. `main.dart` calls `loadAndApply()` before `runApp()`
4. All existing TOTP tests still pass (111/111)
5. New tests cover validation, TTL, and secret application
6. `flutter analyze` passes, `flutter build apk --debug` succeeds
