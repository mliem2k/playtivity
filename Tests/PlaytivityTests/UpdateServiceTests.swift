import Foundation
import XCTest
@testable import Playtivity

final class UpdateServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UpdateService.githubReleasesFetchOverride = nil
        UpdateService.downloadFetchOverride = nil
        // The real Bundle.main.infoDictionary seen by the unit-test host process is NOT the app's
        // own version (see UpdateService.currentAppVersionOverride's doc comment): on native
        // `swift test` it is the `xctest` tool's own bundle info (e.g. "16.0"), which would make
        // every hasUpdate comparison below depend on the Xcode version running the suite. Pin a
        // deterministic low "current version" for every test in this file instead.
        UpdateService.currentAppVersionOverride = AppVersionInfo(version: "0.0.2", buildNumber: "1")
    }

    override func tearDown() {
        UpdateService.githubReleasesFetchOverride = nil
        UpdateService.downloadFetchOverride = nil
        UpdateService.currentAppVersionOverride = nil
        super.tearDown()
    }

    private func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "UpdateServiceTests.\(UUID().uuidString)")!
    }

    // MARK: - extractBaseVersion

    func testExtractBaseVersionStripsBuildMetadata() {
        XCTAssertEqual(UpdateService.extractBaseVersion("1.2.3+45"), "1.2.3")
    }

    func testExtractBaseVersionStripsNightlySuffix() {
        XCTAssertEqual(
            UpdateService.extractBaseVersion("0.0.4-nightly-20260611-050901+1781212141"),
            "0.0.4"
        )
    }

    func testExtractBaseVersionLeavesPlainVersionUnchanged() {
        XCTAssertEqual(UpdateService.extractBaseVersion("1.0.0"), "1.0.0")
    }

    // MARK: - isNewerVersion

    func testIsNewerVersionBothNightlyAlwaysReturnsFalse() {
        // Pins the Dart original's actual (slightly odd) behavior: this path
        // always returns false, callers must use isNewerNightly instead.
        XCTAssertFalse(UpdateService.isNewerVersion(
            current: "0.0.4-nightly-20260610-000000",
            new: "0.0.4-nightly-20260611-000000"
        ))
    }

    func testIsNewerVersionNightlyToStableRequiresStrictlyGreaterBase() {
        XCTAssertTrue(UpdateService.isNewerVersion(current: "0.0.4-nightly-20260611-050901", new: "0.0.5"))
        XCTAssertFalse(UpdateService.isNewerVersion(current: "0.0.5-nightly-20260611-050901", new: "0.0.5"))
    }

    func testIsNewerVersionStableToNightlyAlwaysReturnsFalse() {
        XCTAssertFalse(UpdateService.isNewerVersion(current: "0.0.4", new: "0.0.5-nightly-20260611-050901"))
    }

    func testIsNewerVersionStableToStableSemverComparison() {
        XCTAssertTrue(UpdateService.isNewerVersion(current: "0.0.4", new: "0.0.5"))
        XCTAssertFalse(UpdateService.isNewerVersion(current: "0.0.5", new: "0.0.4"))
        XCTAssertFalse(UpdateService.isNewerVersion(current: "0.0.5", new: "0.0.5"))
        XCTAssertTrue(UpdateService.isNewerVersion(current: "0.9.0", new: "1.0.0"))
    }

    func testIsNewerVersionPreReleaseVsStable() {
        // A version with no pre-release suffix beats one with a suffix at
        // the same base version.
        XCTAssertTrue(UpdateService.isNewerVersion(current: "1.0.0-beta.1", new: "1.0.0"))
        XCTAssertFalse(UpdateService.isNewerVersion(current: "1.0.0", new: "1.0.0-beta.1"))
    }

    // MARK: - isNewerNightly

    func testIsNewerNightlyComparesBuildTimestamps() {
        XCTAssertTrue(UpdateService.isNewerNightly(
            current: "0.0.4-nightly-20260610-050901",
            new: "0.0.4-nightly-20260611-050901"
        ))
        XCTAssertFalse(UpdateService.isNewerNightly(
            current: "0.0.4-nightly-20260611-050901",
            new: "0.0.4-nightly-20260610-050901"
        ))
    }

    func testIsNewerNightlyReturnsFalseWhenEitherSideUnparseable() {
        XCTAssertFalse(UpdateService.isNewerNightly(current: "not-a-version", new: "0.0.4-nightly-20260611-050901"))
    }

    // MARK: - isCurrentVersionNightly

    func testIsCurrentVersionNightlyChecksDashWrappedSubstring() {
        XCTAssertTrue(UpdateService.isCurrentVersionNightly("0.0.4-nightly-20260611-050901"))
        XCTAssertFalse(UpdateService.isCurrentVersionNightly("0.0.4"))
    }

    // MARK: - checkForUpdates / GitHub Releases check

    func testCheckForUpdatesPicksNewestPublishedStableRelease() async {
        UpdateService.githubReleasesFetchOverride = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/mliem2k/playtivity/releases")
            let releases: [[String: Any]] = [
                ["tag_name": "v0.0.4", "name": "v0.0.4", "body": "**Version**: `0.0.4`\n**Build Number**: `1`",
                 "published_at": "2026-06-01T00:00:00Z", "assets": [
                    ["name": "playtivity-0.0.4.apk", "browser_download_url": "https://github.com/x/0.0.4.apk", "size": 1000],
                 ]],
                ["tag_name": "v0.0.5", "name": "v0.0.5", "body": "**Version**: `0.0.5`\n**Build Number**: `1`",
                 "published_at": "2026-06-15T00:00:00Z", "assets": [
                    ["name": "playtivity-0.0.5.apk", "browser_download_url": "https://github.com/x/0.0.5.apk", "size": 2000],
                 ]],
            ]
            let data = try! JSONSerialization.data(withJSONObject: releases)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { UpdateService.githubReleasesFetchOverride = nil }

        let result = await UpdateService.checkForUpdates(forceCheck: true, userDefaults: freshUserDefaults())
        XCTAssertTrue(result.hasUpdate)
        XCTAssertEqual(result.updateInfo?.version, "0.0.5")
        XCTAssertEqual(result.updateInfo?.apkUrl, "https://github.com/x/0.0.5.apk")
    }

    func testCheckForUpdatesExcludesLatestNightlyPointerTagFromNightlySelection() async {
        let ud = freshUserDefaults()
        await UpdateService.setNightlyBuildPreference(true, userDefaults: ud)
        UpdateService.githubReleasesFetchOverride = { _ in
            let releases: [[String: Any]] = [
                ["tag_name": "latest-nightly", "name": "latest", "body": "", "published_at": "2026-07-01T00:00:00Z", "assets": [Any]()],
                ["tag_name": "nightly-20260701-050901", "name": "nightly", "body": "**Version**: `0.0.5-nightly-20260701-050901+123`",
                 "published_at": "2026-07-01T05:09:01Z", "assets": [
                    ["name": "playtivity-nightly.apk", "browser_download_url": "https://github.com/x/n.apk", "size": 500],
                 ]],
            ]
            let data = try! JSONSerialization.data(withJSONObject: releases)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { UpdateService.githubReleasesFetchOverride = nil }

        let result = await UpdateService.checkForUpdates(forceCheck: true, userDefaults: ud)
        // The floating "latest-nightly" pointer tag must never be selected as
        // the nightly candidate itself (it starts with "latest-", not "nightly-").
        XCTAssertNotEqual(result.updateInfo?.buildNumber, "")
        // NOTE: adjusted from the brief's literal "0.0.5" to the value the ported Dart algorithm
        // actually produces. UpdateInfo.fromGithubJson's nightly tier-1 regex
        // (`\*\*Version\*\*:\s*`([^`]+)``) captures everything between the backticks verbatim and
        // only splits on "+" for the build number (update_service.dart lines 623-634); it never
        // strips the "-nightly-..." suffix from the stored `version`. Verified directly against
        // /tmp/ref_update_service.dart: `version = versionParts[0]` where
        // `versionParts = fullVersion.split('+')` and fullVersion is the raw backtick capture, so
        // for body "**Version**: `0.0.5-nightly-20260701-050901+123`" the real Dart output is
        // "0.0.5-nightly-20260701-050901", not "0.0.5". See task-6-report.md for the full trace.
        XCTAssertEqual(result.updateInfo?.version, "0.0.5-nightly-20260701-050901")
        XCTAssertEqual(result.updateInfo?.buildNumber, "123")
    }

    func testCheckForUpdatesReturnsNoUpdateWhenCurrentIsAlreadyLatest() async {
        // Requires stubbing getCurrentAppVersion too; if this codebase's
        // package_info equivalent can't be overridden directly, structure
        // UpdateService.checkForUpdates to accept an injectable "current
        // version" seam the same way other services inject their I/O, and use
        // that seam here instead of relying on the real running app version.
        let ud = freshUserDefaults()
        UpdateService.githubReleasesFetchOverride = { _ in
            let releases: [[String: Any]] = [
                ["tag_name": "v0.0.1", "name": "v0.0.1", "body": "**Version**: `0.0.1`",
                 "published_at": "2020-01-01T00:00:00Z", "assets": [Any]()],
            ]
            let data = try! JSONSerialization.data(withJSONObject: releases)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { UpdateService.githubReleasesFetchOverride = nil }
        let result = await UpdateService.checkForUpdates(forceCheck: true, userDefaults: ud)
        XCTAssertFalse(result.hasUpdate)
    }

    func testShouldCheckForUpdatesRespectsFrequencyGuardAndForceOverride() async {
        let ud = freshUserDefaults()
        UpdateService.githubReleasesFetchOverride = { _ in (200, "[]") }
        defer { UpdateService.githubReleasesFetchOverride = nil }

        let first = await UpdateService.checkForUpdates(userDefaults: ud) // records "checked"
        XCTAssertNotNil(first)
        let secondWithoutForce = await UpdateService.shouldCheckForUpdates(userDefaults: ud)
        XCTAssertFalse(secondWithoutForce, "must not allow a second check within the frequency window")
        let secondResult = await UpdateService.checkForUpdates(forceCheck: true, userDefaults: ud)
        XCTAssertNotNil(secondResult) // forceCheck bypasses the guard entirely
    }

    // MARK: - downloadUpdate

    func testDownloadUpdateSkipsRedownloadWhenExistingFileMatchesExpectedSize() async {
        let info = UpdateInfo(
            version: "0.0.5", buildNumber: "1", buildDate: Date(),
            apkUrl: "https://github.com/x/y.apk", apkFileName: "test-skip-redownload.apk",
            changelog: nil, isNightly: false, fileSizeBytes: 5
        )
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(info.apkFileName)
        try? "12345".data(using: .utf8)!.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }

        var downloadWasCalled = false
        UpdateService.downloadFetchOverride = { _ in
            downloadWasCalled = true
            return (200, Data(), 5)
        }
        defer { UpdateService.downloadFetchOverride = nil }

        let result = await UpdateService.downloadUpdate(info)
        XCTAssertTrue(result.success)
        XCTAssertFalse(downloadWasCalled, "must skip re-download when an existing file already matches the expected size")
    }

    func testDownloadUpdateReportsProgressAndCompletes() async {
        let info = UpdateInfo(
            version: "0.0.5", buildNumber: "1", buildDate: Date(),
            apkUrl: "https://github.com/x/y.apk", apkFileName: "test-progress-\(UUID().uuidString).apk",
            changelog: nil, isNightly: false, fileSizeBytes: 10
        )
        UpdateService.downloadFetchOverride = { _ in
            // Data(repeating:count:) is `@available(*, unavailable)` on Skip's transpile target
            // (SkipFoundation/Data.swift); Data(count:) is the supported zero-filled equivalent.
            (200, Data(count: 10), 10)
        }
        defer {
            UpdateService.downloadFetchOverride = nil
            let path = FileManager.default.temporaryDirectory.appendingPathComponent(info.apkFileName)
            try? FileManager.default.removeItem(at: path)
        }

        var lastProgress: DownloadProgress?
        let result = await UpdateService.downloadUpdate(info) { progress in lastProgress = progress }
        XCTAssertTrue(result.success)
        XCTAssertEqual(lastProgress?.downloadedBytes, 10)
        XCTAssertEqual(lastProgress?.progress, 1.0)
    }
}
