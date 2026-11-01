# Signs the release APK with the keystore kept on this machine. Passwords arrive as environment variables.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$bt = Get-ChildItem "$root\android-sdk\build-tools" | Sort-Object { [version]($_.Name -replace '[^0-9.]','') } | Select-Object -Last 1
$apksigner = "$($bt.FullName)\apksigner.bat"
$in = "C:\b\pt\native\app\build\outputs\apk\production\release\app-production-release-unsigned.apk"
$out = "C:\b\pt\native\app\build\outputs\apk\production\release\app-production-release-signed.apk"
$bundleIn = "C:\b\pt\native\app\build\outputs\bundle\productionRelease\app-production-release.aab"
$bundleOut = "C:\b\pt\native\app\build\outputs\bundle\productionRelease\app-production-release-signed.aab"
Remove-Item $out -ErrorAction SilentlyContinue
Remove-Item $bundleOut -ErrorAction SilentlyContinue
cmd /c "`"$apksigner`" sign --ks C:\b\secrets\release-key.jks --ks-key-alias %KS_ALIAS% --ks-pass env:KS_PASS --key-pass env:KEY_PASS --out `"$out`" `"$in`" 2>&1"
if ($LASTEXITCODE -ne 0) { exit 1 }
cmd /c "`"$apksigner`" verify --print-certs `"$out`" 2>&1" | Select-String "SHA-256"
$jarsigner = "$root\jdk21\bin\jarsigner.exe"
cmd /c "`"$jarsigner`" -keystore C:\b\secrets\release-key.jks -storepass:env KS_PASS -keypass:env KEY_PASS -signedjar `"$bundleOut`" `"$bundleIn`" %KS_ALIAS% 2>&1"
if ($LASTEXITCODE -ne 0) { exit 1 }
$verified = cmd /c "`"$jarsigner`" -verify `"$bundleOut`" 2>&1"
if ($LASTEXITCODE -ne 0 -or -not ($verified -match "jar verified")) { $verified | Select-Object -Last 10; exit 1 }
$verified | Select-String "jar verified"
