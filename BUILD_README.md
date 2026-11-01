# Playtivity Android builds

The Android app is built from `native/` with Kotlin and Gradle. `version.yml` supplies the version name and nightly build code; stable APKs use their build-time Unix timestamp as the Android version code so they can upgrade an installed nightly.

## Requirements

1. JDK 21, Android SDK, and Bun.
2. For a production build, a release keystore at `release-key.jks` or `keystore.base64.txt`. These files stay local and are ignored by Git.
3. Release signing variables `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. The local scripts configure these from the keystore and environment.

## Preview build

```bash
cd native
./gradlew :core:testDebugUnitTest :app:lintPreviewDebug :app:assemblePreviewDebug
```

The APK is `native/app/build/outputs/apk/preview/debug/app-preview-debug.apk`. Its package is `com.mliem.playtivity.nativeapp`, so it can be installed beside the production app.

## Local production builds

```bash
bun run build
bun run release
bun run release:apk-only
```

`build` increments the build number and copies a signed production APK to `builds/`. `release` increments the patch version, builds a signed APK and App Bundle, and copies them to `releases/`. `release:apk-only` omits the App Bundle. These commands create local artifacts. They do not publish a GitHub release.

The production package is `com.mliem.playtivity`. The production APK is built at `native/app/build/outputs/apk/production/release/app-production-release.apk`; the App Bundle is built at `native/app/build/outputs/bundle/productionRelease/app-production-release.aab`.

## Publishing

Routine published updates use `bun scripts/nightly.js`. Formal stable promotion uses `bun scripts/nightly-release.js`. Those scripts own the release tag, version, and metadata. See [CLAUDE.md](CLAUDE.md) for the release policy.

The Windows builder can be selected with `PLAYTIVITY_BUILDER=msi-laptop`. Its build scripts are in `scripts/builder/`. A release build verifies the APK signature before copying or publishing it.

Install and exercise the APK on the Samsung S10 with the configured `android` CLI before a production release. The Kotlin app's device parity check remains open.
