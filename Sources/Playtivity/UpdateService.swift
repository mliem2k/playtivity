import Foundation

/// Pure-Swift port of `lib/services/update_service.dart` and `lib/utils/version_utils.dart`.
/// A plain, stateless-style helper matching `ApiRetryService`'s shape (a static-only `enum`), NOT
/// an `@Observable` store: it has no interaction with `AuthStore`/`SpotifyStore` or their
/// concurrency gates. Settings' own transient UI state (check-in-progress, the fetched result to
/// show) lives in a later task's `SettingsScreen` `@State`, driven directly from this service's
/// static functions.
///
/// No `NSRegularExpression`/Swift `Regex` anywhere in this file: neither is vendored by
/// `SkipFoundation` (confirmed by inspecting the checked-out package; no `Regex`/
/// `NSRegularExpression` source exists there), so every pattern the Dart original expresses as a
/// `RegExp` is hand-rolled here as plain character-by-character scanning over `String.Index`,
/// matching the established `TOTPGenerator.hexDigitValue` idiom (ASCII-value comparisons rather
/// than `Character` range patterns, which Skip's transpiler is documented elsewhere in this
/// codebase to mistranslate). Marker searches are case-insensitive by lowercasing once per call
/// (`String.lowercased()` + the single-argument `String.range(of:)` `SkipFoundation` actually
/// implements); captured values are then read back from that same lowercased copy rather than
/// mapped to the original casing, which is safe here because every value this file ever captures
/// (a semver string, a nightly timestamp, a build number) is digits/dots/dashes/pluses only, never
/// letters whose case would matter.
enum UpdateService {
    // MARK: - Constants

    private static let githubReleasesApi = "https://api.github.com/repos/mliem2k/playtivity/releases"

    private static let prefLastCheckTime = "last_update_check_time"
    private static let prefEnableNightly = "enable_nightly_builds"
    private static let prefCheckFrequencyHours = "update_check_frequency_hours"

    private static let millisecondsPerHour: Int64 = 60 * 60 * 1000

    // MARK: - Test seams

    /// Injectable seam for tests: replaces the real GitHub Releases API call. Mirrors
    /// `BuddyActivityService.buddyListFetchOverride`'s established pattern (one closure per real
    /// network boundary). `nonisolated(unsafe)` because Swift 6 rejects a plain mutable static var
    /// as unsynchronized global state; production code only reads this, only tests write it.
    nonisolated(unsafe) static var githubReleasesFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?

    /// Injectable seam for tests: replaces the real APK download call. Deliberately URL-only (not
    /// a full `URLRequest`) and returns the whole body in one shot rather than a byte stream, since
    /// that is the shape this port's `downloadUpdate` actually needs (see that function's doc
    /// comment for why streaming chunk-by-chunk progress is not implemented here).
    nonisolated(unsafe) static var downloadFetchOverride: ((URL) async throws -> (statusCode: Int, data: Data, contentLength: Int?))?

    /// Injectable seam for tests: overrides `getCurrentAppVersion`'s result outright. Not part of
    /// this task's public interface list (Task 7/8 never need it), added purely because the brief's
    /// own contingency instruction proved necessary in practice: `Bundle.main.infoDictionary` on
    /// this transpile target's actual unit-test host process is NOT empty (confirmed by running the
    /// suite natively) -- it reports the `xctest` tool's own bundle (`CFBundleShortVersionString =
    /// "16.0"`, an Xcode-version-dependent value, not this app's), which is silently a real,
    /// non-empty, entirely wrong "current app version" for every checkForUpdates test. Without this
    /// seam, whether e.g. "0.0.5" reads as newer than the "current version" would depend on which
    /// Xcode version ran the suite. Production code never sets this; only tests do.
    nonisolated(unsafe) static var currentAppVersionOverride: AppVersionInfo?

    /// Reentrancy guard: a second concurrent `checkForUpdates` call short-circuits with an error
    /// rather than queuing, matching Dart's `_isCheckingForUpdates` bool. This is new mutable state
    /// (Dart's own copy is unguarded, safe there only because Dart's event loop serializes
    /// execution), so unlike `ApiRetryService.sleepOverride` (a test-only override never written by
    /// production code) this one genuinely needs a lock: both the read and the write happen from
    /// production code on every real call, so a single consistent synchronization mechanism
    /// (`checkGuardLock`, held only across the synchronous read/write below, never across an
    /// `await`) must protect every touch of `isCheckingForUpdates`, not just the ones written first.
    private static let checkGuardLock = NSLock()
    nonisolated(unsafe) private static var isCheckingForUpdates = false

    private static func tryBeginCheck() -> Bool {
        checkGuardLock.lock()
        defer { checkGuardLock.unlock() }
        if isCheckingForUpdates { return false }
        isCheckingForUpdates = true
        return true
    }

    private static func endCheck() {
        checkGuardLock.lock()
        defer { checkGuardLock.unlock() }
        isCheckingForUpdates = false
    }

    // MARK: - Version comparison (ported from version_utils.dart)

    /// Strips build metadata (`split('+')[0]` equivalent), then strips everything from
    /// `-nightly-` onward if present. Ported from `VersionUtils.extractBaseVersion` (lines 6-17).
    static func extractBaseVersion(_ version: String) -> String {
        let withoutBuild = version.components(separatedBy: "+")[0]
        if withoutBuild.contains("-nightly-") {
            return withoutBuild.components(separatedBy: "-nightly-")[0]
        }
        return withoutBuild
    }

    /// Ported from `VersionUtils.isNewerVersion` (lines 23-59) exactly, including its own
    /// deliberately asymmetric branches: both-nightly always returns `false` (this path is never
    /// the real nightly comparator; callers use `isNewerNightly` instead); current-nightly-vs-new-
    /// stable compares base versions and requires the stable's base to be strictly greater;
    /// current-stable-vs-new-nightly always returns `false` via this function directly (a caller
    /// wanting "offered only if nightly base >= current stable base" must strip nightly suffixes
    /// from both sides via `extractBaseVersion` first, reaching the plain base-version comparison
    /// at the bottom instead of this branch); both-stable is a plain base-version comparison.
    ///
    /// Note this checks for the plain substring `"nightly"`, not `"-nightly-"` like
    /// `isCurrentVersionNightly` does: a real, intentional difference from Dart's own source
    /// (`version_utils.dart` lines 30/34/51 use `.contains('nightly')`), preserved here verbatim.
    static func isNewerVersion(current: String, new: String) -> Bool {
        let currentIsNightly = current.contains("nightly")
        let newIsNightly = new.contains("nightly")

        if currentIsNightly && newIsNightly {
            return false
        } else if currentIsNightly && !newIsNightly {
            let currentBase = extractBaseVersion(current)
            let newBase = extractBaseVersion(new)
            return compareBaseVersions(currentBase, newBase) > 0
        } else if !currentIsNightly && newIsNightly {
            return false
        }

        return compareBaseVersions(current, new) > 0
    }

    /// Ported from `VersionUtils._compareBaseVersions` (lines 62-104): strips build metadata,
    /// splits on `-` for a pre-release suffix, compares major.minor.patch as integers (missing
    /// parts default to `0`), then if bases are equal, no-suffix beats has-suffix, and two suffixes
    /// compare lexicographically. Returns `1` when `version2` is newer, `-1` when `version1` is
    /// newer, `0` when equal (callers only ever check `> 0`, so the exact magnitude beyond sign
    /// doesn't matter, unlike Dart's raw `String.compareTo` magnitude).
    private static func compareBaseVersions(_ version1: String, _ version2: String) -> Int {
        let v1Clean = version1.components(separatedBy: "+")[0]
        let v2Clean = version2.components(separatedBy: "+")[0]

        let v1Parts = v1Clean.components(separatedBy: "-")
        let v2Parts = v2Clean.components(separatedBy: "-")

        var v1BaseParts = v1Parts[0].components(separatedBy: ".")
        var v2BaseParts = v2Parts[0].components(separatedBy: ".")
        while v1BaseParts.count < 3 { v1BaseParts.append("0") }
        while v2BaseParts.count < 3 { v2BaseParts.append("0") }

        for i in 0..<3 {
            let v1Part = Int(v1BaseParts[i]) ?? 0
            let v2Part = Int(v2BaseParts[i]) ?? 0
            if v2Part > v1Part { return 1 }
            if v2Part < v1Part { return -1 }
        }

        if v1Parts.count == 1 && v2Parts.count > 1 { return -1 }
        if v1Parts.count > 1 && v2Parts.count == 1 { return 1 }
        if v1Parts.count > 1 && v2Parts.count > 1 {
            if v2Parts[1] == v1Parts[1] { return 0 }
            return v2Parts[1] > v1Parts[1] ? 1 : -1
        }

        return 0
    }

    /// Ported from `VersionUtils.isNewerNightly` (lines 109-175): regex-extracts the LAST
    /// `nightly-YYYYMMDD-HHMMSS` match from each version string, parses to a `Date`, compares
    /// directly; returns `false` if either side fails to parse. No `RegExp` available (see file
    /// header), so "find the last match" is implemented via `components(separatedBy:)` on the
    /// literal marker `"nightly-"`, trying to parse a `YYYYMMDD-HHMMSS` prefix from the start of
    /// each fragment after a marker and keeping the last one that parses successfully.
    static func isNewerNightly(current: String, new: String) -> Bool {
        guard let currentTime = lastNightlyTimestamp(current),
              let newTime = lastNightlyTimestamp(new) else {
            return false
        }
        return newTime > currentTime
    }

    private static func lastNightlyTimestamp(_ version: String) -> Date? {
        let marker = "nightly-"
        let parts = version.components(separatedBy: marker)
        guard parts.count > 1 else { return nil }
        var lastMatch: Date?
        for i in 1..<parts.count {
            if let date = parseNightlyTimestampPrefix(parts[i]) {
                lastMatch = date
            }
        }
        return lastMatch
    }

    /// Parses a leading `YYYYMMDD-HHMMSS` (8 digits, dash, 6 digits) from the start of `text`,
    /// or `nil` if that exact shape isn't present. Builds a `DateFormatter`-parseable string rather
    /// than using `Calendar`/`DateComponents` (no precedent for either on this transpile target;
    /// `DateFormatter` with a POSIX locale + UTC time zone is the already-proven idiom, matching
    /// `Activity.iso8601Formatter`).
    private static func parseNightlyTimestampPrefix(_ text: String) -> Date? {
        let chars: [Character] = text.map { $0 }
        guard chars.count >= 15 else { return nil }
        for i in 0..<8 {
            if !isAsciiDigit(chars[i]) { return nil }
        }
        guard chars[8] == "-" else { return nil }
        for i in 9..<15 {
            if !isAsciiDigit(chars[i]) { return nil }
        }

        var stamp = ""
        for i in 0..<15 {
            stamp = stamp + String(chars[i])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: stamp)
    }

    /// Ported from `UpdateService.isCurrentVersionNightly` (lines 98-100): a dash-wrapped substring
    /// check, distinct from `isNewerVersion`'s looser plain `"nightly"` check (see that function's
    /// doc comment).
    static func isCurrentVersionNightly(_ version: String) -> Bool {
        version.contains("-nightly-")
    }

    // MARK: - Current app version

    /// Ported from `UpdateService.getCurrentAppVersion` (lines 30-36), which reads
    /// `PackageInfo.fromPlatform()` (Android `versionName`/`versionCode`, matching this project's
    /// own `pubspec.yaml` NAME+BUILD versioning convention). The Swift/Skip equivalent is
    /// `Bundle.main.infoDictionary`'s `CFBundleShortVersionString`/`CFBundleVersion`, which
    /// `SkipFoundation`'s Android `Bundle` shim synthesizes directly from the real installed
    /// package's `PackageInfo` on a genuine device/app run. Checks `currentAppVersionOverride`
    /// first (required in practice, not just anticipated: the native `swift test` host's own
    /// `Bundle.main` is the `xctest` tool's bundle, which has a real, non-empty, Xcode-version-
    /// dependent `CFBundleShortVersionString`/`CFBundleVersion` -- e.g. `"16.0"`/`"24904"` -- so an
    /// unguarded Bundle read would silently make every `checkForUpdates` comparison test's result
    /// depend on which Xcode version ran the suite). Absent an override, both fields fall back to a
    /// sentinel default (`"0.0.2"`/`"1"`, matching Dart's own `**Base Version**` fallback constant
    /// used elsewhere in this file) when Bundle info is empty/unset, which is what a real device/app
    /// run with no Info.plist version keys configured would see.
    static func getCurrentAppVersion() async -> AppVersionInfo {
        if let override = currentAppVersionOverride {
            return override
        }
        var version = "0.0.2"
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty {
            version = v
        }
        var buildNumber = "1"
        if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !b.isEmpty {
            buildNumber = b
        }
        return AppVersionInfo(version: version, buildNumber: buildNumber)
    }

    // MARK: - Preferences

    /// Ported from `UpdateService.getNightlyBuildPreference` (lines 41-47): defaults to `true` when
    /// the installed version is nightly and the user has never explicitly toggled the preference.
    static func getNightlyBuildPreference(userDefaults: UserDefaults = .standard) async -> Bool {
        if let stored = userDefaults.object(forKey: prefEnableNightly) as? Bool {
            return stored
        }
        let version = await getCurrentAppVersion()
        return isCurrentVersionNightly(version.version)
    }

    /// Ported from `UpdateService.setNightlyBuildPreference` (lines 50-53).
    static func setNightlyBuildPreference(_ value: Bool, userDefaults: UserDefaults = .standard) async {
        userDefaults.set(value, forKey: prefEnableNightly)
    }

    /// Reads the check-frequency-in-hours preference, defaulting to 24 (daily), matching Dart's
    /// `getCheckFrequency` default. No public getter/setter is exposed for this (unlike Dart, which
    /// has both): the brief's interface list doesn't call for one, and nothing in this codebase
    /// writes this key today, so exposing a setter would be unused public surface. The key is still
    /// read here (rather than hardcoding 24) so a future caller that does write it is honored.
    private static func checkFrequencyHours(userDefaults: UserDefaults) -> Int {
        (userDefaults.object(forKey: prefCheckFrequencyHours) as? Int) ?? 24
    }

    /// Ported from `UpdateService.shouldCheckForUpdates` (lines 80-88).
    static func shouldCheckForUpdates(userDefaults: UserDefaults = .standard) async -> Bool {
        let lastCheck = (userDefaults.object(forKey: prefLastCheckTime) as? Int64) ?? 0
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let checkFrequencyMs = Int64(checkFrequencyHours(userDefaults: userDefaults)) * millisecondsPerHour
        return (now - lastCheck) >= checkFrequencyMs
    }

    /// Ported from `UpdateService._markUpdateChecked` (lines 91-95).
    private static func markUpdateChecked(userDefaults: UserDefaults) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        userDefaults.set(now, forKey: prefLastCheckTime)
    }

    /// Ported from `UpdateService.autoEnableNightlyIfApplicable` (lines 103-117). Not part of this
    /// task's public interface list (Dart exposes it publicly, but nothing outside `checkForUpdates`
    /// needs to call it directly in this port), so kept `private`. Dart wraps this in a try/catch;
    /// this port has no throwing call inside (`getNightlyBuildPreference`/`setNightlyBuildPreference`
    /// never throw), so no catch is needed to match the same effective behavior.
    private static func autoEnableNightlyIfApplicable(currentVersion: AppVersionInfo, userDefaults: UserDefaults) async {
        let isNightly = isCurrentVersionNightly(currentVersion.version)
        let nightlyEnabled = await getNightlyBuildPreference(userDefaults: userDefaults)
        if isNightly && !nightlyEnabled {
            logger.info("Current version is nightly but preference is disabled. Auto-enabling nightly builds.")
            await setNightlyBuildPreference(true, userDefaults: userDefaults)
        }
    }

    // MARK: - GitHub Releases fetch

    private static func fetchGithubReleases() async throws -> [Any] {
        let url = URL(string: githubReleasesApi)!
        let request = URLRequest(url: url)
        let (statusCode, body) = try await performGithubReleasesRequest(request)
        if statusCode != 200 {
            throw UpdateServiceError(message: "Failed to fetch releases: HTTP \(statusCode)")
        }
        guard let data = body.data(using: String.Encoding.utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw UpdateServiceError(message: "Failed to parse releases response")
        }
        return decoded
    }

    private static func performGithubReleasesRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = githubReleasesFetchOverride {
            return try await override(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    /// Parses a GitHub release's `published_at` field, returning `nil` if missing or invalid.
    /// Ported from `UpdateService._parsePublishedAt` (lines 228-237); uses `DateFormatter` (the
    /// established idiom, see `Activity.iso8601Formatter`) rather than `ISO8601DateFormatter`,
    /// which has no precedent elsewhere in this app's own source (only inside `SkipFoundation`'s own
    /// implementation).
    fileprivate static func parsePublishedAt(_ releaseJson: [String: Any]) -> Date? {
        guard let publishedAt = releaseJson["published_at"] as? String, !publishedAt.isEmpty else { return nil }
        return iso8601Formatter(withFractionalSeconds: true).date(from: publishedAt)
            ?? iso8601Formatter(withFractionalSeconds: false).date(from: publishedAt)
    }

    private static func iso8601Formatter(withFractionalSeconds: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = withFractionalSeconds ? "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    /// `^\d+\.\d+` equivalent: one-or-more digits, a literal dot, one-or-more digits, anchored at
    /// the start of `s`. Used by `checkReleaseUpdates`'s stable-tag classification.
    private static func startsWithDigitsDotDigits(_ s: String) -> Bool {
        let chars: [Character] = s.map { $0 }
        var i = 0
        var firstRun = 0
        while i < chars.count, isAsciiDigit(chars[i]) { i += 1; firstRun += 1 }
        guard firstRun >= 1, i < chars.count, chars[i] == "." else { return false }
        i += 1
        var secondRun = 0
        while i < chars.count, isAsciiDigit(chars[i]) { i += 1; secondRun += 1 }
        return secondRun >= 1
    }

    // MARK: - Release / nightly selection (ported from _checkReleaseUpdatesFromJson / _checkNightlyUpdatesFromJson)

    /// Ported from `UpdateService._checkReleaseUpdatesFromJson` (lines 249-310). GitHub returns
    /// releases sorted by creation time, not tag/version date, so this scans every stable-tagged
    /// release and picks the one with the most recent `published_at`, not the first encountered.
    private static func checkReleaseUpdates(_ releases: [Any], currentVersion: AppVersionInfo) -> UpdateCheckResult {
        var latestReleaseJson: [String: Any]?
        var latestPublishedAt: Date?

        for releaseAny in releases {
            guard let releaseJson = releaseAny as? [String: Any] else { continue }
            let tagName = (releaseJson["tag_name"] as? String) ?? ""
            let isStableTag = (tagName.hasPrefix("v") || startsWithDigitsDotDigits(tagName)) && !tagName.contains("nightly")
            guard isStableTag else { continue }

            guard let publishedAt = parsePublishedAt(releaseJson) else { continue }
            if latestPublishedAt == nil || publishedAt > latestPublishedAt! {
                latestPublishedAt = publishedAt
                latestReleaseJson = releaseJson
            }
        }

        guard let latestReleaseJson else {
            return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: "No stable releases found")
        }

        let releaseInfo = UpdateInfo.fromGithubJson(latestReleaseJson, isNightly: false)
        let hasUpdate = isNewerVersion(current: currentVersion.version, new: releaseInfo.version)
        return UpdateCheckResult(hasUpdate: hasUpdate, isNightly: false, updateInfo: hasUpdate ? releaseInfo : nil, error: nil)
    }

    /// Ported from `UpdateService._checkNightlyUpdatesFromJson` (lines 313-367). The floating
    /// `latest-nightly` pointer tag is naturally excluded by the `hasPrefix("nightly-")` filter
    /// (it starts with `"latest-"`, not `"nightly-"`).
    private static func checkNightlyUpdates(_ releases: [Any], currentVersion: AppVersionInfo) -> UpdateCheckResult {
        var latestNightlyJson: [String: Any]?
        var latestPublishedAt: Date?

        for releaseAny in releases {
            guard let releaseJson = releaseAny as? [String: Any] else { continue }
            let tagName = (releaseJson["tag_name"] as? String) ?? ""
            guard tagName.hasPrefix("nightly-") else { continue }

            guard let publishedAt = parsePublishedAt(releaseJson) else { continue }
            if latestPublishedAt == nil || publishedAt > latestPublishedAt! {
                latestPublishedAt = publishedAt
                latestNightlyJson = releaseJson
            }
        }

        guard let latestNightlyJson else {
            return UpdateCheckResult(hasUpdate: false, isNightly: true, updateInfo: nil, error: "No nightly releases found")
        }

        let nightlyInfo = UpdateInfo.fromGithubJson(latestNightlyJson, isNightly: true)
        let hasUpdate = shouldUpdateToNightly(currentVersion: currentVersion, nightlyInfo: nightlyInfo)
        return UpdateCheckResult(hasUpdate: hasUpdate, isNightly: true, updateInfo: hasUpdate ? nightlyInfo : nil, error: nil)
    }

    /// Ported from `UpdateService._shouldUpdateToNightly` (lines 370-411): a stable user is only
    /// offered a nightly whose base version is >= their current stable base (never a downgrade);
    /// two nightlies compare build numbers (Unix epoch seconds, strictly monotonically increasing)
    /// as the primary signal, falling back to `isNewerNightly`'s embedded-timestamp comparison only
    /// when either build number fails to parse as an integer.
    private static func shouldUpdateToNightly(currentVersion: AppVersionInfo, nightlyInfo: UpdateInfo) -> Bool {
        if !currentVersion.version.contains("nightly") {
            let currentBase = extractBaseVersion(currentVersion.version)
            let nightlyBase = extractBaseVersion(nightlyInfo.version)
            return isNewerVersion(current: currentBase, new: nightlyBase) || currentBase == nightlyBase
        }

        if let currentBuild = Int(currentVersion.buildNumber), let newBuild = Int(nightlyInfo.buildNumber) {
            return newBuild > currentBuild
        }

        return isNewerNightly(current: currentVersion.version, new: nightlyInfo.version)
    }

    // MARK: - checkForUpdates orchestration

    /// Ported from `UpdateService.checkForUpdates` (lines 120-226). Order of operations, matching
    /// Dart exactly: reentrancy guard first, then the rate guard (bypassable via `forceCheck`),
    /// then `autoEnableNightlyIfApplicable` unconditionally on every real attempt, then a single
    /// shared GitHub Releases fetch, then both the stable and (if nightly enabled) nightly checks
    /// against that one fetch, then `_markUpdateChecked` (on any real, successfully-fetched attempt,
    /// regardless of whether an update was found -- but NOT inside the catch block below, matching
    /// Dart's own placement: a failed fetch never marks the check as done), then nightly-first
    /// priority in the return.
    static func checkForUpdates(forceCheck: Bool = false, userDefaults: UserDefaults = .standard) async -> UpdateCheckResult {
        guard tryBeginCheck() else {
            logger.info("Update check already in progress, skipping duplicate check")
            return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: "Update check already in progress")
        }
        defer { endCheck() }

        if !forceCheck {
            let should = await shouldCheckForUpdates(userDefaults: userDefaults)
            if !should {
                logger.info("Skipping update check, too soon since last check")
                return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: "Too soon since last check")
            }
        }

        let currentVersion = await getCurrentAppVersion()
        await autoEnableNightlyIfApplicable(currentVersion: currentVersion, userDefaults: userDefaults)
        let useNightly = await getNightlyBuildPreference(userDefaults: userDefaults)

        logger.info("Checking for updates... current=\(currentVersion.version)+\(currentVersion.buildNumber) nightlyEnabled=\(useNightly)")

        do {
            let releases = try await fetchGithubReleases()

            let releaseCheck = checkReleaseUpdates(releases, currentVersion: currentVersion)
            var nightlyCheck: UpdateCheckResult?
            if useNightly {
                nightlyCheck = checkNightlyUpdates(releases, currentVersion: currentVersion)
            }

            markUpdateChecked(userDefaults: userDefaults)

            if useNightly {
                if let nightlyCheck, nightlyCheck.hasUpdate {
                    logger.info("Nightly update available: \(nightlyCheck.updateInfo?.version ?? "?")")
                    return nightlyCheck
                }
                if releaseCheck.hasUpdate {
                    logger.info("Stable release update available for nightly user: \(releaseCheck.updateInfo?.version ?? "?")")
                    return releaseCheck
                }
                logger.info("No suitable updates available for nightly user")
                return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: nil)
            }

            if releaseCheck.hasUpdate {
                logger.info("Release update available: \(releaseCheck.updateInfo?.version ?? "?")")
                return releaseCheck
            }
            logger.info("No updates available")
            return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: nil)
        } catch {
            logger.error("Error checking for updates: \(error)")
            return UpdateCheckResult(hasUpdate: false, isNightly: false, updateInfo: nil, error: "Error checking for updates: \(error)")
        }
    }

    // MARK: - Download

    /// Ported from `UpdateService.downloadUpdate` (lines 413-512): dedup-reuses an already-complete
    /// download (matched by exact byte size), otherwise fetches the whole APK and writes it to
    /// `FileManager.default.temporaryDirectory`.
    ///
    /// Deliberate, disclosed simplification from Dart: Dart streams the HTTP response chunk-by-
    /// chunk (`response.stream`, an `await for` loop), reporting real incremental progress as each
    /// chunk arrives. This port's `downloadFetchOverride` test seam is intentionally shaped as
    /// `(URL) async throws -> (statusCode: Int, data: Data, contentLength: Int?)` -- a single-shot
    /// full-body result, not a byte stream -- matching this task's brief, which pre-approves this
    /// simplification ("a coarser single-shot progress emission (0% then 100%) is an acceptable,
    /// EXPLICITLY DISCLOSED simplification"). `URLSession.shared.data(from:)`, the non-overridden
    /// production path, is likewise a single-shot fetch, not a byte-stream API, matching every other
    /// network call already established in this codebase (`URLSession.shared.data(for:)` throughout
    /// `BuddyActivityService`/`SpotifyTokenService`/`SpotifySecretsService`, none of which stream
    /// either). `onProgress` is therefore invoked exactly twice: once at 0% before the fetch starts,
    /// once at 100% once the whole file has been fetched and written. This is a real, intentional
    /// reduction in progress granularity versus the Dart original, not an oversight.
    static func downloadUpdate(_ updateInfo: UpdateInfo, onProgress: ((DownloadProgress) -> Void)? = nil) async -> UpdateDownloadResult {
        logger.info("Downloading update: \(updateInfo.version) (\(updateInfo.apkUrl))")

        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(updateInfo.apkFileName)

        // Reuse an already-complete download (e.g. user cancelled the Android installer prompt and
        // tries again -- no need to re-download).
        if updateInfo.fileSizeBytes > 0,
           let existingData = try? Data(contentsOf: fileURL),
           existingData.count == updateInfo.fileSizeBytes {
            logger.info("Reusing existing download: \(fileURL.path)")
            return UpdateDownloadResult(success: true, filePath: fileURL.path, updateInfo: updateInfo, error: nil)
        }

        guard let url = URL(string: updateInfo.apkUrl) else {
            return UpdateDownloadResult(success: false, filePath: nil, updateInfo: nil, error: "Invalid download URL")
        }

        onProgress?(DownloadProgress(
            downloadedBytes: 0, totalBytes: updateInfo.fileSizeBytes,
            progress: 0.0, speedBytesPerSecond: 0.0, estimatedRemainingSeconds: 0.0
        ))

        let startTime = Date()

        do {
            let (statusCode, data, contentLength) = try await performDownloadRequest(url)
            if statusCode != 200 {
                return UpdateDownloadResult(success: false, filePath: nil, updateInfo: nil, error: "Failed to download update: HTTP \(statusCode)")
            }

            try data.write(to: fileURL)

            let totalBytes = contentLength ?? updateInfo.fileSizeBytes
            let downloadedBytes = data.count
            let elapsedSeconds = Date().timeIntervalSince(startTime)
            let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0
            let speedBytesPerSecond = elapsedSeconds > 0 ? Double(downloadedBytes) / elapsedSeconds : 0.0

            onProgress?(DownloadProgress(
                downloadedBytes: downloadedBytes, totalBytes: totalBytes,
                progress: progress, speedBytesPerSecond: speedBytesPerSecond, estimatedRemainingSeconds: 0.0
            ))

            logger.info("Update downloaded successfully: \(fileURL.path)")
            return UpdateDownloadResult(success: true, filePath: fileURL.path, updateInfo: updateInfo, error: nil)
        } catch {
            logger.error("Error downloading update: \(error)")
            return UpdateDownloadResult(success: false, filePath: nil, updateInfo: nil, error: "Error downloading update: \(error)")
        }
    }

    private static func performDownloadRequest(_ url: URL) async throws -> (statusCode: Int, data: Data, contentLength: Int?) {
        if let override = downloadFetchOverride {
            return try await override(url)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        var contentLength: Int?
        if let expected = (response as? HTTPURLResponse)?.expectedContentLength, expected >= 0 {
            contentLength = Int(expected)
        }
        return (statusCode, data, contentLength)
    }

    // MARK: - Small parsing helpers (shared with UpdateInfo.fromGithubJson via `fileprivate`)

    // ASCII-value comparisons rather than `Character` range patterns, matching
    // `TOTPGenerator.hexDigitValue`'s established idiom (Skip's transpiler is documented there to
    // mistranslate Character literals inside range patterns).
    // Widened to UInt32 with explicit `UInt32(...)`-wrapped literals, matching
    // `TOTPGenerator.hexDigitValue`'s exact established idiom: comparing the raw `UInt8` from
    // `asciiValue` directly against a bare Int literal (`v >= 48`) transpiles to a Kotlin `UByte`
    // vs `Int` comparison, which fails to compile ("Operator '==' cannot be applied to 'UByte' and
    // 'Int'"), confirmed by a real Kotlin/JVM build. Widening both sides to UInt32 first avoids it.
    fileprivate static func isAsciiDigit(_ c: Character) -> Bool {
        guard let raw = c.asciiValue else { return false }
        let v = UInt32(raw)
        return v >= UInt32(48) && v <= UInt32(57)
    }

    fileprivate static func isSpaceLike(_ c: Character) -> Bool {
        guard let raw = c.asciiValue else { return false }
        let v = UInt32(raw)
        return v == UInt32(32) || v == UInt32(9) || v == UInt32(10) || v == UInt32(13)
    }

    /// `\*\*<marker>\*\*:\s*`([^`]+)`` equivalent (case-insensitive), operating on an
    /// already-lowercased `lowerText`/`markerLower` pair (see file header for why this is safe).
    /// Returns `nil` if the marker isn't found, if no backtick immediately follows (after optional
    /// whitespace), or if no closing backtick is ever found, or if the captured span is empty --
    /// matching the regex's `+` (one-or-more) and overall match-or-nothing semantics.
    fileprivate static func extractBacktickedValue(_ lowerText: String, markerLower: String) -> String? {
        guard let markerRange = lowerText.range(of: markerLower) else { return nil }
        var idx = markerRange.upperBound
        while idx < lowerText.endIndex, isSpaceLike(lowerText[idx]) {
            idx = lowerText.index(after: idx)
        }
        guard idx < lowerText.endIndex, lowerText[idx] == "`" else { return nil }
        idx = lowerText.index(after: idx)

        var captured = ""
        while idx < lowerText.endIndex, lowerText[idx] != "`" {
            captured = captured + String(lowerText[idx])
            idx = lowerText.index(after: idx)
        }
        guard idx < lowerText.endIndex, !captured.isEmpty else { return nil }
        return captured
    }

    /// `<marker>\s*([^\s\n]+)` equivalent (case-insensitive): a non-whitespace token immediately
    /// (after optional whitespace) following the marker.
    fileprivate static func extractTokenValue(_ lowerText: String, markerLower: String) -> String? {
        guard let markerRange = lowerText.range(of: markerLower) else { return nil }
        var idx = markerRange.upperBound
        while idx < lowerText.endIndex, isSpaceLike(lowerText[idx]) {
            idx = lowerText.index(after: idx)
        }
        var captured = ""
        while idx < lowerText.endIndex, !isSpaceLike(lowerText[idx]) {
            captured = captured + String(lowerText[idx])
            idx = lowerText.index(after: idx)
        }
        return captured.isEmpty ? nil : captured
    }

    /// `-\s*\*\*Version\*\*:\s*`([^`]+)`` equivalent: the Dart original's third-tier nightly
    /// version pattern. Ported for structural fidelity only -- in Dart this tier is provably
    /// unreachable dead code, since its pattern is a strict superset of tier 1's
    /// (`\*\*Version\*\*:\s*`([^`]+)``, no dash anchor at all), so tier 1 always matches first
    /// whenever tier 3 would. This simplified port (first `-` anywhere in the text, then tier 1's
    /// own extractor on everything after it) preserves that same unreachability rather than
    /// precisely modeling `-\s*` immediately before the marker, which no real input can exercise.
    fileprivate static func extractDashPrefixedBacktickedVersion(_ lowerText: String) -> String? {
        let parts = lowerText.components(separatedBy: "-")
        guard parts.count > 1 else { return nil }
        let afterFirstDash = parts.dropFirst().joined(separator: "-")
        return extractBacktickedValue(afterFirstDash, markerLower: "**version**:")
    }

    /// `Version[:\s]*`?([^`\s\n]+)`?` equivalent (case-insensitive): looser than the nightly tiers
    /// above -- `[:\s]*` (colon-or-whitespace, zero or more) rather than `\s*`, and the leading
    /// backtick is optional rather than required. This looseness is what produces the Dart
    /// original's own documented quirk when applied to a `"**Version**: \`x.y.z\`"` body (the same
    /// markdown-bold shape the nightly tiers expect): "Version" matches at offset 2 inside
    /// `"**Version**:"`, `[:\s]*` cannot consume the immediately-following `"*"`, the optional
    /// backtick also doesn't match `"*"`, so the capture greedily eats `"**:"` (three characters)
    /// starting right there and stops at the next whitespace -- never reaching the real semver value
    /// at all. Faithfully reproduced (not "fixed") per this task's brief: match Dart's behavior
    /// rather than making it stricter. In practice this quirk is harmless: `fromGithubJson` only
    /// overrides the tag-derived version when the body match is STRICTLY LONGER, and `"**:"` (3
    /// chars) is essentially always shorter than any real tag-derived version string.
    fileprivate static func extractLooseVersionToken(_ lowerBody: String) -> String? {
        guard let markerRange = lowerBody.range(of: "version") else { return nil }
        var idx = markerRange.upperBound
        while idx < lowerBody.endIndex, (lowerBody[idx] == ":" || isSpaceLike(lowerBody[idx])) {
            idx = lowerBody.index(after: idx)
        }
        if idx < lowerBody.endIndex, lowerBody[idx] == "`" {
            idx = lowerBody.index(after: idx)
        }
        var captured = ""
        while idx < lowerBody.endIndex {
            let ch = lowerBody[idx]
            if ch == "`" || isSpaceLike(ch) { break }
            captured = captured + String(ch)
            idx = lowerBody.index(after: idx)
        }
        return captured.isEmpty ? nil : captured
    }

    /// Shared by the stable `Build Number[:\s]*`?(\d+)`?` pattern (`allowColon: true`, also
    /// consumes an optional leading backtick) and the release-name fallback `build\s*(\d+)`
    /// pattern (`allowColon: false`, whitespace only, no backtick). Both only ever capture digits.
    fileprivate static func extractDigitsAfterMarker(_ lowerText: String, markerLower: String, allowColon: Bool) -> String? {
        guard let markerRange = lowerText.range(of: markerLower) else { return nil }
        var idx = markerRange.upperBound
        while idx < lowerText.endIndex, (isSpaceLike(lowerText[idx]) || (allowColon && lowerText[idx] == ":")) {
            idx = lowerText.index(after: idx)
        }
        if allowColon, idx < lowerText.endIndex, lowerText[idx] == "`" {
            idx = lowerText.index(after: idx)
        }
        var digits = ""
        while idx < lowerText.endIndex, isAsciiDigit(lowerText[idx]) {
            digits = digits + String(lowerText[idx])
            idx = lowerText.index(after: idx)
        }
        return digits.isEmpty ? nil : digits
    }

    /// JSON numeric values from `JSONSerialization` can arrive boxed as either a 32-bit or 64-bit
    /// integer depending on magnitude and platform; both are tried explicitly, same fix as
    /// `BuddyActivityService.intValue`.
    fileprivate static func intValue(from element: Any?) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    /// The last `/`-separated segment of a plain URL string, e.g.
    /// `"https://x/y/z.apk"` -> `"z.apk"`. GitHub's `browser_download_url` values never carry a
    /// query string, so a plain split (matching `components(separatedBy:)`'s established idiom
    /// elsewhere in this codebase) is equivalent to Dart's `Uri.parse(apkUrl).pathSegments.last`
    /// without needing `URL.lastPathComponent` (no precedent for that API on this transpile target).
    fileprivate static func lastPathSegment(_ urlString: String) -> String {
        urlString.components(separatedBy: "/").last ?? ""
    }
}

// Internal (not `private`) rather than file-scoped: no test in this task needs to catch it by
// name today, but matches `BuddyActivityServiceError`'s established visibility precedent for a
// same-shaped internal error type in this codebase.
struct UpdateServiceError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Data models

struct AppVersionInfo: Equatable {
    let version: String
    let buildNumber: String
}

struct UpdateInfo: Equatable {
    let version: String
    let buildNumber: String
    let buildDate: Date
    let apkUrl: String
    let apkFileName: String
    let changelog: String?
    let isNightly: Bool
    let fileSizeBytes: Int

    /// Ported from `UpdateInfo.fromGithubJson` (lines 566-718). Version/build-number extraction
    /// comes from the release BODY (not `tag_name` alone): nightly releases try 3 ordered patterns
    /// against the body markdown, splitting on `+` for version/buildNumber; if none match, falls
    /// back to a synthetic construction from a `**Base Version**:` body field (default `0.0.2`)
    /// plus the tag's own `YYYYMMDD-HHMMSS` suffix, with `buildNumber` set to `published_at` as
    /// Unix epoch seconds. Stable releases start from the tag (leading `v` stripped), optionally
    /// overridden by a body-regex match only if STRICTLY LONGER than the tag-derived string (see
    /// `UpdateService.extractLooseVersionToken`'s doc comment for the resulting quirk this
    /// preserves); build number via a separate body regex, falling back to the release NAME field.
    /// The APK asset is the first `assets` entry whose `name` ends in `.apk`; `apkFileName` is
    /// re-derived from the download URL's last path segment, not read from the asset's own `name`.
    static func fromGithubJson(_ json: [String: Any], isNightly: Bool) -> UpdateInfo {
        let tagName = (json["tag_name"] as? String) ?? ""
        let releaseName = (json["name"] as? String) ?? tagName
        let body = (json["body"] as? String) ?? ""
        let lowerBody = body.lowercased()

        var apkUrl = ""
        var fileSizeBytes = 0
        if let assets = json["assets"] as? [Any] {
            for assetAny in assets {
                guard let asset = assetAny as? [String: Any] else { continue }
                let name = (asset["name"] as? String) ?? ""
                if name.hasSuffix(".apk") {
                    apkUrl = (asset["browser_download_url"] as? String) ?? ""
                    fileSizeBytes = UpdateService.intValue(from: asset["size"]) ?? 0
                    break
                }
            }
        }
        let apkFileName = apkUrl.isEmpty ? "" : UpdateService.lastPathSegment(apkUrl)

        let buildDate = UpdateService.parsePublishedAt(json) ?? Date()

        var version: String
        var buildNumber = ""

        if isNightly && tagName.hasPrefix("nightly-") {
            var fullVersion = UpdateService.extractBacktickedValue(lowerBody, markerLower: "**version**:")
            if fullVersion == nil {
                fullVersion = UpdateService.extractTokenValue(lowerBody, markerLower: "version:")
            }
            if fullVersion == nil {
                fullVersion = UpdateService.extractDashPrefixedBacktickedVersion(lowerBody)
            }

            if let fullVersion {
                let versionParts = fullVersion.components(separatedBy: "+")
                version = versionParts[0]
                if versionParts.count > 1 {
                    buildNumber = versionParts[1]
                }
                // else: Dart falls back to a `\+(\d+)` search within `fullVersion` here, which can
                // never match given `versionParts.count <= 1` already proves `fullVersion` contains
                // no `+` at all -- provably a no-op, so `buildNumber` correctly stays "".
            } else {
                let baseVersion = UpdateService.extractBacktickedValue(lowerBody, markerLower: "**base version**:") ?? "0.0.2"
                let tagSuffix = String(tagName.dropFirst("nightly-".count))
                version = "\(baseVersion)-nightly-\(tagSuffix)"
                buildNumber = String(Int64(buildDate.timeIntervalSince1970))
            }
        } else {
            version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            if let bodyVersion = UpdateService.extractLooseVersionToken(lowerBody), bodyVersion.count > version.count {
                version = bodyVersion
            }
            if let buildNum = UpdateService.extractDigitsAfterMarker(lowerBody, markerLower: "build number", allowColon: true) {
                buildNumber = buildNum
            } else if let fallback = UpdateService.extractDigitsAfterMarker(releaseName.lowercased(), markerLower: "build", allowColon: false) {
                buildNumber = fallback
            }
        }

        return UpdateInfo(
            version: version, buildNumber: buildNumber, buildDate: buildDate,
            apkUrl: apkUrl, apkFileName: apkFileName, changelog: json["body"] as? String,
            isNightly: isNightly, fileSizeBytes: fileSizeBytes
        )
    }
}

struct UpdateCheckResult {
    let hasUpdate: Bool
    let isNightly: Bool
    let updateInfo: UpdateInfo?
    let error: String?
}

struct UpdateDownloadResult {
    let success: Bool
    let filePath: String?
    let updateInfo: UpdateInfo?
    let error: String?
}

struct DownloadProgress {
    let downloadedBytes: Int
    let totalBytes: Int
    let progress: Double
    let speedBytesPerSecond: Double
    let estimatedRemainingSeconds: Double
}
