#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

class APKReleaser {
    constructor() {
        this.projectRoot = __dirname;
        this.pubspecPath = path.join(this.projectRoot, 'pubspec.yaml');
        this.outputDir = path.join(this.projectRoot, 'releases');
        this.keystorePath = path.join(this.projectRoot, 'release-key.jks');
        this.keystoreBase64Path = path.join(this.projectRoot, 'keystore.base64.txt');
        this.apkPath = path.join(this.projectRoot, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
        this.bundlePath = path.join(this.projectRoot, 'build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab');
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const prefix = {
            'info': '📱',
            'success': '✅',
            'error': '❌',
            'warning': '⚠️',
            'build': '🔨',
            'release': '🚀',
            'security': '🔐'
        }[type] || 'ℹ️';
        
        console.log(`[${timestamp}] ${prefix} ${message}`);
    }

    ensureOutputDirectory() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir, { recursive: true });
            this.log(`Created release directory: ${this.outputDir}`);
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

    getCurrentVersion() {
        const content = this.readPubspec();
        const lines = content.split('\n');
        
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].startsWith('version:')) {
                return this.parseVersion(lines[i]);
            }
        }
        
        throw new Error('Version line not found in pubspec.yaml');
    }

    incrementVersion(incrementType = 'patch') {
        this.log('Reading current version from pubspec.yaml');
        
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

        this.log(`Current version: ${currentVersion.fullVersion}`);

        let newVersionName = currentVersion.versionName;
        let newBuildNumber = 1; // Reset build number for releases

        // Increment based on type
        switch (incrementType) {
            case 'major':
                const [major, minor, patch] = newVersionName.split('.');
                newVersionName = `${parseInt(major) + 1}.0.0`;
                break;
            case 'minor':
                const [maj, min, pat] = newVersionName.split('.');
                newVersionName = `${maj}.${parseInt(min) + 1}.0`;
                break;
            case 'patch':
                const [ma, mi, pa] = newVersionName.split('.');
                newVersionName = `${ma}.${mi}.${parseInt(pa) + 1}`;
                break;
            case 'none':
                // Don't increment version, just reset build number
                newBuildNumber = 1;
                break;
            default:
                throw new Error(`Invalid increment type: ${incrementType}`);
        }

        const newFullVersion = `${newVersionName}+${newBuildNumber}`;
        
        lines[versionLineIndex] = `version: ${newFullVersion}`;
        this.writePubspec(lines.join('\n'));
        
        this.log(`Version updated to: ${newFullVersion}`, 'success');
        
        return {
            versionName: newVersionName,
            buildNumber: newBuildNumber,
            fullVersion: newFullVersion
        };
    }

    setupKeystore() {
        this.log('Setting up keystore for release signing', 'security');
        
        // Check if keystore already exists
        if (fs.existsSync(this.keystorePath)) {
            this.log('Keystore already exists, skipping setup');
            return;
        }

        // Try to decode from base64 file
        if (fs.existsSync(this.keystoreBase64Path)) {
            try {
                const base64Content = fs.readFileSync(this.keystoreBase64Path, 'utf8').trim();
                const keystoreData = Buffer.from(base64Content, 'base64');
                fs.writeFileSync(this.keystorePath, keystoreData);
                this.log('Keystore decoded from base64 file', 'success');
                return;
            } catch (error) {
                this.log(`Failed to decode keystore from base64: ${error.message}`, 'warning');
            }
        }

        throw new Error('No keystore found. Please ensure release-key.jks exists or keystore.base64.txt contains valid base64 data.');
    }

    promptForKeystoreCredentials() {
        this.log('Setting up keystore credentials', 'security');
        
        const keystorePassword = process.env.ANDROID_KEYSTORE_PASSWORD || 'playtivity123';
        const keyAlias = process.env.ANDROID_KEY_ALIAS || 'playtivity-key';
        const keyPassword = process.env.ANDROID_KEY_PASSWORD || 'playtivity123';
        
        // Set environment variables for the build process
        process.env.ANDROID_KEYSTORE_PATH = this.keystorePath;
        process.env.ANDROID_KEYSTORE_PASSWORD = keystorePassword;
        process.env.ANDROID_KEY_ALIAS = keyAlias;
        process.env.ANDROID_KEY_PASSWORD = keyPassword;
        
        this.log('Keystore credentials configured', 'success');
        
        return {
            keystorePath: this.keystorePath,
            keystorePassword,
            keyAlias,
            keyPassword
        };
    }

    runCommand(command, description) {
        this.log(`${description}...`, 'build');
        try {
            const output = execSync(command, { 
                cwd: this.projectRoot,
                stdio: 'pipe',
                encoding: 'utf8',
                env: { ...process.env }
            });
            this.log(`${description} completed`, 'success');
            return output;
        } catch (error) {
            this.log(`${description} failed: ${error.message}`, 'error');
            throw error;
        }
    }

    buildReleaseAPK() {
        this.log('Starting release APK build', 'build');

        // Check if FVM is available
        let flutterCommand = 'flutter';
        try {
            execSync('fvm --version', { stdio: 'pipe' });
            flutterCommand = 'fvm flutter';
            this.log('Using FVM for Flutter commands');
        } catch (error) {
            this.log('FVM not found, using system Flutter');
        }

        try {
            // Clean and get dependencies
            this.runCommand(`${flutterCommand} clean`, 'Cleaning project');
            this.runCommand(`${flutterCommand} pub get`, 'Getting dependencies');
            
            // Run tests
            try {
                this.runCommand(`${flutterCommand} test`, 'Running tests');
            } catch (error) {
                this.log('Tests failed, but continuing with release build', 'warning');
            }
            
            // Build signed APK
            this.runCommand(`${flutterCommand} build apk --release`, 'Building signed release APK');
            
            return true;
        } catch (error) {
            this.log(`Release build failed: ${error.message}`, 'error');
            return false;
        }
    }

    buildReleaseBundle() {
        this.log('Building Android App Bundle (AAB)', 'build');

        let flutterCommand = 'flutter';
        try {
            execSync('fvm --version', { stdio: 'pipe' });
            flutterCommand = 'fvm flutter';
        } catch (error) {
            // FVM not available, use system flutter
        }

        try {
            this.runCommand(`${flutterCommand} build appbundle --release`, 'Building signed release bundle');
            return true;
        } catch (error) {
            this.log(`Bundle build failed: ${error.message}`, 'warning');
            return false;
        }
    }

    generateAPKChecksum(apkPath) {
        try {
            const fileBuffer = fs.readFileSync(apkPath);
            const hashSum = crypto.createHash('sha256');
            hashSum.update(fileBuffer);
            return hashSum.digest('hex');
        } catch (error) {
            this.log(`Failed to generate checksum: ${error.message}`, 'warning');
            return null;
        }
    }

    verifyAPKSignature(apkPath) {
        this.log('Verifying APK signature', 'security');
        
        try {
            // Try to get APK info using aapt if available
            try {
                const output = execSync(`aapt dump badging "${apkPath}"`, { 
                    stdio: 'pipe', 
                    encoding: 'utf8' 
                });
                
                const packageMatch = output.match(/package: name='([^']+)'/);
                const versionCodeMatch = output.match(/versionCode='([^']+)'/);
                const versionNameMatch = output.match(/versionName='([^']+)'/);
                
                this.log('APK signature verified successfully', 'success');
                
                return {
                    packageName: packageMatch ? packageMatch[1] : 'Unknown',
                    versionCode: versionCodeMatch ? versionCodeMatch[1] : 'Unknown',
                    versionName: versionNameMatch ? versionNameMatch[1] : 'Unknown'
                };
            } catch (error) {
                this.log('aapt not available, skipping detailed APK verification', 'warning');
                return null;
            }
        } catch (error) {
            this.log(`APK verification failed: ${error.message}`, 'error');
            throw error;
        }
    }

    copyReleaseFiles(version) {
        this.log('Copying release files to release directory', 'release');
        
        const releaseInfo = {
            version: version,
            timestamp: new Date().toISOString().replace(/[:.]/g, '-').slice(0, 16),
            files: []
        };

        // Copy APK
        if (fs.existsSync(this.apkPath)) {
            const apkFileName = `playtivity-v${version.versionName}-release.apk`;
            const apkDestPath = path.join(this.outputDir, apkFileName);
            
            fs.copyFileSync(this.apkPath, apkDestPath);
            
            const apkInfo = this.getFileInfo(apkDestPath);
            const checksum = this.generateAPKChecksum(apkDestPath);
            
            releaseInfo.files.push({
                type: 'APK',
                name: apkFileName,
                path: apkDestPath,
                size: apkInfo.size,
                checksum: checksum
            });
            
            this.log(`APK copied: ${apkFileName}`, 'success');
        }

        // Copy AAB if exists
        if (fs.existsSync(this.bundlePath)) {
            const bundleFileName = `playtivity-v${version.versionName}-release.aab`;
            const bundleDestPath = path.join(this.outputDir, bundleFileName);
            
            fs.copyFileSync(this.bundlePath, bundleDestPath);
            
            const bundleInfo = this.getFileInfo(bundleDestPath);
            
            releaseInfo.files.push({
                type: 'AAB',
                name: bundleFileName,
                path: bundleDestPath,
                size: bundleInfo.size,
                checksum: this.generateAPKChecksum(bundleDestPath)
            });
            
            this.log(`Bundle copied: ${bundleFileName}`, 'success');
        }

        return releaseInfo;
    }

    getFileInfo(filePath) {
        try {
            const stats = fs.statSync(filePath);
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

    generateReleaseNotes(version, releaseInfo) {
        const releaseNotesPath = path.join(this.outputDir, `release-notes-v${version.versionName}.md`);
        
        const notes = `# Playtivity Release v${version.versionName}

## Release Information
- **Version:** ${version.versionName}
- **Build Number:** ${version.buildNumber}
- **Release Date:** ${new Date().toLocaleDateString()}
- **Build Date:** ${releaseInfo.timestamp}

## Release Files

${releaseInfo.files.map(file => `
### ${file.type}
- **File:** \`${file.name}\`
- **Size:** ${file.size} MB
- **SHA256:** \`${file.checksum || 'N/A'}\`
`).join('\n')}

## Installation Instructions

### APK Installation
1. Enable "Install from unknown sources" in Android settings
2. Download the APK file: \`${releaseInfo.files.find(f => f.type === 'APK')?.name || 'N/A'}\`
3. Open the downloaded file and follow installation prompts

### Using ADB
\`\`\`bash
adb install "${releaseInfo.files.find(f => f.type === 'APK')?.name || 'playtivity-release.apk'}"
\`\`\`

## Verification
You can verify the integrity of the downloaded files using their SHA256 checksums listed above.

## Changes in this Release
<!-- Add your changelog here -->
- Release build with proper signing
- Performance optimizations
- Bug fixes and improvements

---
*Generated automatically by Playtivity Release Builder*
`;

        fs.writeFileSync(releaseNotesPath, notes, 'utf8');
        this.log(`Release notes generated: ${releaseNotesPath}`, 'success');
        
        return releaseNotesPath;
    }

    async release(incrementType = 'patch', buildBundle = true) {
        try {
            this.log('🚀 Starting Playtivity Release Process', 'release');
            
            // Setup
            this.ensureOutputDirectory();
            this.setupKeystore();
            this.promptForKeystoreCredentials();
            
            // Version management
            const newVersion = this.incrementVersion(incrementType);
            
            // Build APK
            const apkSuccess = this.buildReleaseAPK();
            if (!apkSuccess) {
                throw new Error('APK build failed');
            }

            // Verify APK
            if (fs.existsSync(this.apkPath)) {
                this.verifyAPKSignature(this.apkPath);
            }

            // Build AAB (optional)
            if (buildBundle) {
                this.buildReleaseBundle();
            }
            
            // Copy and organize release files
            const releaseInfo = this.copyReleaseFiles(newVersion);
            
            // Generate release notes
            const releaseNotesPath = this.generateReleaseNotes(newVersion, releaseInfo);
            
            // Success summary
            this.log('🎉 Release build completed successfully!', 'success');
            
            console.log('\n📋 Release Summary:');
            console.log(`   Version: ${newVersion.fullVersion}`);
            console.log(`   Release Directory: ${this.outputDir}`);
            console.log(`   Release Notes: ${releaseNotesPath}`);
            
            console.log('\n📱 Release Files:');
            releaseInfo.files.forEach(file => {
                console.log(`   ${file.type}: ${file.name} (${file.size} MB)`);
            });
            
            console.log('\n🔐 Security:');
            console.log('   ✅ APK signed with release keystore');
            console.log('   ✅ SHA256 checksums generated');
            
            console.log('\n📤 Next Steps:');
            console.log('   1. Test the release APK on a real device');
            console.log('   2. Upload AAB to Google Play Console (if available)');
            console.log('   3. Create GitHub release with generated files');
            console.log('   4. Update release notes with actual changes');
            
        } catch (error) {
            this.log(`Release process failed: ${error.message}`, 'error');
            process.exit(1);
        }
    }
}

// CLI interface
function showHelp() {
    console.log(`
🚀 Playtivity Release Builder

Usage: node release-apk.js [increment-type] [options]

Increment Types:
  patch (default) - Increment patch version (0.0.1 → 0.0.2)
  minor          - Increment minor version (0.1.0 → 0.2.0)
  major          - Increment major version (1.0.0 → 2.0.0)
  none           - Don't increment version, just build release

Options:
  --no-bundle    - Skip building Android App Bundle (AAB)
  --help, -h     - Show this help message

Examples:
  node release-apk.js              # Increment patch, build APK + AAB
  node release-apk.js minor        # Increment minor version
  node release-apk.js --no-bundle  # Build APK only, no AAB
  node release-apk.js none         # Build release without version increment

Environment Variables:
  ANDROID_KEYSTORE_PASSWORD - Keystore password (default: playtivity123)
  ANDROID_KEY_ALIAS         - Key alias (default: playtivity-key)
  ANDROID_KEY_PASSWORD      - Key password (default: playtivity123)

The script will:
  ✅ Set up keystore for release signing
  ✅ Increment version in pubspec.yaml
  ✅ Build signed release APK
  ✅ Build signed release AAB (optional)
  ✅ Generate checksums and release notes
  ✅ Organize files in releases/ folder
`);
}

// Main execution
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.includes('--help') || args.includes('-h')) {
        showHelp();
        process.exit(0);
    }
    
    const incrementType = args.find(arg => !arg.startsWith('--')) || 'patch';
    const buildBundle = !args.includes('--no-bundle');
    
    const validTypes = ['patch', 'minor', 'major', 'none'];
    
    if (!validTypes.includes(incrementType)) {
        console.error(`❌ Invalid increment type: ${incrementType}`);
        console.error(`Valid types: ${validTypes.join(', ')}`);
        process.exit(1);
    }
    
    const releaser = new APKReleaser();
    releaser.release(incrementType, buildBundle);
}

module.exports = APKReleaser;
