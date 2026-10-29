$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$root\node;$root\bun;$env:JAVA_HOME\bin;$env:Path"
Set-Location C:\b\pt
cmd /c "bun install --frozen-lockfile > build.log 2>&1 && bun x expo prebuild --platform android --no-install >> build.log 2>&1"
if ($LASTEXITCODE -ne 0) { Get-Content build.log -Tail 20; exit 1 }
Set-Content android\local.properties ("sdk.dir=" + ($env:ANDROID_HOME -replace '\\','\\'))
cmd /c "cd android && gradlew.bat -Dorg.gradle.java.home=C:\Users\user\toolchain\jdk21 assembleRelease -x lintVitalRelease -x lintVitalAnalyzeRelease -PreactNativeArchitectures=arm64-v8a --console=plain >> ..\build.log 2>&1"
$code = $LASTEXITCODE
Get-Content build.log | Select-String -Pattern "BUILD (SUCCESSFUL|FAILED)|What went wrong|^e: |FAILED" -Context 0,5 | Select-Object -First 30
Get-ChildItem android\app\build\outputs\apk\release -ErrorAction SilentlyContinue | Select-Object Name,Length
exit $code
