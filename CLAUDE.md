# Playtivity — Claude Instructions

## Release Policy

**All releases must be done locally using the scripts in `scripts/`.** Never create releases any other way.

- Nightly build: `node scripts/nightly.js`
- Promote nightly to release: `node scripts/nightly-release.js [--increment patch|minor|major|none] [--version x.y.z]`

**Forbidden release paths (never use these):**
- `gh release create` — manual gh CLI release
- `gh workflow run` or any GitHub Actions workflow
- The GitHub web UI releases page
- Hand-editing `pubspec.yaml` version and tagging manually

The workflows in `.github/workflows/` have been removed; releases are owned by the local scripts. Every release must go through `nightly.js` or `nightly-release.js` so the version, tag, APK filename, and build metadata are all consistent.

---

## Versioning

All version strings follow Flutter's `pubspec.yaml` format: `version: NAME+BUILD`.

Flutter maps this to the platform as:
- Android `versionName` = NAME, `versionCode` = BUILD
- iOS `CFBundleShortVersionString` = NAME, `CFBundleVersion` = BUILD

### Stable release

```
version: MAJOR.MINOR.PATCH+1
```

- BUILD is always `1` for stable releases (reset by `nightly-release.js`).
- NAME is plain semver: `0.0.2`, `0.1.0`, `1.0.0`.
- GitHub tag: `vMAJOR.MINOR.PATCH` (e.g. `v0.0.2`).
- `nightly-release.js` increments the base version and resets BUILD to `1`:
  - `--increment patch` (default): PATCH + 1
  - `--increment minor`: MINOR + 1, PATCH = 0
  - `--increment major`: MAJOR + 1, MINOR = 0, PATCH = 0
  - `--version x.y.z`: override to exact version

### Nightly

```
version: MAJOR.MINOR.PATCH-nightly-YYYYMMDD-HHMMSS+UNIX_EPOCH_SECONDS
```

Example: `0.0.2-nightly-20260611-050901+1781212141`

- NAME embeds the build date-time (local machine time when `nightly.js` runs).
- BUILD is `Math.floor(Date.now() / 1000)` — Unix epoch seconds at build time.
  BUILD is strictly monotonically increasing and is the **primary signal** used
  by the in-app update checker to decide whether a nightly is newer.
- `pubspec.yaml` is temporarily patched to the nightly version for the build
  and then restored to the stable base immediately after.
- GitHub tags: `nightly-YYYYMMDD-HHMMSS` (individual build) and
  `latest-nightly` (floating, always recreated to point to the newest nightly).

### In-app update detection (`lib/services/update_service.dart`)

| Installed | Available | Rule |
|-----------|-----------|------|
| nightly   | nightly   | BUILD (integer) comparison — larger BUILD wins. Timestamp fallback if BUILDs are unparseable. |
| nightly   | stable    | Only offered if stable has a higher major or minor base version. |
| stable    | stable    | Semver comparison on NAME. |
| stable    | nightly   | Only offered if nightly base version >= installed stable base version. |

### What never changes

- Stable BUILD is always `1`. Do not set it to anything else.
- Nightly BUILD must be `Math.floor(Date.now() / 1000)` — do not use a
  sequential counter or a hardcoded value.
- Never hand-edit `pubspec.yaml` version while a build is running; the scripts
  own that field and restore it on completion.
