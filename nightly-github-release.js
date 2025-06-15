#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

class NightlyGitHubReleaser {    constructor() {
        this.projectRoot = __dirname;
        this.nightlyDir = path.join(this.projectRoot, 'nightly');
        this.githubRepo = this.detectGitHubRepo();
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const prefix = {
            'info': '🌙',
            'success': '✅',
            'error': '❌',
            'warning': '⚠️',
            'upload': '📤',
            'github': '🐙',
            'nightly': '🌃'
        }[type] || 'ℹ️';
        
        console.log(`[${timestamp}] ${prefix} ${message}`);
    }

    detectGitHubRepo() {
        try {
            const remoteUrl = execSync('git remote get-url origin', { encoding: 'utf8' }).trim();
            
            // Handle both HTTPS and SSH URLs
            let repoMatch = remoteUrl.match(/github\.com[/:]([\w-]+)\/([\w-]+)(?:\.git)?$/);
            
            if (repoMatch) {
                return `${repoMatch[1]}/${repoMatch[2]}`;
            }
            
            throw new Error('Could not parse GitHub repository from remote URL');
        } catch (error) {
            this.log(`Failed to detect GitHub repo: ${error.message}`, 'warning');
            return null;
        }
    }    checkGitHubCLI() {
        try {
            execSync('gh --version', { stdio: 'ignore' });
            this.log('GitHub CLI detected', 'github');
        } catch (error) {
            throw new Error(`
GitHub CLI not found. Please install it first:

Download from: https://cli.github.com/
Or install with PowerShell: winget install GitHub.cli

After installation, authenticate with: gh auth login
`);
        }

        // Check if authenticated
        try {
            execSync('gh auth status', { stdio: 'ignore' });
            this.log('GitHub CLI authenticated', 'success');
        } catch (error) {
            throw new Error(`
GitHub CLI not authenticated. Please run: gh auth login

This will open a web browser to authenticate with GitHub.
`);
        }
    }

    checkGitHubRepo() {
        if (!this.githubRepo) {
            throw new Error('GitHub repository not detected. Ensure you are in a git repository with GitHub origin.');
        }
        this.log(`Repository: ${this.githubRepo}`, 'github');
    }

    listNightlyBuilds() {
        if (!fs.existsSync(this.nightlyDir)) {
            throw new Error('No nightly builds found. Run nightly build first.');
        }

        const files = fs.readdirSync(this.nightlyDir);
        const nightlyAPKs = files
            .filter(file => file.startsWith('playtivity-nightly-') && file.endsWith('.apk'))
            .filter(file => !file.includes('latest'))
            .sort()
            .reverse(); // Most recent first

        if (nightlyAPKs.length === 0) {
            throw new Error('No nightly APK files found in nightly directory.');
        }

        return nightlyAPKs.map(apk => {
            const apkPath = path.join(this.nightlyDir, apk);
            const stats = fs.statSync(apkPath);
            
            // Extract build ID from filename
            const buildId = apk.match(/playtivity-nightly-(\d{8}-\d{6})-/)?.[1];
            const infoPath = buildId ? path.join(this.nightlyDir, `nightly-info-${buildId}.json`) : null;
            
            let buildInfo = null;
            if (infoPath && fs.existsSync(infoPath)) {
                try {
                    buildInfo = JSON.parse(fs.readFileSync(infoPath, 'utf8'));
                } catch (error) {
                    this.log(`Failed to read build info for ${apk}: ${error.message}`, 'warning');
                }
            }

            return {
                fileName: apk,
                path: apkPath,
                size: (stats.size / (1024 * 1024)).toFixed(2),
                created: stats.birthtime.toLocaleString(),
                buildId,
                buildInfo
            };
        });
    }

    selectNightlyBuild(nightlyBuilds, buildId = null) {
        if (buildId) {
            const build = nightlyBuilds.find(b => b.buildId === buildId);
            if (!build) {
                throw new Error(`Nightly build with ID ${buildId} not found.`);
            }
            return build;
        }

        // If no buildId specified, use the latest
        return nightlyBuilds[0];
    }

    generateChecksum(filePath) {
        const fileBuffer = fs.readFileSync(filePath);
        const hashSum = crypto.createHash('sha256');
        hashSum.update(fileBuffer);
        return hashSum.digest('hex');
    }    createGitHubRelease(build, prerelease = true) {
        this.log(`Creating GitHub release for nightly build: ${build.fileName}`, 'github');

        const tagName = `nightly-${build.buildId}`;
        const releaseName = `🌙 Nightly Build ${build.buildId}`;
        
        // Generate release body
        const checksum = this.generateChecksum(build.path);
        const releaseBody = this.generateReleaseNotes(build, checksum);

        // Create release using GitHub CLI
        this.createReleaseWithGHCLI(tagName, releaseName, releaseBody, build, prerelease);
    }    createReleaseWithGHCLI(tagName, releaseName, releaseBody, build, prerelease) {
        const prereleaseFlag = prerelease ? '--prerelease' : '';
        const notesFile = path.join(this.nightlyDir, `release-notes-${build.buildId}.md`);
        
        // Write release notes to temporary file
        fs.writeFileSync(notesFile, releaseBody);

        try {
            // Create release with GitHub CLI
            const createCmd = `gh release create "${tagName}" "${build.path}" --title "${releaseName}" --notes-file "${notesFile}" ${prereleaseFlag}`;
            
            this.log('Creating release with GitHub CLI...', 'upload');
            execSync(createCmd, { 
                stdio: 'inherit',
                cwd: this.projectRoot
            });
            
            this.log(`✅ GitHub release created: https://github.com/${this.githubRepo}/releases/tag/${tagName}`, 'success');
            
        } catch (error) {
            throw new Error(`Failed to create GitHub release: ${error.message}`);
        } finally {
            // Clean up temporary file
            if (fs.existsSync(notesFile)) {
                fs.unlinkSync(notesFile);
            }
        }
    }    generateReleaseNotes(build, checksum) {
        const buildInfo = build.buildInfo;
        
        let releaseNotes = `# 🌙 Playtivity Nightly Build

**⚠️ WARNING: This is a NIGHTLY DEVELOPMENT BUILD ⚠️**

This build contains the latest development code and may be unstable. Use at your own risk!

## Build Information

- **Build Date**: ${build.created}
- **Build ID**: ${build.buildId}
- **File Size**: ${build.size} MB
- **File Name**: ${build.fileName}

## Version Information
`;        if (buildInfo) {
            releaseNotes += `
- **Version**: ${buildInfo.version?.fullVersion || buildInfo.version?.versionName || 'Unknown'}
- **Base Version**: ${buildInfo.baseVersion?.fullVersion || buildInfo.baseVersion?.versionName || 'Unknown'}

## Git Information

- **Branch**: ${buildInfo.git?.branch || 'unknown'}
- **Commit**: ${buildInfo.git?.commit || 'unknown'}
- **Commit Message**: ${buildInfo.git?.commitMessage || 'Unknown'}
- **Author**: ${buildInfo.git?.author || 'unknown'}
- **Date**: ${buildInfo.git?.date || 'unknown'}

## Build Environment

- **Flutter Version**: ${buildInfo.environment?.flutterVersion || 'unknown'}
- **Dart Version**: ${buildInfo.environment?.dartVersion || 'unknown'}
- **Gradle Version**: ${buildInfo.environment?.gradleVersion || 'unknown'}
- **Java Version**: ${buildInfo.environment?.javaVersion || 'unknown'}
`;
        }

        releaseNotes += `
## Security

- **SHA256 Checksum**: \`${checksum}\`

## Installation

1. Download the APK file from the assets below
2. Enable "Install from unknown sources" in your Android settings
3. Install the APK file

## What's New in This Nightly

This nightly build includes all commits up to ${buildInfo?.git?.commit?.substring(0, 7) || 'unknown'}.

**Note**: This is an automated nightly release. For stable releases, please see the main releases page.

---
*Built automatically from the latest development code*
`;

        return releaseNotes;
    }

    async releaseNightly(buildId = null, prerelease = true) {
        try {            this.log('🌙 Starting Nightly GitHub Release Process', 'nightly');
            
            // Validation
            this.checkGitHubCLI();
            this.checkGitHubRepo();
            
            // List available nightly builds
            this.log('Looking for nightly builds...', 'info');
            const nightlyBuilds = this.listNightlyBuilds();
            
            this.log(`Found ${nightlyBuilds.length} nightly build(s)`, 'success');
            
            // Select build to release
            const selectedBuild = this.selectNightlyBuild(nightlyBuilds, buildId);
            
            this.log(`Selected build: ${selectedBuild.fileName} (${selectedBuild.size} MB)`, 'info');
              if (selectedBuild.buildInfo) {
                const commit = selectedBuild.buildInfo.git?.commit || 'unknown';
                const branch = selectedBuild.buildInfo.git?.branch || 'unknown';
                const commitShort = commit.length > 7 ? commit.substring(0, 7) : commit;
                this.log(`Git: ${branch}@${commitShort}`, 'info');
            }
            
            // Create GitHub release
            this.createGitHubRelease(selectedBuild, prerelease);
            
            this.log('🎉 Nightly GitHub release completed successfully!', 'success');
            
        } catch (error) {
            this.log(`❌ Nightly GitHub release failed: ${error.message}`, 'error');
            process.exit(1);
        }
    }
}

function showHelp() {
    console.log(`
🌙 Playtivity Nightly GitHub Releaser

Usage: node nightly-github-release.js [options]

Options:
  --build-id <id>       - Release specific nightly build (e.g., 20250614-143022)
  --stable              - Mark as stable release (not prerelease)
  --help, -h            - Show this help message

Requirements:
  - GitHub CLI (gh) installed and authenticated
  - GitHub repository with write access
  - Existing nightly builds in nightly/ folder

Setup:
  1. Install GitHub CLI: https://cli.github.com/
  2. Authenticate: gh auth login
  3. Ensure you have write access to the repository

Examples:
  node nightly-github-release.js                    # Release latest nightly
  node nightly-github-release.js --build-id 20250614-143022  # Release specific build
  node nightly-github-release.js --stable           # Mark as stable release

The script will:
  ✅ Find available nightly builds
  ✅ Create GitHub release with detailed notes
  ✅ Upload APK as release asset
  ✅ Include git commit information
  ✅ Generate SHA256 checksum
  ✅ Mark as prerelease by default
`);
}

// Main execution
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.includes('--help') || args.includes('-h')) {
        showHelp();
        process.exit(0);
    }
    
    // Parse options
    let buildId = null;
    let prerelease = true;
    
    const buildIdIndex = args.indexOf('--build-id');
    if (buildIdIndex !== -1 && args[buildIdIndex + 1]) {
        buildId = args[buildIdIndex + 1];
    }
    
    if (args.includes('--stable')) {
        prerelease = false;
    }
    
    const releaser = new NightlyGitHubReleaser();
    releaser.releaseNightly(buildId, prerelease);
}

module.exports = NightlyGitHubReleaser;
