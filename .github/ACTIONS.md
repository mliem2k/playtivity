# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the Playtivity app.

## Available Workflows

### 1. Release APK (`release-apk.yml`)

**Trigger:** Manual (workflow_dispatch)

This workflow builds a release APK and creates a GitHub release with the built APK attached.

#### How to use:
1. Go to the "Actions" tab in your GitHub repository
2. Select "Release APK" from the workflow list
3. Click "Run workflow"
4. Fill in the required inputs:
   - **Release name**: The tag name for the release (e.g., `v1.0.0`)
   - **Release notes**: Description of what's included in this release

#### What it does:
- Checks out the code
- Sets up Java 21 and Flutter
- Installs FVM and uses the Flutter version specified in `.fvmrc`
- Gets dependencies with `fvm flutter pub get`
- Runs tests (continues even if tests fail)
- Sets up Android keystore for APK signing
- Builds the **signed** release APK with `fvm flutter build apk --release`
- Verifies APK signing
- Creates a GitHub release with the signed APK attached
- Uploads the APK as a workflow artifact

### 2. Build APK (PR) (`build-apk-pr.yml`)

**Trigger:** Pull requests to main/master branch, or manual

This workflow builds an APK for testing purposes on pull requests.

#### What it does:
- Same build process as the release workflow
- Uploads the built APK as a workflow artifact for download
- Artifacts are retained for 7 days

## Requirements

### Repository Setup
- The repository should have FVM configured (`.fvmrc` file present)
- Flutter project with proper `pubspec.yaml`
- **Android keystore secrets configured** (see KEYSTORE_SETUP.md)

### Permissions
The workflows require the following GitHub token permissions:
- `contents: write` (for creating releases)
- `actions: read` (for workflow artifacts)

### Secrets
The following repository secrets are required for APK signing:
- `ANDROID_KEYSTORE_BASE64` - Base64 encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD` - Keystore password
- `ANDROID_KEY_ALIAS` - Key alias name
- `ANDROID_KEY_PASSWORD` - Key password

**📖 See `KEYSTORE_SETUP.md` for detailed setup instructions**

## APK Location

After successful builds, APKs can be found:
- **Release workflow**: Attached to the GitHub release + workflow artifacts
- **PR workflow**: In workflow artifacts only

## Customization

You can customize the workflows by:
- Modifying the Flutter version in the workflow (currently uses 'stable')
- Adding additional build variants (debug, profile)
- Adding code signing for release builds
- Adding deployment to app stores
- Modifying retention periods for artifacts

## Troubleshooting

### Common Issues:
1. **Build fails**: Check that all dependencies are properly declared in `pubspec.yaml`
2. **FVM not found**: Ensure `.fvmrc` file exists and is properly formatted
3. **Tests fail**: Tests are set to continue on error, but you may want to fix failing tests
4. **Java version issues**: The workflow uses Java 17, which is compatible with current Flutter versions

### Getting Help:
- Check the workflow run logs in the Actions tab
- Verify your Flutter project builds locally with `fvm flutter build apk --release`
- Ensure all required files are committed to the repository
