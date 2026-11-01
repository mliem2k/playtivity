const { test } = require('bun:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const NightlyBuilder = require('../nightly');
const NightlyReleaser = require('../nightly-release');
const APKReleaser = require('../release-apk');

test('stable release builds APK and bundle together', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'playtivity_release_test_'));
    const bundle = path.join(dir, 'native/app/build/outputs/bundle/productionRelease/app-production-release.aab');
    fs.mkdirSync(path.dirname(bundle), { recursive: true });
    fs.writeFileSync(bundle, 'old');
    const builder = new NightlyBuilder();
    builder.projectRoot = dir;
    builder.setupSigningForBuild = () => {};
    builder.shouldCleanBuild = () => false;
    builder.verifyApk = () => {};
    let command;
    builder.runCommand = (value) => {
        command = value;
        assert.equal(fs.existsSync(bundle), false);
        fs.writeFileSync(bundle, 'new');
    };
    try {
        assert.equal(builder.buildNightlyAPK(true), true);
        assert.match(command, /:app:assembleProductionRelease :app:bundleProductionRelease/);
        const releaser = new NightlyReleaser();
        releaser.projectRoot = dir;
        releaser.runCommand = () => { throw new Error('Bundle must not be rebuilt separately'); };
        assert.equal(releaser.buildSignedBundle(), true);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test('other stable build entry point shares the APK build with its bundle', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'playtivity_bundle_test_'));
    const original = NightlyBuilder.prototype.buildNightlyAPK;
    let choice;
    NightlyBuilder.prototype.buildNightlyAPK = (buildBundle) => { choice = buildBundle; return true; };
    try {
        const releaser = new APKReleaser();
        assert.equal(releaser.buildReleaseAPK(true), true);
        assert.equal(choice, true);
        releaser.bundlePath = path.join(dir, 'missing.aab');
        releaser.runCommand = () => { throw new Error('Bundle must not be rebuilt separately'); };
        assert.equal(releaser.buildReleaseBundle(), false);
        fs.writeFileSync(releaser.bundlePath, 'built');
        assert.equal(releaser.buildReleaseBundle(), true);
    } finally {
        NightlyBuilder.prototype.buildNightlyAPK = original;
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test('bundle-free release ignores stale App Bundle', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'playtivity_release_files_test_'));
    const apk = path.join(dir, 'native/app/build/outputs/apk/production/release/app-production-release.apk');
    const bundle = path.join(dir, 'native/app/build/outputs/bundle/productionRelease/app-production-release.aab');
    fs.mkdirSync(path.dirname(apk), { recursive: true });
    fs.mkdirSync(path.dirname(bundle), { recursive: true });
    fs.writeFileSync(apk, 'current');
    fs.writeFileSync(bundle, 'stale');
    const releaser = new NightlyReleaser();
    releaser.projectRoot = dir;
    releaser.releasesDir = dir;
    try {
        const info = releaser.copyReleaseFiles({ versionName: '0.0.6' }, {}, false);
        assert.deepEqual(info.files.map(file => file.type), ['APK']);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test('release passes the bundle choice into its APK build', () => {
    const original = NightlyBuilder.prototype.buildNightlyAPK;
    let choice;
    NightlyBuilder.prototype.buildNightlyAPK = (buildBundle) => { choice = buildBundle; return true; };
    try {
        assert.equal(new NightlyReleaser().buildSignedAPK(true), true);
        assert.equal(choice, true);
    } finally {
        NightlyBuilder.prototype.buildNightlyAPK = original;
    }
});
