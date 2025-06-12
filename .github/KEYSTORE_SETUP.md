# Android Keystore Setup for GitHub Actions

This guide will help you set up Android APK signing for your GitHub Actions workflow.

## Step 1: Generate Android Keystore

Run the following command to generate a new keystore (replace the values with your own):

```bash
keytool -genkey -v -keystore release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias playtivity-key
```

You'll be prompted to enter:
- Keystore password (remember this!)
- Key password (remember this!)
- Your details (name, organization, etc.)

## Step 2: Convert Keystore to Base64

Convert your keystore to base64 format for GitHub Secrets:

### On Windows (PowerShell):
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release-key.jks")) | Out-File -Encoding ascii keystore.base64.txt
```

### On macOS/Linux:
```bash
base64 -i release-key.jks -o keystore.base64.txt
```

## Step 3: Set Up GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these repository secrets:

1. **ANDROID_KEYSTORE_BASE64**
   - Copy the entire content of `keystore.base64.txt`

2. **ANDROID_KEYSTORE_PASSWORD**
   - The password you entered for the keystore

3. **ANDROID_KEY_ALIAS**
   - The alias you used (e.g., `playtivity-key`)

4. **ANDROID_KEY_PASSWORD**
   - The key password you entered

## Step 4: Security Best Practices

1. **Delete local files**: After setting up secrets, delete these files:
   ```bash
   rm release-key.jks keystore.base64.txt
   ```

2. **Add to .gitignore**: Make sure these patterns are in your `.gitignore`:
   ```
   *.jks
   *.keystore
   *.base64.txt
   android/app/release-key.jks
   ```

3. **Backup**: Keep a secure backup of your keystore file offline!

## Step 5: Test the Setup

1. Commit and push your changes
2. Go to Actions → Release APK → Run workflow
3. Check the build logs for signing verification

## Troubleshooting

### Common Issues:

1. **Base64 decoding fails**:
   - Ensure no line breaks in the base64 secret
   - Copy the entire content from the .txt file

2. **Keystore not found**:
   - Check the ANDROID_KEYSTORE_BASE64 secret is set correctly

3. **Wrong password**:
   - Verify ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_PASSWORD secrets

4. **Build fails with Java version**:
   - The workflow uses Java 21, ensure compatibility

### Verify APK Signing Locally:

```bash
# Build the APK locally with signing
flutter build apk --release

# Verify signing (if you have Android SDK)
$ANDROID_HOME/build-tools/[version]/apksigner verify --verbose build/app/outputs/flutter-apk/app-release.apk
```

## Notes

- The keystore will be valid for ~27 years (10000 days)
- Keep your keystore password secure - you'll need it for all future releases
- If you lose the keystore, you cannot update your app on Play Store
- The workflow will fallback to debug signing for local development
