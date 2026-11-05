package com.mliem.playtivity.nativeapp

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.pm.PackageInfoCompat
import com.mliem.playtivity.core.AppVersion
import com.mliem.playtivity.core.UpdateCheck
import com.mliem.playtivity.core.UpdateInfo
import com.mliem.playtivity.core.checkNightly
import com.mliem.playtivity.core.checkRelease
import com.mliem.playtivity.core.isNightlyVersion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.io.File
import java.security.MessageDigest

class UpdateManager(private val context: Context, private val client: OkHttpClient = OkHttpClient()) {
    private val preferences = context.getSharedPreferences("playtivity_updates", Context.MODE_PRIVATE)

    private val _installError = MutableStateFlow<String?>(null)

    /** Set when the system installer refuses a downloaded update, after [downloadAndInstall] has already returned. */
    val installError: StateFlow<String?> = _installError.asStateFlow()

    fun onInstallFailed(message: String) {
        _installError.value = message
    }

    var nightly: Boolean
        get() = preferences.getBoolean("enable_nightly", isNightlyVersion(currentVersion().version))
        set(value) { preferences.edit().putBoolean("enable_nightly", value).apply() }

    fun currentVersion(): AppVersion {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return AppVersion(info.versionName ?: "0.0.0", PackageInfoCompat.getLongVersionCode(info).toString())
    }

    suspend fun check(force: Boolean = false): UpdateCheck = withContext(Dispatchers.IO) {
        if (context.packageName != PRODUCTION_PACKAGE) {
            return@withContext UpdateCheck(false, false, error = "Updates are available in the official Playtivity app")
        }
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
        if (!checksumMatches(sha256Of(destination), info.sha256)) {
            destination.delete()
            error("The downloaded file did not match its checksum, so it was not installed")
        }
        if (!context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            error("Allow Playtivity to install apps in the settings screen that just opened, then tap Install again")
        }
        _installError.value = null
        commit(destination)
    }

    private fun sha256Of(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun commit(apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("update.apk", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            // The installer fills in the status extras, so this PendingIntent has to be mutable.
            val callback = PendingIntent.getBroadcast(
                context,
                sessionId,
                Intent(context, InstallResultReceiver::class.java).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            session.commit(callback.intentSender)
        }
    }

    companion object {
        private const val DAY_MS = 24 * 60 * 60 * 1000L
        private const val PRODUCTION_PACKAGE = "com.mliem.playtivity"

        /** GitHub reports a digest for new assets; an older asset has none and is accepted on size alone. */
        internal fun checksumMatches(actualHex: String, expected: String?) =
            expected == null || actualHex.equals(expected, ignoreCase = true)
    }
}
