# Compare clean and incremental Kotlin production builds on the Windows builder.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
Set-Location C:\b\pt\native
$gradle = "gradlew.bat :app:assembleProductionRelease --console=plain"

function Time-Run($label, $command) {
  $clock = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "$command > C:\b\bench-$label.log 2>&1"
  $code = $LASTEXITCODE
  $clock.Stop()
  $ok = $code -eq 0 -and (Select-String -Path "C:\b\bench-$label.log" -Pattern "BUILD SUCCESSFUL" -Quiet)
  "{0,-28} {1,7:N0}s  success={2}" -f $label, $clock.Elapsed.TotalSeconds, $ok
  if (-not $ok) { exit $code }
}

cmd /c "gradlew.bat clean --console=plain > C:\b\bench-clean.log 2>&1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Time-Run "clean" "$gradle"
Time-Run "incremental" "$gradle"
Time-Run "config_cache_prime" "$gradle --configuration-cache"
Time-Run "config_cache_warm" "$gradle --configuration-cache"
