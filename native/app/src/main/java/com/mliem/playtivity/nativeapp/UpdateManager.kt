package com.mliem.playtivity.nativeapp

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import com.mliem.playtivity.core.AppVersion
import com.mliem.playtivity.core.UpdateCheck
import com.mliem.playtivity.core.UpdateInfo
import com.mliem.playtivity.core.checkNightly
import com.mliem.playtivity.core.checkRelease
import com.mliem.playtivity.core.isNightlyVersion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.io.File

class UpdateManager(private val context: Context, private val client: OkHttpClient = OkHttpClient()) {
    private val preferences = context.getSharedPreferences("playtivity_updates", Context.MODE_PRIVATE)

    var nightly: Boolean
        get() = preferences.getBoolean("enable_nightly", isNightlyVersion(currentVersion().version))
        set(value) { preferences.edit().putBoolean("enable_nightly", value).apply() }

    fun currentVersion(): AppVersion {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return AppVersion(info.versionName ?: "0.0.0", PackageInfoCompat.getLongVersionCode(info).toString())
    }

    suspend fun check(force: Boolean = false): UpdateCheck = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val last = preferences.getLong("last_update_check", 0)
        if (!force && now - last < DAY_MS) return@withContext UpdateCheck(false, false, error = "Too soon since last check")
        try {
            val request = Request.Builder()
                .url("https://api.github.com/repos/mliem2k/playtivity/releases?per_page=100")
                .header("Accept", "application/vnd.github+json")
                .build()
            val releases = client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("HTTP ${response.code}")
                JSONArray(response.body.string())
            }
            preferences.edit().putLong("last_update_check", now).apply()
            val version = currentVersion()
            val nightlyCheck = if (nightly) checkNightly(releases, version) else null
            if (nightlyCheck?.hasUpdate == true) return@withContext nightlyCheck
            val stable = checkRelease(releases, version)
            if (stable.hasUpdate) stable else UpdateCheck(false, false)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            UpdateCheck(false, false, error = "Error checking for updates: ${error.message}")
        }
    }

    suspend fun downloadAndInstall(info: UpdateInfo) = withContext(Dispatchers.IO) {
        require(info.apkUrl.startsWith("https://")) { "Invalid update URL" }
        val directory = File(context.cacheDir, "updates").apply { mkdirs() }
        val filename = info.apkFileName.takeIf { it.matches(Regex("[A-Za-z0-9._-]+\\.apk")) } ?: "playtivity.apk"
        val destination = File(directory, filename)
        if (!destination.exists() || info.fileSizeBytes <= 0 || destination.length() != info.fileSizeBytes) {
            val temp = File(directory, "$filename.tmp")
            try {
                val request = Request.Builder().url(info.apkUrl).build()
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) error("Failed to download update: HTTP ${response.code}")
                    response.body.byteStream().use { input -> temp.outputStream().use(input::copyTo) }
                }
                if (info.fileSizeBytes > 0 && temp.length() != info.fileSizeBytes) error("Incomplete update download")
                if (!temp.renameTo(destination)) error("Could not save update")
            } finally {
                temp.delete()
            }
        }
        val archive = context.packageManager.getPackageArchiveInfo(destination.absolutePath, PackageManager.GET_ACTIVITIES)
        require(archive?.packageName == context.packageName) { "This update is for a different app" }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", destination)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    }

    companion object {
        private const val DAY_MS = 24 * 60 * 60 * 1000L
    }
}
