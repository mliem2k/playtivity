#!/usr/bin/env node

const { execSync } = require('child_process');

console.log(`
🚀 Playtivity Build Scripts

Available Commands:
═══════════════════

📱 Development Builds (Testing)
  npm run build           # Quick build (increment build number)
  npm run build:patch     # Patch version increment
  npm run build:minor     # Minor version increment  
  npm run build:major     # Major version increment

🏗️ Release Builds (Production)
  npm run release         # Standard release (patch increment)
  npm run release:patch   # Patch version release
  npm run release:minor   # Minor version release
  npm run release:major   # Major version release
  npm run release:apk-only # APK only, skip AAB bundle

🌙 Nightly Builds (Development)
  npm run nightly         # Create nightly build
  npm run nightly:keep-10 # Keep 10 old nightly builds

⬆️ Nightly Promotion (Nightly → Release)
  npm run nightly:promote       # Promote latest nightly (patch)
  npm run nightly:promote-patch # Promote with patch increment
  npm run nightly:promote-minor # Promote with minor increment
  npm run nightly:promote-major # Promote with major increment

🐙 GitHub Releases
  npm run nightly:github        # Upload latest nightly to GitHub
  npm run nightly:github-stable # Upload as stable release

❓ Help Commands
  npm run help                  # Development build help
  npm run help:release          # Release build help
  npm run help:nightly          # Nightly build help
  npm run help:nightly-promote  # Nightly promotion help
  npm run help:nightly-github   # GitHub release help

Direct Script Usage:
  node scripts/build-apk.js [increment-type]
  node scripts/release-apk.js [increment-type] [--no-bundle]
  node scripts/nightly.js [--keep-builds N]
  node scripts/nightly-release.js [increment-type] [--build-id ID]

Build Outputs:
  builds/     - Development builds
  releases/   - Production releases  
  nightly/    - Nightly builds

Requirements:
  ✅ Node.js 14.0.0+
  ✅ Flutter SDK (or FVM)
  ✅ Android SDK
  ✅ GitHub CLI (for GitHub releases)

For detailed documentation, see: BUILD_README.md
`);

// Show current versions if in project directory
try {
    const fs = require('fs');
    const path = require('path');
    
    const pubspecPath = path.join(__dirname, '..', 'pubspec.yaml');
    if (fs.existsSync(pubspecPath)) {
        const pubspec = fs.readFileSync(pubspecPath, 'utf8');
        const versionMatch = pubspec.match(/version:\s*(.+)/);
        if (versionMatch) {
            console.log(`Current version: ${versionMatch[1].trim()}`);
        }
    }
} catch (error) {
    // Ignore errors when not in project directory
}

console.log('\n💡 Quick Start: npm run build (for development) or npm run release (for production)\n');
