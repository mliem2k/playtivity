# Playtivity Local APK Builder & Releaser

This directory contains Node.js scripts to build and release Playtivity APK files locally with automatic version incrementing and proper release signing.

## 🚀 Quick Start

```bash
# List all available commands
bun run list

# Quick development build
bun run build

# Production release
bun run release

# Latest development with nightly branding
bun run nightly
```

### Development Builds (Testing)
```bash
# Quick development build (increment build number only)
bun build-apk.js          # or: bun run build
```

### Release Builds (Distribution)
```bash
# Production release (increment patch version, signed APK + AAB)
bun release-apk.js         # or: bun run release
```

### Nightly Builds (Latest Development)
```bash
# Latest development build with nightly branding
bun nightly-apk.js         # or: bun run nightly
```

### Nightly Release Promotion
```bash
# Promote tested nightly build to official release
bun nightly-release.js     # or: bun run nightly:promote
```

### Nightly GitHub Release
```bash
# Create GitHub release from nightly build
bun nightly-github-release.js  # or: bun run nightly:github
```

## 📱 Build Types Comparison

| Feature | Development Build | Release Build | Nightly Build | Nightly Promotion | Nightly GitHub Release |
|---------|------------------|---------------|---------------|-------------------|----------------------|
| **Purpose** | Testing, development | Distribution, production | Latest development features | Convert nightly to release | Share nightly on GitHub |
| **Signing** | Debug signing | Release keystore signing | Debug signing | Release keystore signing | Debug signing |
| **Version** | Increments build number | Increments version number | Special nightly versioning | Strips nightly, increments version | Uses nightly version |
| **Output** | `builds/` folder | `releases/` folder | `nightly/` folder | `releases/` folder | GitHub release |
| **Files** | APK only | APK + AAB + release notes | APK + detailed build info | APK + AAB + release notes | APK + release notes |
| **Stability** | Stable development | Production ready | **Unstable - may have bugs** | Production ready (tested nightly) | **Unstable - may have bugs** |
| **Branding** | Normal | Official release | **NIGHTLY DEVELOPMENT BUILD** | Official release | **NIGHTLY DEVELOPMENT BUILD** |

## 🛠️ Development Build Usage

### Node.js
```bash
# Quick build (increment build number: 0.0.1+1 → 0.0.1+2)
bun build-apk.js

# Increment version parts
bun build-apk.js patch     # 0.0.1+5 → 0.0.2+1
bun build-apk.js minor     # 0.1.2+3 → 0.2.0+1  
bun build-apk.js major     # 1.2.3+4 → 2.0.0+1
```

### NPM Scripts
```bash
bun run build         # Default build
bun run build:patch   # Patch version
bun run build:minor   # Minor version  
bun run build:major   # Major version
bun run help          # Show help
```

### NPM Scripts
```bash
bun run build              # Default build
bun run build:patch        # Patch version
bun run build:minor        # Minor version
bun run build:major        # Major version
```

### PowerShell
```powershell
.\build-apk.ps1            # Default build
.\build-apk.ps1 patch      # Patch version
```

## 🚀 Release Build Usage

### Node.js
```bash
# Standard release (increment patch: 0.0.1 → 0.0.2)
bun release-apk.js

# Different version increments
bun release-apk.js minor           # 0.1.0 → 0.2.0
bun release-apk.js major           # 1.0.0 → 2.0.0
bun release-apk.js none            # Don't increment version

# APK-only release (skip AAB bundle)
bun release-apk.js --no-bundle
```

### NPM Scripts
```bash
bun run release             # Standard release
bun run release:patch       # Patch version
bun run release:minor       # Minor version  
bun run release:major       # Major version
bun run release:apk-only    # APK only, no AAB
```

### PowerShell
```powershell
.\release-apk.ps1           # Standard release
.\release-apk.ps1 minor     # Minor version
.\release-apk.ps1 -NoBundle # APK only
```

## 🌙 Nightly Build Usage

**⚠️ WARNING: Nightly builds are DEVELOPMENT BUILDS and may be unstable!**

### Node.js
```bash
# Create nightly build from latest development code
bun nightly-apk.js

# Keep more old nightly builds
bun nightly-apk.js --keep-builds 10
```

### NPM Scripts
```bash
bun run nightly             # Standard nightly build
bun run nightly:keep-10     # Keep 10 old builds
```

### Nightly Build Features
- **Special Versioning**: `0.0.1-nightly-20250614-143022+timestamp`
- **Git Integration**: Includes branch, commit hash, and commit message
- **Build Metadata**: Detailed JSON build information
- **Auto-cleanup**: Automatically removes old nightly builds
- **Clear Branding**: Explicitly marked as NIGHTLY DEVELOPMENT BUILD

## 🌙 Nightly Release Promotion

After testing a nightly build and confirming it's stable, you can promote it to an official release:

**⚠️ IMPORTANT: This feature converts a tested nightly build into a production release!**

### Node.js
```bash
# Promote latest nightly to release (patch increment)
bun nightly-release.js

# Promote with version increment type
bun nightly-release.js patch     # 0.0.1-nightly-... → 0.0.2+1
bun nightly-release.js minor     # 0.1.0-nightly-... → 0.2.0+1
bun nightly-release.js major     # 1.0.0-nightly-... → 2.0.0+1

# Promote specific nightly build
bun nightly-release.js --build-id 20250614-143022

# Custom version for release
bun nightly-release.js --version 1.5.0
```

### NPM Scripts
```bash
bun run nightly:promote              # Promote latest (patch increment)
bun run nightly:promote-patch        # Patch increment
bun run nightly:promote-minor        # Minor increment
bun run nightly:promote-major        # Major increment
```

### PowerShell
```powershell
.\nightly-release.ps1                    # Promote latest (patch increment)
.\nightly-release.ps1 patch             # Patch increment
.\nightly-release.ps1 minor             # Minor increment
.\nightly-release.ps1 major             # Major increment
.\nightly-release.ps1 -BuildId "20250614-143022"  # Specific build
.\nightly-release.ps1 -Version "1.5.0"  # Custom version
```

### Promotion Process
1. **Lists Available Nightly Builds**: Shows all nightly builds with creation dates and sizes
2. **Selects Build**: Uses latest by default, or specify with `--build-id`
3. **Creates Release Version**: Strips `-nightly-` suffix and increments version
4. **Updates pubspec.yaml**: Sets new release version
5. **Builds Signed APK + AAB**: Creates production-ready files with release keystore
6. **Generates Release Notes**: Includes original nightly build info and git details
7. **Stores in releases/**: Organized alongside other official releases

### Example Promotion
```bash
# Before: 0.1.0-nightly-20250614-143022+1718373622
# After:  0.1.1+1 (official release)
```

## 🔄 Development Workflow Examples

### Standard Development Cycle
```bash
# 1. Quick testing during development
bun run build                    # Create development builds for testing

# 2. Ready for release
bun run release                  # Create official release when stable
```

### Nightly Development Cycle
```bash
# 1. Create nightly with latest development code
bun run nightly                  # Build with nightly branding + git tracking

# 2. Test the nightly build thoroughly
# (Install and test the APK from nightly/ folder)

# 3. If nightly is stable, promote to official release
bun run nightly:promote          # Convert tested nightly to official release
```

### Nightly GitHub Release Cycle
```bash
# 1. Create nightly with latest development code
bun run nightly                  # Build with nightly branding + git tracking

# 2. Share nightly build on GitHub for community testing
bun run nightly:github           # Upload to GitHub releases as prerelease

# 3. (Optional) After community testing, promote to official release
bun run nightly:promote          # Convert tested nightly to official release
```

### Recommended Workflow
1. **Daily Development**: Use `bun run build` for rapid testing
2. **Weekly Nightly**: Use `bun run nightly` to test latest development code
3. **Monthly Releases**: Use `bun run release` or promote tested nightly builds
4. **Emergency Fixes**: Use `bun run release patch` for quick bug fixes

### GitHub Release Workflow
1. **Create Nightly**: Use `bun run nightly` to build with git tracking
2. **Share for Testing**: Use `bun run nightly:github` to upload to GitHub
3. **Community Feedback**: Let testers download and provide feedback
4. **Promote if Stable**: Use `bun run nightly:promote` for official release

## 🔧 GitHub Release Setup

### 1. Install GitHub CLI
Download from: https://cli.github.com/

Or with PowerShell:
```powershell
winget install GitHub.cli
```

Or with Chocolatey:
```powershell
choco install gh
```

### 2. Authenticate with GitHub
```bash
gh auth login
```

This will open a web browser to authenticate with GitHub. Choose your preferred authentication method.

## 📱 Version Increment Types

| Type | Example Change | When to Use |
|------|----------------|-------------|
| `build` (default) | `0.0.1+1` → `0.0.1+2` | Testing, development builds |
| `patch` | `0.0.1+5` → `0.0.2+1` | Bug fixes |
| `minor` | `0.1.2+3` → `0.2.0+1` | New features |
| `major` | `1.2.3+4` → `2.0.0+1` | Breaking changes |

## 🛠️ Usage Examples

### Node.js
```bash
# Quick build (increment build number)
bun build-apk.js

# Increment patch version
bun build-apk.js patch

# Increment minor version  
bun build-apk.js minor

# Increment major version
bun build-apk.js major

# Show help
bun build-apk.js --help
```

### NPM Scripts
```bash
bun run build         # Default build
bun run build:patch   # Patch version
bun run build:minor   # Minor version  
bun run build:major   # Major version
bun run help          # Show help
```

### Nightly GitHub Release Examples
```bash
# Create and share latest nightly on GitHub
bun run nightly && bun run nightly:github

# Share specific nightly build
bun run nightly:github               # Latest nightly
bun nightly-github-release.js --build-id 20250614-143022  # Specific build

# Mark nightly as stable release (not prerelease)
bun run nightly:github-stable
```

## 🏗️ Release Build Usage

### Node.js
```bash
# Default release build (patch increment)
bun release-apk.js

# Increment version types
bun release-apk.js patch   # 0.0.1+5 → 0.0.2+1
bun release-apk.js minor   # 0.1.2+3 → 0.2.0+1  
bun release-apk.js major   # 1.2.3+4 → 2.0.0+1

# APK only (skip AAB bundle)
bun release-apk.js --no-bundle
```

### NPM Scripts
```bash
bun run release           # Default release (patch)
bun run release:patch     # Patch version
bun run release:minor     # Minor version
bun run release:major     # Major version
bun run release:apk-only  # APK only, no AAB
```

### PowerShell
```powershell
.\build-apk.ps1                    # Default build
.\build-apk.ps1 patch             # Patch version
.\build-apk.ps1 minor             # Minor version
.\build-apk.ps1 major             # Major version
.\build-apk.ps1 -Help             # Show help
```

## 📁 Output Structure

### Development Builds (`builds/` folder)
```
builds/
├── playtivity-v0.0.1-build2-2025-06-14-1430.apk  # Timestamped APK
├── playtivity-v0.0.1-build3-2025-06-14-1445.apk  # Another build
└── playtivity-latest.apk                          # Always points to latest build
```

### Release Builds (`releases/` folder)
```
releases/
├── playtivity-v0.0.2-release.apk                  # Signed release APK
├── playtivity-v0.0.2-release.aab                  # Signed App Bundle (for Play Store)
├── release-notes-v0.0.2.md                        # Generated release notes
├── playtivity-v0.0.3-release.apk                  # Next release
└── release-notes-v0.0.3.md                        # Next release notes
```

### Nightly Builds (`nightly/` folder)
```
nightly/
├── playtivity-nightly-20250614-143022-a1b2c3d.apk     # Timestamped nightly APK
├── playtivity-latest-nightly.apk                      # Always points to latest nightly
├── nightly-info-20250614-143022.json                  # Build metadata with git info
├── nightly-notes-20250614-143022.md                   # Detailed build notes
├── latest-nightly-info.json                           # Latest build metadata
└── latest-nightly-notes.md                            # Latest build notes
```

### Nightly Release Promotion
When you promote a nightly build using `nightly-release.js`, it:
1. **Reads nightly build metadata** from `nightly/` folder
2. **Creates official release** in `releases/` folder with proper versioning
3. **Strips nightly branding** and creates production-ready APK + AAB
4. **Preserves git history** from original nightly build in release notes
5. **Updates pubspec.yaml** with new release version
├── nightly-info-20250614-143022.json                  # Build metadata
├── nightly-notes-20250614-143022.md                   # Build documentation
├── playtivity-latest-nightly.apk                      # Latest nightly build
├── latest-nightly-info.json                           # Latest build info
└── latest-nightly-notes.md                            # Latest build notes
```

## 🔐 Release Signing Setup

Release builds require a keystore for signing. The scripts handle this automatically:

### Automatic Setup
1. **Base64 Keystore**: If `keystore.base64.txt` exists, it's decoded to `release-key.jks`
2. **Existing Keystore**: If `release-key.jks` exists, it's used directly
3. **Environment Variables**: Credentials can be set via environment variables

### Environment Variables (Optional)
```bash
# Windows Command Prompt
set ANDROID_KEYSTORE_PASSWORD=your_password
set ANDROID_KEY_ALIAS=your_alias
set ANDROID_KEY_PASSWORD=your_key_password

# PowerShell
$env:ANDROID_KEYSTORE_PASSWORD="your_password"
$env:ANDROID_KEY_ALIAS="your_alias"
$env:ANDROID_KEY_PASSWORD="your_key_password"
```

### Default Credentials
If no environment variables are set, defaults are used:
- **Keystore Password**: `playtivity123`
- **Key Alias**: `playtivity-key`
- **Key Password**: `playtivity123`

## 📱 Installing on Device

### Development Builds
```bash
# Install latest development build
adb install "builds/playtivity-latest.apk"
```

### Release Builds
```bash
# Install latest release build
adb install "releases/playtivity-v0.0.2-release.apk"
```

### Nightly Builds
```bash
# Install latest nightly build
adb install "nightly/playtivity-latest-nightly.apk"

# Install specific nightly build
adb install "nightly/playtivity-nightly-20250614-143022-a1b2c3d.apk"
```

### Manual Installation
1. Transfer the APK file to your Android device
2. Enable "Install from unknown sources" in Android settings
3. Open the APK file and follow installation prompts

## ⚙️ What the Scripts Do

### Development Build Process (`build-apk.js`)
1. **📖 Read Current Version**: Parse version from `pubspec.yaml`
2. **🔢 Increment Build Number**: Increment build number only (for testing)
3. **💾 Update pubspec.yaml**: Write new version back to file
4. **🧹 Clean Build**: Run `bunx expo prebuild --clean` to ensure fresh build
5. **📦 Get Dependencies**: Run `bun install`
6. **🧪 Run Tests**: Execute tests (continues on failure)
7. **🔨 Build APK**: Create debug APK with `./gradlew assembleRelease`
8. **📁 Copy & Organize**: Copy APK to `builds/` with timestamp

### Release Build Process (`release-apk.js`)
1. **🔐 Setup Keystore**: Prepare release signing keystore
2. **📖 Read Current Version**: Parse version from `pubspec.yaml`
3. **🔢 Increment Version**: Increment version number (patch/minor/major)
4. **💾 Update pubspec.yaml**: Write new version back to file
5. **🧹 Clean Build**: Run `bunx expo prebuild --clean` to ensure fresh build
6. **📦 Get Dependencies**: Run `bun install`
7. **🧪 Run Tests**: Execute tests (continues on failure)
8. **🔨 Build Signed APK**: Create signed APK with release keystore
9. **📦 Build AAB Bundle**: Create signed App Bundle for Play Store
10. **🔍 Verify Signatures**: Validate APK signing and integrity
11. **📁 Copy & Organize**: Copy files to `releases/` folder
12. **🧮 Generate Checksums**: Create SHA256 checksums for verification
13. **📝 Create Release Notes**: Generate markdown release documentation

## 🔧 Requirements

### For All Scripts:
- Node.js 14.0.0 or higher
- Android SDK, JDK 17 and Bun
- Android SDK (for release signing verification)
- **Java 21** (required for Android builds - configured in `android/app/build.gradle.kts`)

### For Release Builds (Additional):
- Valid Android keystore (`release-key.jks` or `keystore.base64.txt`)
- Android SDK Build Tools (for APK verification)

### For GitHub Releases (Additional):
- GitHub CLI (`gh`) installed and authenticated
- GitHub repository with write access

## 🎯 When to Use Each Script

### Use Development Builds (`build-apk.js`) When:
- 🧪 Testing new features
- 🐛 Debugging issues
- 🔄 Rapid iteration during development
- 📱 Installing on your own device for testing

### Use Release Builds (`release-apk.js`) When:
- 🚀 Creating production releases
- 📤 Distributing to beta testers
- 🏪 Uploading to app stores
- 📋 Creating official version releases
- 🔐 Need properly signed APKs

### Use Nightly Builds (`nightly-apk.js`) When:
- 🌙 Want to test the absolute latest development code
- 🔬 Need to verify recent commits work
- 👥 Sharing bleeding-edge builds with testers
- 📊 Creating automated development builds
- ⚡ Want git commit tracking in builds

### Use Nightly Release Promotion (`nightly-release.js`) When:
- ✅ You've tested a nightly build and confirmed it's stable
- 🚀 Ready to create an official release from tested nightly code
- 📋 Want to maintain git history from nightly to release
- 🔄 Converting development build to production release
- 📦 Need signed APK + AAB for distribution after nightly testing

### Use Nightly GitHub Release (`nightly-github-release.js`) When:
- 📤 Want to share nightly builds publicly on GitHub
- 👥 Distributing development builds to testers via GitHub
- 📋 Creating automated nightly release pipeline
- 🔗 Need permanent download links for nightly builds
- 📊 Want to track nightly releases with git history
- 🌍 Making bleeding-edge builds available to community

**⚠️ IMPORTANT: Nightly builds are development builds and may be unstable!**

## 🎯 Why Auto-Increment Version?

Android requires a higher version code (build number) for app updates. These scripts ensure:
- ✅ No version conflicts when installing on device
- ✅ Proper app updates (Android won't install lower version codes)
- ✅ Easy tracking of builds with timestamps
- ✅ Consistent versioning across development team

## 🔍 Troubleshooting

### "Android SDK not found"
- Set ANDROID_HOME to your Android SDK
- Or install and use FVM: `dart pub global activate fvm`

### "Build failed"
- Check that you're in the project root directory
- Ensure `pubspec.yaml` exists
- Check ANDROID_HOME and JDK 17

### "Permission denied" (PowerShell)
```powershell
# Allow script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "APK won't install on device"
- Enable "Install from unknown sources" in Android settings
- Uninstall previous version if downgrading
- Check available storage space

### "No nightly builds found" (Nightly Promotion)
- Run `bun run nightly` first to create nightly builds
- Check that `nightly/` folder exists with APK files
- Verify nightly build completed successfully

### "Keystore not found" (Release/Nightly Promotion)
- Ensure `release-key.jks` exists in project root
- Or provide `keystore.base64.txt` for automatic keystore setup
- Check keystore permissions and file integrity

### "GitHub CLI not found" (GitHub Release)
- Install GitHub CLI from https://cli.github.com/
- Or install with: `winget install GitHub.cli`
- Ensure `gh` is in your PATH after installation
- Authenticate with: `gh auth login`

### "GitHub CLI not authenticated" (GitHub Release)
- Run `gh auth login` to authenticate
- Follow the prompts to authenticate via web browser
- Verify authentication with: `gh auth status`

### "Permission denied" (GitHub Release)
- Verify you have write access to the repository
- Check that you're the owner or have collaborator access
- Ensure the repository exists and is accessible
- Re-authenticate with: `gh auth login`

## 📝 Notes

- Version increments are permanent (modifies `pubspec.yaml`)
- Build artifacts are stored in `builds/` directory
- Release artifacts are stored in `releases/` directory  
- Nightly artifacts are stored in `nightly/` directory
- Scripts automatically detect and use FVM if available
- Tests run but don't fail the build (continues on error)
- Each build creates both timestamped and "latest" APK files
- Nightly release promotion preserves original build metadata
- Keystore setup is automatic if `keystore.base64.txt` exists
- All scripts are Node.js-based for cross-platform compatibility
- GitHub releases require GitHub CLI authentication
- GitHub releases are marked as prerelease by default (use `--stable` to override)

## 🤝 Contributing

To modify the build scripts:
1. Edit the relevant `.js` files for functionality changes
2. Update this README if adding new features
3. Test on different environments before committing
4. Ensure Node.js compatibility across platforms
