# Times the same full release rebuild three ways (ccache off, cold, warm), then the configuration cache.
$root = "C:\Users\user\toolchain"
$env:JAVA_HOME = "$root\jdk21"
$env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$root\node;$root\bun;$root\ccache;$env:JAVA_HOME\bin;$env:Path"
$env:CCACHE_DIR = "C:\b\ccache"
$env:CCACHE_SLOPPINESS = "pch_defines,time_macros"
$env:CCACHE_MAXSIZE = "10G"
Set-Location C:\b\pt\android
$gradle = "gradlew.bat -Dorg.gradle.java.home=$root\jdk21 --console=plain -x lintVitalRelease -x lintVitalAnalyzeRelease -PreactNativeArchitectures=arm64-v8a"

function Time-Run($label, $cmd) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  cmd /c "$cmd > C:\b\bench-$label.log 2>&1"
  $sw.Stop()
  $ok = (Select-String -Path "C:\b\bench-$label.log" -Pattern "BUILD SUCCESSFUL" -Quiet)
  "{0,-34} {1,7:N0}s  success={2}" -f $label, $sw.Elapsed.TotalSeconds, $ok
}

Remove-Item Env:CMAKE_C_COMPILER_LAUNCHER, Env:CMAKE_CXX_COMPILER_LAUNCHER -ErrorAction SilentlyContinue
cmd /c "$gradle clean > nul 2>&1"
Time-Run "A_clean_no_ccache" "$gradle assembleRelease --no-build-cache"

$env:CMAKE_C_COMPILER_LAUNCHER = "ccache"; $env:CMAKE_CXX_COMPILER_LAUNCHER = "ccache"
ccache -z | Out-Null
cmd /c "$gradle clean > nul 2>&1"
Time-Run "B_clean_ccache_cold" "$gradle assembleRelease --no-build-cache"
ccache -s | Select-String "Hits|Misses|Cacheable"

cmd /c "$gradle clean > nul 2>&1"
ccache -z | Out-Null
Time-Run "C_clean_ccache_warm" "$gradle assembleRelease --no-build-cache"
ccache -s | Select-String "Hits|Misses|Cacheable"

# Unchanged rebuild: configuration cache off vs on (second run of each is the one that counts).
Time-Run "D1_noop_cfgcache_off_prime" "$gradle assembleRelease --no-configuration-cache"
Time-Run "D2_noop_cfgcache_off" "$gradle assembleRelease --no-configuration-cache"
Time-Run "E1_noop_cfgcache_on_prime" "$gradle assembleRelease --configuration-cache"
Time-Run "E2_noop_cfgcache_on" "$gradle assembleRelease --configuration-cache"
