#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

class NightlyBuilder {
    constructor() {
        this.projectRoot = __dirname;
        this.pubspecPath = path.join(this.projectRoot, 'pubspec.yaml');
        this.outputDir = path.join(this.projectRoot, 'nightly');
        this.apkPath = path.join(this.projectRoot, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const prefix = {
            'info': '🌙',
            'success': '✅',
            'error': '❌',
            'warning': '⚠️',
            'build': '🔨',
            'nightly': '🌃'
        }[type] || 'ℹ️';
        
        console.log(`[${timestamp}] ${prefix} ${message}`);
    }

    ensureOutputDirectory() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir, { recursive: true });
            this.log(`Created nightly directory: ${this.outputDir}`);
        }
    }

    readPubspec() {
        try {
            const content = fs.readFileSync(this.pubspecPath, 'utf8');
            return content;
        } catch (error) {
            throw new Error(`Failed to read pubspec.yaml: ${error.message}`);
        }
    }

    writePubspec(content) {
        try {
            fs.writeFileSync(this.pubspecPath, content, 'utf8');
        } catch (error) {
            throw new Error(`Failed to write pubspec.yaml: ${error.message}`);
        }
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

    createNightlyVersion() {
        this.log('Creating nightly version from current pubspec.yaml', 'nightly');
        
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

        if (versionLineIndex === -1) {
            throw new Error('Version line not found in pubspec.yaml');
        }

        this.log(`Base version: ${currentVersion.fullVersion}`);

        // Create nightly version with date and time
        const now = new Date();
        const dateStr = now.toISOString().split('T')[0].replace(/-/g, ''); // YYYYMMDD
        const timeStr = now.toTimeString().split(' ')[0].replace(/:/g, ''); // HHMMSS
        
        // Format: base-version-nightly-YYYYMMDD-HHMMSS+build
        const nightlyVersionName = `${currentVersion.versionName}-nightly-${dateStr}-${timeStr}`;
        const nightlyBuildNumber = Math.floor(Date.now() / 1000); // Unix timestamp for uniqueness
        
        const nightlyFullVersion = `${nightlyVersionName}+${nightlyBuildNumber}`;
        
        // Backup original version
        const backupContent = content;
        
        // Update version line for build
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
            backup: backupContent,
            dateStr,
            timeStr
        };
    }

    restoreOriginalVersion(backup) {
        this.log('Restoring original version', 'info');
        this.writePubspec(backup);
    }    getBuildEnvironmentInfo() {
        const environment = {};
        
        try {
            // Get Flutter version
            let flutterCommand = 'flutter';
            try {
                execSync('fvm --version', { stdio: 'pipe' });
                flutterCommand = 'fvm flutter';
            } catch (error) {
                // FVM not available, use system Flutter
            }
            
            const flutterVersion = execSync(`${flutterCommand} --version --machine`, { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();
            
            const flutterInfo = JSON.parse(flutterVersion);
            environment.flutterVersion = flutterInfo.frameworkVersion || 'unknown';
            environment.dartVersion = flutterInfo.dartSdkVersion || 'unknown';
        } catch (error) {
            environment.flutterVersion = 'unknown';
            environment.dartVersion = 'unknown';
        }

        try {
            // Get Gradle version from gradle wrapper
            const gradlePath = process.platform === 'win32' ? '.\\gradlew.bat' : './gradlew';
            const gradleVersion = execSync(`${gradlePath} --version`, { 
                stdio: 'pipe', 
                encoding: 'utf8',
                cwd: path.join(this.projectRoot, 'android')
            });
            
            const gradleMatch = gradleVersion.match(/Gradle (\d+\.\d+(?:\.\d+)?)/);
            environment.gradleVersion = gradleMatch ? gradleMatch[1] : 'unknown';
        } catch (error) {
            environment.gradleVersion = 'unknown';
        }        try {
            // Get Java version (java -version outputs to stderr, redirect to stdout)
            const javaVersion = execSync('java -version 2>&1', { 
                stdio: 'pipe',
                encoding: 'utf8'
            });
            
            // Match various Java version formats
            let javaMatch = javaVersion.match(/openjdk version "([^"]+)"/i);
            if (!javaMatch) {
                javaMatch = javaVersion.match(/java version "([^"]+)"/i);
            }
            
            environment.javaVersion = javaMatch ? javaMatch[1] : 'unknown';
        } catch (error) {
            environment.javaVersion = 'unknown';
        }

        return environment;
    }

    getGitInfo() {
        try {
            const branch = execSync('git rev-parse --abbrev-ref HEAD', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();
            
            const commit = execSync('git rev-parse --short HEAD', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();
            
            const commitCount = execSync('git rev-list --count HEAD', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();

            // Get commit message
            const commitMessage = execSync('git log -1 --pretty=%B', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();

            // Get commit author
            const author = execSync('git log -1 --pretty=%an', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();

            // Get commit date
            const date = execSync('git log -1 --pretty=%ad --date=iso', { 
                stdio: 'pipe', 
                encoding: 'utf8' 
            }).trim();
            
            return {
                branch,
                commit,
                commitCount,
                commitMessage,
                author,
                date
            };
        } catch (error) {
            this.log('Failed to get git info, using defaults', 'warning');
            return {
                branch: 'unknown',
                commit: 'unknown',
                commitCount: '0',
                commitMessage: 'Git info unavailable',
                author: 'unknown',
                date: 'unknown'
            };
        }
    }

    runCommand(command, description) {
        this.log(`${description}...`, 'build');
        try {
            const output = execSync(command, { 
                cwd: this.projectRoot,
                stdio: 'pipe',
                encoding: 'utf8'
            });
            this.log(`${description} completed`, 'success');
            return output;
        } catch (error) {
            this.log(`${description} failed: ${error.message}`, 'error');
            throw error;
        }
    }

    buildNightlyAPK() {
        this.log('Starting nightly APK build process', 'build');

        let flutterCommand = 'flutter';
        try {
            execSync('fvm --version', { stdio: 'pipe' });
            flutterCommand = 'fvm flutter';
            this.log('Using FVM for Flutter commands');
        } catch (error) {
            this.log('FVM not found, using system Flutter');
        }

        try {
            // Get dependencies
            this.runCommand(`${flutterCommand} pub get`, 'Getting dependencies');
            
            // Clean previous builds
            this.runCommand(`${flutterCommand} clean`, 'Cleaning previous builds');
            
            // Run tests (optional, continue on failure)
            try {
                this.runCommand(`${flutterCommand} test`, 'Running tests');
            } catch (error) {
                this.log('Tests failed, but continuing with nightly build', 'warning');
            }
            
            // Build APK with nightly configuration
            this.runCommand(`${flutterCommand} build apk --release --dart-define=BUILD_TYPE=nightly`, 'Building nightly APK');
            
            return true;
        } catch (error) {
            this.log(`Nightly build failed: ${error.message}`, 'error');
            return false;
        }
    }

    copyNightlyAPK(versionInfo, gitInfo) {
        if (!fs.existsSync(this.apkPath)) {
            throw new Error(`APK not found at: ${this.apkPath}`);
        }

        const { dateStr, timeStr } = versionInfo;
        const fileName = `playtivity-nightly-${dateStr}-${timeStr}-${gitInfo.commit}.apk`;
        const destinationPath = path.join(this.outputDir, fileName);
        
        fs.copyFileSync(this.apkPath, destinationPath);
        
        this.log(`Nightly APK copied to: ${destinationPath}`, 'success');
        
        // Create a "latest-nightly" copy for convenience
        const latestPath = path.join(this.outputDir, 'playtivity-latest-nightly.apk');
        if (fs.existsSync(latestPath)) {
            fs.unlinkSync(latestPath);
        }
        fs.copyFileSync(this.apkPath, latestPath);
        
        return {
            timestampedPath: destinationPath,
            latestPath: latestPath,
            fileName: fileName
        };
    }

    getAPKInfo(apkPath) {
        try {
            const stats = fs.statSync(apkPath);
            const sizeInMB = (stats.size / (1024 * 1024)).toFixed(2);
            return {
                size: sizeInMB,
                created: stats.birthtime.toLocaleString(),
                sizeBytes: stats.size
            };
        } catch (error) {
            return { size: 'Unknown', created: 'Unknown', sizeBytes: 0 };
        }
    }

    generateNightlyInfo(versionInfo, gitInfo, apkInfo) {
        const infoPath = path.join(this.outputDir, `nightly-info-${versionInfo.dateStr}-${versionInfo.timeStr}.json`);
        
        const nightlyInfo = {
            buildType: 'nightly',
            buildDate: new Date().toISOString(),
            version: versionInfo.nightly,
            baseVersion: versionInfo.original,
            git: gitInfo,
            apk: {
                fileName: apkInfo.fileName,
                size: apkInfo.size,
                sizeBytes: apkInfo.sizeBytes
            },            environment: this.getBuildEnvironmentInfo()
        };
        
        fs.writeFileSync(infoPath, JSON.stringify(nightlyInfo, null, 2));
        
        // Also create latest info
        const latestInfoPath = path.join(this.outputDir, 'latest-nightly-info.json');
        fs.writeFileSync(latestInfoPath, JSON.stringify(nightlyInfo, null, 2));
        
        this.log(`Nightly info saved: ${infoPath}`, 'success');
        
        return { infoPath, latestInfoPath, info: nightlyInfo };
    }

    generateNightlyNotes(versionInfo, gitInfo, apkInfo, nightlyInfo) {
        const notesPath = path.join(this.outputDir, `nightly-notes-${versionInfo.dateStr}-${versionInfo.timeStr}.md`);
        
        const notes = `# 🌙 Playtivity Nightly Build

**⚠️ WARNING: This is a NIGHTLY DEVELOPMENT BUILD ⚠️**

This build contains the latest development code and may be unstable. Use at your own risk!

## Build Information
- **Build Type:** Nightly Development Build
- **Version:** \`${versionInfo.nightly.fullVersion}\`
- **Base Version:** \`${versionInfo.original.fullVersion}\`
- **Build Date:** ${new Date().toLocaleString()}
- **Build ID:** ${versionInfo.dateStr}-${versionInfo.timeStr}

## Source Information
- **Branch:** \`${gitInfo.branch}\`
- **Commit:** \`${gitInfo.commit}\`
- **Commit Count:** ${gitInfo.commitCount}
- **Last Commit:** ${gitInfo.commitMessage}

## APK Details
- **File:** \`${apkInfo.fileName}\`
- **Size:** ${apkInfo.size} MB
- **Install Command:** \`adb install "${apkInfo.fileName}"\`

## ⚠️ Important Notes

### This is a Nightly Build
- **Unstable**: May contain bugs, crashes, or incomplete features
- **Testing Only**: Not recommended for production use
- **Development**: Built from latest development code
- **No Support**: No official support provided for nightly builds

### Installation
1. **Backup**: Backup your data before installing
2. **Uninstall**: May need to uninstall previous versions
3. **Enable**: Enable "Install from unknown sources" in Android settings
4. **Install**: Use ADB or manual installation

### Feedback
- Report issues on GitHub with "nightly" label
- Include build ID: \`${versionInfo.dateStr}-${versionInfo.timeStr}\`
- Mention commit: \`${gitInfo.commit}\`

### Next Steps
- Test new features and report feedback
- Check for newer nightly builds regularly
- Wait for stable releases for production use

---
*This nightly build was automatically generated from the latest development code.*
*Build System: Playtivity Nightly Builder v1.0*
`;

        fs.writeFileSync(notesPath, notes);
        
        // Also create latest notes
        const latestNotesPath = path.join(this.outputDir, 'latest-nightly-notes.md');
        fs.writeFileSync(latestNotesPath, notes);
        
        this.log(`Nightly notes generated: ${notesPath}`, 'success');
        
        return { notesPath, latestNotesPath };
    }

    cleanOldNightlyBuilds(keepCount = 5) {
        this.log(`Cleaning old nightly builds (keeping ${keepCount} most recent)`, 'info');
        
        try {
            const files = fs.readdirSync(this.outputDir);
            
            // Filter APK files with nightly pattern
            const nightlyAPKs = files
                .filter(file => file.startsWith('playtivity-nightly-') && file.endsWith('.apk'))
                .filter(file => !file.includes('latest'))
                .sort()
                .reverse(); // Most recent first
            
            if (nightlyAPKs.length > keepCount) {
                const toDelete = nightlyAPKs.slice(keepCount);
                
                toDelete.forEach(apkFile => {
                    const apkPath = path.join(this.outputDir, apkFile);
                    const baseName = apkFile.replace('.apk', '');
                    
                    // Delete APK
                    if (fs.existsSync(apkPath)) {
                        fs.unlinkSync(apkPath);
                    }
                    
                    // Delete associated info and notes files
                    const infoFile = path.join(this.outputDir, `nightly-info-${baseName.replace('playtivity-nightly-', '')}.json`);
                    const notesFile = path.join(this.outputDir, `nightly-notes-${baseName.replace('playtivity-nightly-', '')}.md`);
                    
                    if (fs.existsSync(infoFile)) {
                        fs.unlinkSync(infoFile);
                    }
                    
                    if (fs.existsSync(notesFile)) {
                        fs.unlinkSync(notesFile);
                    }
                });
                
                this.log(`Cleaned ${toDelete.length} old nightly builds`, 'success');
            } else {
                this.log('No old nightly builds to clean', 'info');
            }
        } catch (error) {
            this.log(`Failed to clean old builds: ${error.message}`, 'warning');
        }
    }

    async buildNightly(keepBuilds = 5) {
        let versionBackup = null;
        
        try {
            this.log('🌃 Starting Playtivity Nightly Build Process', 'nightly');
            
            // Setup
            this.ensureOutputDirectory();
            
            // Get git information
            const gitInfo = this.getGitInfo();
            this.log(`Building from branch: ${gitInfo.branch} (${gitInfo.commit})`, 'info');
            
            // Create nightly version
            const versionInfo = this.createNightlyVersion();
            versionBackup = versionInfo.backup;
            
            // Build APK
            const buildSuccess = this.buildNightlyAPK();
            
            if (!buildSuccess) {
                throw new Error('Nightly build failed');
            }
            
            // Copy APK to nightly directory
            const apkInfo = this.copyNightlyAPK(versionInfo, gitInfo);
            const fileInfo = this.getAPKInfo(apkInfo.timestampedPath);
            
            // Generate build information and notes
            const nightlyInfoResult = this.generateNightlyInfo(versionInfo, gitInfo, { ...apkInfo, ...fileInfo });
            const notesResult = this.generateNightlyNotes(versionInfo, gitInfo, { ...apkInfo, ...fileInfo }, nightlyInfoResult.info);
            
            // Clean old builds
            this.cleanOldNightlyBuilds(keepBuilds);
            
            // Restore original version
            this.restoreOriginalVersion(versionBackup);
            versionBackup = null;
            
            // Success summary
            this.log('🎉 Nightly build completed successfully!', 'success');
            
            console.log('\n🌙 Nightly Build Summary:');
            console.log(`   Build Type: NIGHTLY DEVELOPMENT BUILD`);
            console.log(`   Version: ${versionInfo.nightly.fullVersion}`);
            console.log(`   Base Version: ${versionInfo.original.fullVersion}`);
            console.log(`   Branch: ${gitInfo.branch}`);
            console.log(`   Commit: ${gitInfo.commit}`);
            console.log(`   APK Size: ${fileInfo.size} MB`);
            console.log(`   Location: ${apkInfo.timestampedPath}`);
            console.log(`   Latest: ${apkInfo.latestPath}`);
            
            console.log('\n📋 Generated Files:');
            console.log(`   Info: ${nightlyInfoResult.infoPath}`);
            console.log(`   Notes: ${notesResult.notesPath}`);
            
            console.log('\n⚠️  IMPORTANT:');
            console.log('   This is a NIGHTLY DEVELOPMENT BUILD');
            console.log('   - May contain bugs and incomplete features');
            console.log('   - For testing purposes only');
            console.log('   - Not recommended for production use');
            
            console.log('\n📱 Installation:');
            console.log(`   adb install "${apkInfo.latestPath}"`);
            console.log('   or transfer to your device and install manually');
            
        } catch (error) {
            // Restore original version if something went wrong
            if (versionBackup) {
                try {
                    this.restoreOriginalVersion(versionBackup);
                    this.log('Original version restored after error', 'info');
                } catch (restoreError) {
                    this.log(`Failed to restore original version: ${restoreError.message}`, 'error');
                }
            }
            
            this.log(`Nightly build process failed: ${error.message}`, 'error');
            process.exit(1);
        }
    }
}

// CLI interface
function showHelp() {
    console.log(`
🌙 Playtivity Nightly Builder

Usage: node nightly-apk.js [options]

Options:
  --keep-builds <count>  - Number of old nightly builds to keep (default: 5)
  --help, -h            - Show this help message

Examples:
  node nightly-apk.js                # Build nightly with default settings
  node nightly-apk.js --keep-builds 10  # Keep 10 old builds

About Nightly Builds:
  - Built from current development code
  - Versioned with date, time, and git commit
  - Marked clearly as NIGHTLY DEVELOPMENT BUILDS
  - Include git information and build metadata
  - Automatically clean old builds
  - NOT for production use

The script will:
  ✅ Create nightly version with timestamp
  ✅ Build APK with nightly branding
  ✅ Include git commit information
  ✅ Generate detailed build notes
  ✅ Clean old nightly builds
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
    
    // Parse keep-builds option
    let keepBuilds = 5;
    const keepIndex = args.indexOf('--keep-builds');
    if (keepIndex !== -1 && args[keepIndex + 1]) {
        keepBuilds = parseInt(args[keepIndex + 1]) || 5;
    }
    
    const builder = new NightlyBuilder();
    builder.buildNightly(keepBuilds);
}

module.exports = NightlyBuilder;
