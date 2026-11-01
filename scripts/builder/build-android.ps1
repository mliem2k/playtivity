$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
Set-Location C:\b\pt\native
Set-Content local.properties ("sdk.dir=" + ($env:ANDROID_HOME -replace '\\','\\'))
cmd /c "gradlew.bat :core:testDebugUnitTest :app:lintProductionRelease :app:assembleProductionRelease :app:bundleProductionRelease --console=plain > build.log 2>&1"
$code = $LASTEXITCODE
Get-Content build.log | Select-String -Pattern "BUILD (SUCCESSFUL|FAILED)|What went wrong|^e: |FAILED" -Context 0,5 | Select-Object -First 30
Get-ChildItem app\build\outputs\apk\production\release -ErrorAction SilentlyContinue | Select-Object Name,Length
Get-ChildItem app\build\outputs\bundle\productionRelease -ErrorAction SilentlyContinue | Select-Object Name,Length
exit $code
