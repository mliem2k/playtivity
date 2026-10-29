# Debug APK: the JavaScript comes from Metro, so only native changes need this rebuild.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$root\node;$root\bun;$root\ccache;$env:JAVA_HOME\bin;$env:Path"
Set-Location C:\b\pt\android
cmd /c "gradlew.bat -Dorg.gradle.java.home=$root\jdk21 assembleDebug -PreactNativeArchitectures=arm64-v8a --console=plain > ..\debug.log 2>&1"
$code = $LASTEXITCODE
Get-Content ..\debug.log | Select-String -Pattern "BUILD (SUCCESSFUL|FAILED)|What went wrong" -Context 0,4 | Select-Object -First 12
Get-ChildItem app\build\outputs\apk\debug -Filter *.apk | Select-Object Name,Length
exit $code
