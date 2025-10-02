#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

class NightlyBuilder {
    constructor() {
        this.projectRoot = __dirname;
        this.pubspecPath = path.join(this.projectRoot, 'pubspec.yaml');
        this.outputDir = path.join(this.projectRoot, 'nightly');
        this.apkPath = path.join(this.projectRoot, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
        this.githubRepo = this.detectGitHubRepo();
        this.buildInfo = {};
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const emojis = {
            'info': '📘',
            'success': '✅',
            'error': '❌',
            'warning': '⚠️',
            'build': '🔨',
            'nightly': '🌙',
            'github': '🐙',
            'upload': '📤',
            'clean': '🧹'
        };
        
        console.log(`[${timestamp}] ${emojis[type] || 'ℹ️'} ${message}`);
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
            throw new Error('Invalid version format in pubspec.yaml');
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
            throw new Error('Version line not found in pubspec.yaml');
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
            let flutterCmd = 'flutter';
            try {
                execSync('fvm --version', { stdio: 'pipe' });
                flutterCmd = 'fvm flutter';
            } catch {}
            
            const flutterVersion = execSync(`${flutterCmd} --version --machine`, { encoding: 'utf8' });
            const flutterInfo = JSON.parse(flutterVersion);
            env.flutterVersion = flutterInfo.frameworkVersion || 'unknown';
            env.dartVersion = flutterInfo.dartSdkVersion || 'unknown';
        } catch {
            env.flutterVersion = 'unknown';
            env.dartVersion = 'unknown';
        }

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

    buildNightlyAPK() {
        this.log('Starting nightly APK build', 'build');

        let flutterCommand = 'flutter';
        try {
            execSync('fvm --version', { stdio: 'pipe' });
            flutterCommand = 'fvm flutter';
            this.log('Using FVM for Flutter commands');
        } catch {
            this.log('Using system Flutter');
        }

        try {
            // Smart dependency management
            const pubspecLockModified = this.isPubspecLockModified();
            if (pubspecLockModified) {
                this.runCommand(`${flutterCommand} pub get`, 'Getting dependencies');
            } else {
                this.log('Dependencies up to date, skipping pub get', 'info');
            }

            // Smart clean - only when necessary
            if (this.shouldCleanBuild()) {
                this.runCommand(`${flutterCommand} clean`, 'Cleaning build');
            }

            // Build APK with optimizations
            const buildCmd = [
                `${flutterCommand} build apk`,
                '--release',
                '--target-platform android-arm64',
                '--no-tree-shake-icons'
            ].join(' ');

            this.runCommand(buildCmd, 'Building APK');
            return true;
        } catch (error) {
            this.log(`Build failed: ${error.message}`, 'error');
            return false;
        }
    }

    isPubspecLockModified() {
        try {
            const status = execSync('git status pubspec.lock --porcelain', { encoding: 'utf8' });
            return status.trim().length > 0;
        } catch {
            return true; // Safe default
        }
    }

    shouldCleanBuild() {
        const buildDir = path.join(this.projectRoot, 'build');
        return !fs.existsSync(buildDir) || 
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

    createGitHubRelease(apkInfo, prerelease = true) {
        this.log('Creating GitHub release', 'github');

        const tagName = `nightly-${this.buildInfo.buildId}`;
        const releaseName = `🌙 Nightly Build ${this.buildInfo.buildId}`;
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
        } catch (error) {
            throw new Error(`Failed to create GitHub release: ${error.message}`);
        } finally {
            if (fs.existsSync(notesFile)) {
                fs.unlinkSync(notesFile);
            }
        }
    }

    generateReleaseNotes(apkInfo) {
        const { version, baseVersion, git, apk, environment } = this.buildInfo;

        return `# 🌙 Playtivity Nightly Build

**⚠️ NIGHTLY DEVELOPMENT BUILD - Use at your own risk!**

## Build Information
- **Version**: \`${version.fullVersion}\`
- **Base Version**: \`${baseVersion}\`
- **Build Date**: ${new Date().toLocaleString()}
- **Build ID**: \`${this.buildInfo.buildId}\`

## Git Information
- **Branch**: \`${git.branch}\`
- **Commit**: \`${git.commit}\`
- **Message**: "${git.commitMessage}"
- **Author**: ${git.author}

## Build Environment
- **Flutter**: ${environment.flutterVersion}
- **Dart**: ${environment.dartVersion}

## APK Details
- **File**: ${apk.fileName}
- **Size**: ${apk.size} MB
- **SHA256**: \`${apk.checksum}\`

## Installation

### Android Device
1. Download the APK from the assets section below
2. Enable "Install from unknown sources" in your device settings
3. Open and install the APK

### Using ADB
\`\`\`bash
adb install ${apk.fileName}
\`\`\`

## ⚠️ Important Notes
- This is unstable development code
- May contain bugs or incomplete features
- Not recommended for production use
- Always backup your data before installing

## Checking for Updates
The app includes an automatic update checker for nightly builds. Enable nightly updates in Settings to receive automatic update notifications.

## Feedback
Report issues with build ID: \`${this.buildInfo.buildId}\`

---
*Automated nightly build from commit ${git.commitShort}*`;
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
            this.log('🌙 Starting Nightly Build & Release Process', 'nightly');
            
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
            this.log('🎉 Nightly build & release completed!', 'success');
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
        console.log('\n📊 Build Summary:');
        console.log(`   Version: ${versionInfo.nightly.fullVersion}`);
        console.log(`   Base: ${versionInfo.baseVersion}`);
        console.log(`   Branch: ${gitInfo.branch}`);
        console.log(`   Commit: ${gitInfo.commitShort}`);
        console.log(`   APK Size: ${apkInfo.size} MB`);
        console.log(`   Location: ${apkInfo.fileName}`);
        
        if (!skipGitHub && this.githubRepo) {
            console.log(`\n🐙 GitHub Release:`);
            console.log(`   https://github.com/${this.githubRepo}/releases/tag/nightly-${this.buildInfo.buildId}`);
        }
        
        console.log('\n📱 Installation:');
        console.log(`   adb install "${apkInfo.latestPath}"`);
        
        console.log('\n⚠️  This is a NIGHTLY BUILD - not for production use!');
    }
}

// ==================== CLI Interface ====================

function showHelp() {
    console.log(`
🌙 Playtivity Nightly Builder & Releaser

Usage: node nightly.js [options]

Options:
  --skip-github         Skip GitHub release (local build only)
  --stable              Mark as stable release (not prerelease)
  --keep <n>            Number of old builds to keep (default: 5)
  --clean               Force clean build
  --help, -h            Show this help

Examples:
  node nightly.js                    # Build and release to GitHub
  node nightly.js --skip-github      # Local build only
  node nightly.js --stable           # Create stable release
  node nightly.js --keep 10          # Keep 10 old builds
  node nightly.js --clean            # Force clean rebuild

Requirements:
  - Flutter SDK installed
  - GitHub CLI (gh) installed and authenticated
  - Git repository with GitHub remote

The script will:
  ✅ Create nightly version with timestamp
  ✅ Build optimized APK
  ✅ Generate build metadata and checksums
  ✅ Create GitHub release with APK
  ✅ Clean old builds automatically
  ✅ Restore original version after build
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