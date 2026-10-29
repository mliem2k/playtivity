#!/usr/bin/env bun

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

class NightlyBuilder {
    constructor() {
        this.projectRoot = path.join(__dirname, '..');
        this.pubspecPath = path.join(this.projectRoot, 'version.yml');
        this.outputDir = path.join(this.projectRoot, 'nightly');
        this.apkPath = path.join(this.projectRoot, 'android', 'app', 'build', 'outputs', 'apk', 'release', 'app-release.apk');
        this.keystorePath = path.join(this.projectRoot, 'release-key.jks');
        this.keystoreBase64Path = path.join(this.projectRoot, 'keystore.base64.txt');
        this.githubRepo = this.detectGitHubRepo();
        this.buildInfo = {};
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const labels = {
            'info': 'INFO',
            'success': 'OK',
            'error': 'ERR',
            'warning': 'WARN',
            'build': 'BUILD',
            'nightly': 'NIGHTLY',
            'github': 'GITHUB',
            'upload': 'UPLOAD',
            'clean': 'CLEAN'
        };

        console.log(`[${timestamp}] [${labels[type] || 'INFO'}] ${message}`);
    }

    // ==================== Setup & Validation ====================

    ensureOutputDirectory() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir, { recursive: true });
            this.log(`Created nightly directory: ${this.outputDir}`);
        }
    }

    detectGitHubRepo() {
        try {
            const remoteUrl = execSync('git remote get-url origin', { encoding: 'utf8' }).trim();
            const repoMatch = remoteUrl.match(/github\.com[/:]([^/]+)\/([^/.]+)(?:\.git)?$/);
            
            if (repoMatch) {
                return `${repoMatch[1]}/${repoMatch[2]}`;
            }
            
            throw new Error('Could not parse GitHub repository from remote URL');
        } catch (error) {
            this.log(`Failed to detect GitHub repo: ${error.message}`, 'warning');
            return null;
        }
    }

    checkGitHubCLI() {
        try {
            execSync('gh --version', { stdio: 'ignore' });
            this.log('GitHub CLI detected', 'github');
        } catch {
            throw new Error(`
GitHub CLI not found. Please install it first:

Windows: winget install GitHub.cli
Mac: brew install gh
Linux: See https://cli.github.com/

After installation, authenticate with: gh auth login
`);
        }

        try {
            execSync('gh auth status', { stdio: 'ignore' });
            this.log('GitHub CLI authenticated', 'success');
        } catch {
            throw new Error('GitHub CLI not authenticated. Please run: gh auth login');
        }
    }

    // ==================== Version Management ====================

    readPubspec() {
        return fs.readFileSync(this.pubspecPath, 'utf8');
    }

    writePubspec(content) {
        fs.writeFileSync(this.pubspecPath, content, 'utf8');
    }

    parseVersion(versionLine) {
        const match = versionLine.match(/version:\s*(.+)/);
        if (!match) {
            throw new Error('Invalid version format in version.yml');
        }

        const fullVersion = match[1].trim();
        const [versionName, buildNumber] = fullVersion.split('+');
        
        return {
            versionName: versionName || '0.0.1',
            buildNumber: parseInt(buildNumber) || 1,
            fullVersion
        };
    }

    extractBaseVersion(versionName) {
        // Remove any existing nightly suffixes
        if (versionName.includes('-nightly-')) {
            return versionName.split('-nightly-')[0];
        }
        return versionName;
    }

    createNightlyVersion() {
        this.log('Creating nightly version', 'nightly');
        
        const content = this.readPubspec();
        const lines = content.split('\n');
        
        let versionLineIndex = -1;
        let currentVersion = null;

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].startsWith('version:')) {
                versionLineIndex = i;
                currentVersion = this.parseVersion(lines[i]);
                break;
            }
        }

        if (!currentVersion) {
            throw new Error('Version line not found in version.yml');
        }

        this.log(`Current version: ${currentVersion.fullVersion}`);
        
        const baseVersionName = this.extractBaseVersion(currentVersion.versionName);
        const now = new Date();
        const dateStr = now.toISOString().slice(0, 10).replace(/-/g, '');
        const timeStr = now.toTimeString().slice(0, 8).replace(/:/g, '');
        
        const nightlyVersionName = `${baseVersionName}-nightly-${dateStr}-${timeStr}`;
        const nightlyBuildNumber = Math.floor(Date.now() / 1000);
        const nightlyFullVersion = `${nightlyVersionName}+${nightlyBuildNumber}`;
        
        lines[versionLineIndex] = `version: ${nightlyFullVersion}`;
        this.writePubspec(lines.join('\n'));
        
        this.log(`Nightly version created: ${nightlyFullVersion}`, 'success');
        
        return {
            original: currentVersion,
            nightly: {
                versionName: nightlyVersionName,
                buildNumber: nightlyBuildNumber,
                fullVersion: nightlyFullVersion
            },
            backup: content,
            dateStr,
            timeStr,
            baseVersion: baseVersionName
        };
    }

    restoreOriginalVersion(backup) {
        this.log('Restoring original version', 'info');
        this.writePubspec(backup);
    }

    // ==================== Build Information ====================

    getGitInfo() {
        try {
            const branch = execSync('git rev-parse --abbrev-ref HEAD', { encoding: 'utf8' }).trim();
            const commit = execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();
            const commitShort = commit.substring(0, 7);
            const commitMessage = execSync('git log -1 --pretty=%B', { encoding: 'utf8' }).trim();
            const author = execSync('git log -1 --pretty=%an', { encoding: 'utf8' }).trim();
            const date = execSync('git log -1 --pretty=%ad --date=iso', { encoding: 'utf8' }).trim();
            
            return { branch, commit, commitShort, commitMessage, author, date };
        } catch (error) {
            this.log('Failed to get git info', 'warning');
            return {
                branch: 'unknown',
                commit: 'unknown',
                commitShort: 'unknown',
                commitMessage: 'Git info unavailable',
                author: 'unknown',
                date: new Date().toISOString()
            };
        }
    }

    getBuildEnvironment() {
        const env = {};
        try {
            env.expoVersion = JSON.parse(fs.readFileSync(path.join(this.projectRoot, 'node_modules', 'expo', 'package.json'), 'utf8')).version;
        } catch {
            env.expoVersion = 'unknown';
        }
        env.bunVersion = Bun.version;
        return env;
    }

    // ==================== Build Process ====================

    runCommand(command, description) {
        this.log(`${description}...`, 'build');
        try {
            execSync(command, { 
                cwd: this.projectRoot,
                stdio: 'inherit'
            });
            this.log(`${description} completed`, 'success');
            return true;
        } catch (error) {
            this.log(`${description} failed: ${error.message}`, 'error');
            throw error;
        }
    }

    setupSigningForBuild() {
        // Ensure the release keystore exists (decode from base64 if needed).
        if (!fs.existsSync(this.keystorePath)) {
            if (fs.existsSync(this.keystoreBase64Path)) {
                try {
                    const base64Content = fs.readFileSync(this.keystoreBase64Path, 'utf8').trim();
                    fs.writeFileSync(this.keystorePath, Buffer.from(base64Content, 'base64'));
                    this.log('Keystore decoded from base64', 'success');
                } catch (error) {
                    throw new Error(`Failed to decode keystore: ${error.message}`);
                }
            } else {
                throw new Error('No keystore found. Ensure release-key.jks or keystore.base64.txt exists.');
            }
        }

        // Inject env vars so build.gradle.kts picks up the release signing config
        // instead of falling back to the debug key.
        process.env.ANDROID_KEYSTORE_PATH     = this.keystorePath;
        process.env.ANDROID_KEYSTORE_PASSWORD = process.env.ANDROID_KEYSTORE_PASSWORD || 'playtivity123';
        process.env.ANDROID_KEY_ALIAS         = process.env.ANDROID_KEY_ALIAS         || 'playtivity-key';
        process.env.ANDROID_KEY_PASSWORD      = process.env.ANDROID_KEY_PASSWORD      || 'playtivity123';

        this.log('Release signing configured', 'success');
    }

    buildNightlyAPK() {
        this.log('Starting nightly APK build', 'build');

        // Signing env vars must be set before gradle runs, otherwise the APK falls back to the
        // debug key and conflicts with release-signed installs.
        this.setupSigningForBuild();

        try {
            if (process.env.PLAYTIVITY_BUILDER) {
                this.buildOnRemote(process.env.PLAYTIVITY_BUILDER);
                return true;
            }
            // Same ccache speed-up as the remote builder, when it is installed here.
            try {
                execSync('ccache --version', { stdio: 'pipe' });
                process.env.CMAKE_C_COMPILER_LAUNCHER = 'ccache';
                process.env.CMAKE_CXX_COMPILER_LAUNCHER = 'ccache';
                process.env.CCACHE_SLOPPINESS = 'pch_defines,time_macros';
            } catch {}
            this.runCommand('bun install --frozen-lockfile', 'Installing dependencies');
            // Prebuild regenerates android/ from app.config.js, which reads version.yml, so the
            // nightly version written above is what lands in versionName and versionCode.
            const clean = this.shouldCleanBuild() ? ' --clean' : '';
            this.runCommand(`bunx expo prebuild --platform android --no-install${clean}`, 'Generating Android project');
            this.runCommand('cd android && ./gradlew assembleRelease -PreactNativeArchitectures=arm64-v8a', 'Building APK');
            return true;
        } catch (error) {
            this.log(`Build failed: ${error.message}`, 'error');
            return false;
        }
    }

    // Builds on a Windows machine reachable over ssh (PLAYTIVITY_BUILDER=<ssh host>), then signs
    // here, so the release keystore never leaves this machine.
    buildOnRemote(host) {
        const remoteDir = 'C:/b/pt';
        const apkOut = this.apkPath;
        const tracked = execSync('git ls-files -z --cached --others --exclude-standard', { cwd: this.projectRoot, maxBuffer: 64 * 1024 * 1024 })
            .toString('utf8').split('\0')
            .filter((p) => p && !/^(landing|releases|nightly|builds|screenshots|docs)\//.test(p) && !/jks|keystore/.test(p));
        const listFile = path.join(this.outputDir, '.sync-files');
        fs.mkdirSync(this.outputDir, { recursive: true });
        fs.writeFileSync(listFile, tracked.join('\n'));

        this.runCommand(`ssh ${host} "if not exist C:\\b\\pt mkdir C:\\b\\pt"`, `Preparing ${host}`);
        // Source folders are replaced, not merged: a route or module deleted here must not survive there.
        const remoteWin = 'C:\\b\\pt';
        this.runCommand(`ssh ${host} "for %d in (app src tests plugins) do if exist ${remoteWin}\\%d rmdir /s /q ${remoteWin}\\%d"`, `Clearing stale sources on ${host}`);
        this.runCommand(`COPYFILE_DISABLE=1 tar -c -T "${listFile}" -f - | ssh ${host} "tar -x -C ${remoteDir} -f -"`, `Syncing source to ${host}`);
        this.runCommand(`scp -q scripts/builder/build-android.ps1 ${host}:C:/b/build-android.ps1`, 'Copying build script');
        this.runCommand(`ssh ${host} "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\b\\build-android.ps1"`, `Building on ${host}`);

        fs.mkdirSync(path.dirname(apkOut), { recursive: true });
        this.runCommand(`scp -q ${host}:${remoteDir}/android/app/build/outputs/apk/release/app-release.apk "${apkOut}"`, 'Fetching APK');
        this.signApk(apkOut);
    }

    signApk(apk) {
        const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || '/opt/homebrew/share/android-commandlinetools';
        const tools = path.join(sdk, 'build-tools');
        const latest = fs.readdirSync(tools).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).pop();
        const apksigner = path.join(tools, latest, 'apksigner');
        const signed = `${apk}.signed`;
        this.runCommand(
            `"${apksigner}" sign --ks "${process.env.ANDROID_KEYSTORE_PATH}" --ks-key-alias "${process.env.ANDROID_KEY_ALIAS}" ` +
            `--ks-pass env:ANDROID_KEYSTORE_PASSWORD --key-pass env:ANDROID_KEY_PASSWORD --out "${signed}" "${apk}"`,
            'Signing APK with the release key'
        );
        this.runCommand(`"${apksigner}" verify "${signed}"`, 'Verifying signature');
        fs.renameSync(signed, apk);
    }

    shouldCleanBuild() {
        return !fs.existsSync(path.join(this.projectRoot, 'android')) ||
               process.env.FORCE_CLEAN === 'true' ||
               process.argv.includes('--clean');
    }

    // ==================== File Management ====================

    copyNightlyAPK(versionInfo, gitInfo) {
        if (!fs.existsSync(this.apkPath)) {
            throw new Error(`APK not found at: ${this.apkPath}`);
        }

        const fileName = `playtivity-nightly-${versionInfo.dateStr}-${versionInfo.timeStr}-${gitInfo.commitShort}.apk`;
        const destPath = path.join(this.outputDir, fileName);
        
        fs.copyFileSync(this.apkPath, destPath);
        this.log(`APK copied to: ${fileName}`, 'success');
        
        // Create latest symlink
        const latestPath = path.join(this.outputDir, 'playtivity-latest-nightly.apk');
        if (fs.existsSync(latestPath)) {
            fs.unlinkSync(latestPath);
        }
        fs.copyFileSync(this.apkPath, latestPath);
        
        const stats = fs.statSync(destPath);
        return {
            fileName,
            path: destPath,
            latestPath,
            size: (stats.size / (1024 * 1024)).toFixed(2),
            sizeBytes: stats.size
        };
    }

    generateChecksum(filePath) {
        const fileBuffer = fs.readFileSync(filePath);
        const hash = crypto.createHash('sha256');
        hash.update(fileBuffer);
        return hash.digest('hex');
    }

    saveBuildInfo(versionInfo, gitInfo, apkInfo) {
        const buildId = `${versionInfo.dateStr}-${versionInfo.timeStr}`;
        const infoPath = path.join(this.outputDir, `nightly-info-${buildId}.json`);
        
        this.buildInfo = {
            buildId,
            buildType: 'nightly',
            buildDate: new Date().toISOString(),
            version: versionInfo.nightly,
            baseVersion: versionInfo.baseVersion,
            git: gitInfo,
            apk: {
                fileName: apkInfo.fileName,
                size: apkInfo.size,
                checksum: this.generateChecksum(apkInfo.path)
            },
            environment: this.getBuildEnvironment()
        };
        
        fs.writeFileSync(infoPath, JSON.stringify(this.buildInfo, null, 2));
        
        // Also save as latest
        const latestInfoPath = path.join(this.outputDir, 'latest-nightly-info.json');
        fs.writeFileSync(latestInfoPath, JSON.stringify(this.buildInfo, null, 2));
        
        this.log('Build info saved', 'success');
        return this.buildInfo;
    }

    // ==================== GitHub Release ====================

    cleanDraftReleases() {
        try {
            const raw = execSync('gh release list --json tagName,isDraft --limit 30 --include-drafts', {
                encoding: 'utf8',
                cwd: this.projectRoot,
                stdio: ['ignore', 'pipe', 'ignore'],
            });
            const releases = JSON.parse(raw);
            const drafts = releases.filter(r => r.isDraft && r.tagName.startsWith('nightly-'));
            for (const draft of drafts) {
                this.log(`Removing orphaned draft: ${draft.tagName}`, 'clean');
                try {
                    execSync(`gh release delete "${draft.tagName}" --yes --cleanup-tag`, {
                        stdio: 'ignore',
                        cwd: this.projectRoot,
                    });
                } catch (e) {
                    this.log(`Could not delete ${draft.tagName}: ${e.message}`, 'warning');
                }
            }
            if (drafts.length > 0) {
                this.log(`Removed ${drafts.length} orphaned draft(s)`, 'success');
            }
        } catch (e) {
            this.log(`Draft cleanup skipped: ${e.message}`, 'warning');
        }
    }

    createGitHubRelease(apkInfo, prerelease = true) {
        this.log('Creating GitHub release', 'github');
        this.cleanDraftReleases();

        const tagName = `nightly-${this.buildInfo.buildId}`;
        const releaseName = `Nightly Build ${this.buildInfo.buildId}`;
        const releaseNotes = this.generateReleaseNotes(apkInfo);

        const notesFile = path.join(this.outputDir, `release-notes-temp.md`);
        fs.writeFileSync(notesFile, releaseNotes);

        try {
            const prereleaseFlag = prerelease ? '--prerelease' : '';
            const createCmd = `gh release create "${tagName}" "${apkInfo.path}" --title "${releaseName}" --notes-file "${notesFile}" ${prereleaseFlag}`;

            this.log('Uploading to GitHub...', 'upload');
            execSync(createCmd, {
                stdio: 'inherit',
                cwd: this.projectRoot
            });

            this.log(`GitHub release created: https://github.com/${this.githubRepo}/releases/tag/${tagName}`, 'success');

            // Keep a rolling "latest-nightly" release so that
            // github.com/.../releases/latest always resolves and the repo
            // sidebar shows a non-zero release count.
            this.updateLatestNightlyRelease(apkInfo, releaseNotes);
        } catch (error) {
            throw new Error(`Failed to create GitHub release: ${error.message}`);
        } finally {
            if (fs.existsSync(notesFile)) {
                fs.unlinkSync(notesFile);
            }
        }
    }

    updateLatestNightlyRelease(apkInfo, releaseNotes) {
        this.log('Updating latest-nightly release...', 'github');
        const latestTag = 'latest-nightly';
        const latestNotes = `${releaseNotes}\n\n---\n*This tag always points to the most recent nightly build.*`;
        const notesFile = path.join(this.outputDir, 'release-notes-latest-temp.md');
        fs.writeFileSync(notesFile, latestNotes);

        try {
            // Delete existing latest-nightly release + tag if present.
            try {
                execSync(`gh release delete "${latestTag}" --yes --cleanup-tag`, {
                    stdio: 'ignore',
                    cwd: this.projectRoot,
                });
                this.log('Removed previous latest-nightly release', 'clean');
            } catch (_) {
                // Fine if it didn't exist yet.
            }

            execSync(
                `gh release create "${latestTag}" "${apkInfo.path}" --title "Latest Nightly" --notes-file "${notesFile}"`,
                { stdio: 'inherit', cwd: this.projectRoot }
            );
            this.log(`latest-nightly updated: https://github.com/${this.githubRepo}/releases/latest`, 'success');
        } catch (error) {
            this.log(`Failed to update latest-nightly (non-fatal): ${error.message}`, 'warning');
        } finally {
            if (fs.existsSync(notesFile)) fs.unlinkSync(notesFile);
        }
    }

    generateReleaseNotes(apkInfo) {
        const { version, baseVersion, git, apk, environment } = this.buildInfo;

        return `Nightly development build — unstable, not for production use.

**Version**: \`${version.fullVersion}\`
**Base Version**: \`${baseVersion}\`
**Commit**: \`${git.commitShort}\` — ${git.commitMessage}
**Branch**: \`${git.branch}\`
**Expo**: ${environment.expoVersion} / Bun ${environment.bunVersion}

**APK**: ${apk.fileName} (${apk.size} MB)
**SHA256**: \`${apk.checksum}\`

Download the APK from the assets below, enable "Install from unknown sources" on your device, and install it.

Report issues with build ID: \`${this.buildInfo.buildId}\``;
    }

    // ==================== Cleanup ====================

    cleanOldBuilds(keepCount = 5) {
        this.log(`Cleaning old builds (keeping ${keepCount} recent)`, 'clean');
        
        try {
            const files = fs.readdirSync(this.outputDir);
            const nightlyAPKs = files
                .filter(f => f.startsWith('playtivity-nightly-') && f.endsWith('.apk'))
                .filter(f => !f.includes('latest'))
                .sort()
                .reverse();
            
            if (nightlyAPKs.length > keepCount) {
                const toDelete = nightlyAPKs.slice(keepCount);
                
                toDelete.forEach(apk => {
                    const apkPath = path.join(this.outputDir, apk);
                    const buildId = apk.match(/(\d{8}-\d{6})/)?.[1];
                    
                    // Delete APK
                    if (fs.existsSync(apkPath)) fs.unlinkSync(apkPath);
                    
                    // Delete associated files
                    if (buildId) {
                        const infoFile = path.join(this.outputDir, `nightly-info-${buildId}.json`);
                        if (fs.existsSync(infoFile)) fs.unlinkSync(infoFile);
                    }
                });
                
                this.log(`Cleaned ${toDelete.length} old builds`, 'success');
            }
        } catch (error) {
            this.log(`Failed to clean old builds: ${error.message}`, 'warning');
        }
    }

    // ==================== Main Process ====================

    async run(options = {}) {
        const {
            skipGitHub = false,
            prerelease = true,
            keepBuilds = 5,
            clean = false
        } = options;

        let versionBackup = null;

        try {
            this.log('Starting Nightly Build & Release Process', 'nightly');
            
            // Setup
            this.ensureOutputDirectory();
            
            if (!skipGitHub) {
                this.checkGitHubCLI();
                if (!this.githubRepo) {
                    throw new Error('GitHub repository not detected');
                }
                this.log(`Repository: ${this.githubRepo}`, 'github');
            }

            // Get git info
            const gitInfo = this.getGitInfo();
            this.log(`Building from: ${gitInfo.branch}@${gitInfo.commitShort}`, 'info');
            
            // Create nightly version
            const versionInfo = this.createNightlyVersion();
            versionBackup = versionInfo.backup;
            
            // Build APK
            if (!this.buildNightlyAPK()) {
                throw new Error('APK build failed');
            }
            
            // Copy and process APK
            const apkInfo = this.copyNightlyAPK(versionInfo, gitInfo);
            
            // Save build information
            this.saveBuildInfo(versionInfo, gitInfo, apkInfo);
            
            // Create GitHub release
            if (!skipGitHub) {
                this.createGitHubRelease(apkInfo, prerelease);
            }
            
            // Clean old builds
            this.cleanOldBuilds(keepBuilds);
            
            // Restore original version
            this.restoreOriginalVersion(versionBackup);
            versionBackup = null;
            
            // Success summary
            this.log('Nightly build & release completed!', 'success');
            this.printSummary(versionInfo, gitInfo, apkInfo, skipGitHub);
            
        } catch (error) {
            // Restore original version on error
            if (versionBackup) {
                try {
                    this.restoreOriginalVersion(versionBackup);
                    this.log('Original version restored', 'info');
                } catch (restoreError) {
                    this.log(`Failed to restore version: ${restoreError.message}`, 'error');
                }
            }
            
            this.log(`Process failed: ${error.message}`, 'error');
            process.exit(1);
        }
    }

    printSummary(versionInfo, gitInfo, apkInfo, skipGitHub) {
        console.log('\nBuild Summary:');
        console.log(`   Version: ${versionInfo.nightly.fullVersion}`);
        console.log(`   Base: ${versionInfo.baseVersion}`);
        console.log(`   Branch: ${gitInfo.branch}`);
        console.log(`   Commit: ${gitInfo.commitShort}`);
        console.log(`   APK Size: ${apkInfo.size} MB`);
        console.log(`   Location: ${apkInfo.fileName}`);

        if (!skipGitHub && this.githubRepo) {
            console.log(`\nGitHub Release:`);
            console.log(`   https://github.com/${this.githubRepo}/releases/tag/nightly-${this.buildInfo.buildId}`);
        }

        console.log(`   APK: ${apkInfo.latestPath}`);
        console.log('\nNOTE: Nightly build — not for production use.');
    }
}

// ==================== CLI Interface ====================

function showHelp() {
    console.log(`
Playtivity Nightly Builder & Releaser

Usage: bun nightly.js [options]

Options:
  --skip-github         Skip GitHub release (local build only)
  --stable              Mark as stable release (not prerelease)
  --keep <n>            Number of old builds to keep (default: 5)
  --clean               Force clean build
  --help, -h            Show this help

Examples:
  bun nightly.js                    # Build and release to GitHub
  bun nightly.js --skip-github      # Local build only
  bun nightly.js --stable           # Create stable release
  bun nightly.js --keep 10          # Keep 10 old builds
  bun nightly.js --clean            # Force clean rebuild

Requirements:
  - Android SDK and JDK 17 installed
  - GitHub CLI (gh) installed and authenticated
  - Git repository with GitHub remote

The script will:
  - Create nightly version with timestamp
  - Build optimized APK
  - Generate build metadata and checksums
  - Create GitHub release with APK
  - Clean old builds automatically
  - Restore original version after build
`);
}

// Main execution
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.includes('--help') || args.includes('-h')) {
        showHelp();
        process.exit(0);
    }
    
    const options = {
        skipGitHub: args.includes('--skip-github'),
        prerelease: !args.includes('--stable'),
        clean: args.includes('--clean')
    };
    
    // Parse keep builds
    const keepIndex = args.indexOf('--keep');
    if (keepIndex !== -1 && args[keepIndex + 1]) {
        options.keepBuilds = parseInt(args[keepIndex + 1]) || 5;
    }
    
    const builder = new NightlyBuilder();
    builder.run(options);
}

module.exports = NightlyBuilder;