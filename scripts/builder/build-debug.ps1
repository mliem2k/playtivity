# Build the Kotlin preview APK for device checks.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
Set-Location C:\b\pt\native
cmd /c "gradlew.bat :core:testDebugUnitTest :app:assemblePreviewDebug --console=plain > debug.log 2>&1"
$code = $LASTEXITCODE
Get-Content debug.log | Select-String -Pattern "BUILD (SUCCESSFUL|FAILED)|What went wrong" -Context 0,4 | Select-Object -First 12
Get-ChildItem app\build\outputs\apk\preview\debug -Filter *.apk | Select-Object Name,Length
exit $code
