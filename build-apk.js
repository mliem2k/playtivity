#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

class APKBuilder {
    constructor() {
        this.projectRoot = __dirname;
        this.pubspecPath = path.join(this.projectRoot, 'pubspec.yaml');
        this.outputDir = path.join(this.projectRoot, 'builds');
        this.apkPath = path.join(this.projectRoot, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    }

    log(message, type = 'info') {
        const timestamp = new Date().toLocaleTimeString();
        const prefix = {
            'info': '📱',
            'success': '✅',
            'error': '❌',
            'warning': '⚠️',
            'build': '🔨'
        }[type] || 'ℹ️';
        
        console.log(`[${timestamp}] ${prefix} ${message}`);
    }

    ensureOutputDirectory() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir, { recursive: true });
            this.log(`Created output directory: ${this.outputDir}`);
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
        // Extract version like "0.0.1+1" from "version: 0.0.1+1"
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

    incrementVersion(incrementType = 'build') {
        this.log('Reading current version from pubspec.yaml');
        
        const content = this.readPubspec();
        const lines = content.split('\n');
        
        let versionLineIndex = -1;
        let currentVersion = null;

        // Find the version line
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
        let newBuildNumber = currentVersion.buildNumber;

        // Increment based on type
        switch (incrementType) {
            case 'major':
                const [major, minor, patch] = newVersionName.split('.');
                newVersionName = `${parseInt(major) + 1}.0.0`;
                newBuildNumber = 1;
                break;
            case 'minor':
                const [maj, min, pat] = newVersionName.split('.');
                newVersionName = `${maj}.${parseInt(min) + 1}.0`;
                newBuildNumber = 1;
                break;
            case 'patch':
                const [ma, mi, pa] = newVersionName.split('.');
                newVersionName = `${ma}.${mi}.${parseInt(pa) + 1}`;
                newBuildNumber = 1;
                break;
            case 'build':
            default:
                newBuildNumber = currentVersion.buildNumber + 1;
                break;
        }

        const newFullVersion = `${newVersionName}+${newBuildNumber}`;
        
        // Update the version line
        lines[versionLineIndex] = `version: ${newFullVersion}`;
        
        // Write back to file
        this.writePubspec(lines.join('\n'));
        
        this.log(`Version updated to: ${newFullVersion}`, 'success');
        
        return {
            versionName: newVersionName,
            buildNumber: newBuildNumber,
            fullVersion: newFullVersion
        };
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

    buildAPK() {
        this.log('Starting APK build process', 'build');

        // Check if FVM is available, otherwise use flutter directly
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
                this.log('Tests failed, but continuing with build', 'warning');
            }
            
            // Build APK
            this.runCommand(`${flutterCommand} build apk --release`, 'Building APK');
            
            return true;
        } catch (error) {
            this.log(`Build failed: ${error.message}`, 'error');
            return false;
        }
    }

    copyAPK(version) {
        if (!fs.existsSync(this.apkPath)) {
            throw new Error(`APK not found at: ${this.apkPath}`);
        }

        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 16);
        const fileName = `playtivity-v${version.versionName}-build${version.buildNumber}-${timestamp}.apk`;
        const destinationPath = path.join(this.outputDir, fileName);
        
        fs.copyFileSync(this.apkPath, destinationPath);
        
        this.log(`APK copied to: ${destinationPath}`, 'success');
        
        // Also create a "latest" symlink/copy for convenience
        const latestPath = path.join(this.outputDir, 'playtivity-latest.apk');
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
                created: stats.birthtime.toLocaleString()
            };
        } catch (error) {
            return { size: 'Unknown', created: 'Unknown' };
        }
    }

    async build(incrementType = 'build') {
        try {
            this.log('🚀 Starting Playtivity APK Build Process');
            
            // Ensure output directory exists
            this.ensureOutputDirectory();
            
            // Increment version
            const newVersion = this.incrementVersion(incrementType);
            
            // Build APK
            const buildSuccess = this.buildAPK();
            
            if (!buildSuccess) {
                this.log('Build failed, exiting', 'error');
                process.exit(1);
            }
            
            // Copy APK to output directory
            const apkInfo = this.copyAPK(newVersion);
            const fileInfo = this.getAPKInfo(apkInfo.timestampedPath);
            
            // Success summary
            this.log('🎉 Build completed successfully!', 'success');
            console.log('\n📋 Build Summary:');
            console.log(`   Version: ${newVersion.fullVersion}`);
            console.log(`   APK Size: ${fileInfo.size} MB`);
            console.log(`   Location: ${apkInfo.timestampedPath}`);
            console.log(`   Latest: ${apkInfo.latestPath}`);
            console.log('\n📱 Installation:');
            console.log(`   adb install "${apkInfo.latestPath}"`);
            console.log('   or transfer to your device and install manually');
            
        } catch (error) {
            this.log(`Build process failed: ${error.message}`, 'error');
            process.exit(1);
        }
    }
}

// CLI interface
function showHelp() {
    console.log(`
🔨 Playtivity APK Builder

Usage: node build-apk.js [increment-type]

Increment Types:
  build (default) - Increment build number only (0.0.1+1 → 0.0.1+2)
  patch          - Increment patch version (0.0.1+5 → 0.0.2+1)
  minor          - Increment minor version (0.1.2+3 → 0.2.0+1)
  major          - Increment major version (1.2.3+4 → 2.0.0+1)

Examples:
  node build-apk.js           # Increment build number
  node build-apk.js build     # Same as above
  node build-apk.js patch     # Increment patch version
  node build-apk.js minor     # Increment minor version
  node build-apk.js major     # Increment major version

The script will:
  ✅ Automatically increment the version in pubspec.yaml
  ✅ Clean and build the APK
  ✅ Copy the APK to builds/ folder with timestamp
  ✅ Create a "latest" APK for easy installation
`);
}

// Main execution
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.includes('--help') || args.includes('-h')) {
        showHelp();
        process.exit(0);
    }
    
    const incrementType = args[0] || 'build';
    const validTypes = ['build', 'patch', 'minor', 'major'];
    
    if (!validTypes.includes(incrementType)) {
        console.error(`❌ Invalid increment type: ${incrementType}`);
        console.error(`Valid types: ${validTypes.join(', ')}`);
        process.exit(1);
    }
    
    const builder = new APKBuilder();
    builder.build(incrementType);
}

module.exports = APKBuilder;
