# Signs the release APK with the keystore kept on this machine. Passwords arrive as environment variables.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$bt = Get-ChildItem "$root\android-sdk\build-tools" | Sort-Object { [version]($_.Name -replace '[^0-9.]','') } | Select-Object -Last 1
$apksigner = "$($bt.FullName)\apksigner.bat"
$in = "C:\b\pt\android\app\build\outputs\apk\release\app-release.apk"
$out = "C:\b\pt\android\app\build\outputs\apk\release\app-release-signed.apk"
Remove-Item $out -ErrorAction SilentlyContinue
cmd /c "`"$apksigner`" sign --ks C:\b\secrets\release-key.jks --ks-key-alias %KS_ALIAS% --ks-pass env:KS_PASS --key-pass env:KEY_PASS --out `"$out`" `"$in`" 2>&1"
if ($LASTEXITCODE -ne 0) { exit 1 }
cmd /c "`"$apksigner`" verify --print-certs `"$out`" 2>&1" | Select-String "SHA-256"
