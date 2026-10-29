#!/usr/bin/env bun

const { execSync } = require('child_process');

console.log(`
🚀 Playtivity Build Scripts

Available Commands:
═══════════════════

📱 Development Builds (Testing)
  bun run build           # Quick build (increment build number)
  bun run build:patch     # Patch version increment
  bun run build:minor     # Minor version increment  
  bun run build:major     # Major version increment

🏗️ Release Builds (Production)
  bun run release         # Standard release (patch increment)
  bun run release:patch   # Patch version release
  bun run release:minor   # Minor version release
  bun run release:major   # Major version release
  bun run release:apk-only # APK only, skip AAB bundle

🌙 Nightly Builds (Development)
  bun run nightly         # Create nightly build
  bun run nightly:keep-10 # Keep 10 old nightly builds

⬆️ Nightly Promotion (Nightly → Release)
  bun run nightly:promote       # Promote latest nightly (patch)
  bun run nightly:promote-patch # Promote with patch increment
  bun run nightly:promote-minor # Promote with minor increment
  bun run nightly:promote-major # Promote with major increment

🐙 GitHub Releases
  bun run nightly:github        # Upload latest nightly to GitHub
  bun run nightly:github-stable # Upload as stable release

❓ Help Commands
  bun run help                  # Development build help
  bun run help:release          # Release build help
  bun run help:nightly          # Nightly build help
  bun run help:nightly-promote  # Nightly promotion help
  bun run help:nightly-github   # GitHub release help

Direct Script Usage:
  bun scripts/build-apk.js [increment-type]
  bun scripts/release-apk.js [increment-type] [--no-bundle]
  bun scripts/nightly.js [--keep-builds N]
  bun scripts/nightly-release.js [increment-type] [--build-id ID]

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

console.log('\n💡 Quick Start: bun run build (for development) or bun run release (for production)\n');
