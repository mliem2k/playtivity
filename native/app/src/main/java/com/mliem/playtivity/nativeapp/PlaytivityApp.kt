package com.mliem.playtivity.nativeapp

import android.app.Application
import com.mliem.android.update.Channel
import com.mliem.android.update.UpdateClient
import com.mliem.android.update.UpdateConfig
import com.mliem.android.update.UpdateMessages
import com.mliem.playtivity.core.SecretCache
import com.mliem.playtivity.core.Activity
import com.mliem.playtivity.core.ActivityCacheCodec
import com.mliem.playtivity.core.SpotifyHttpClient
import com.mliem.playtivity.core.TotpSecretRepository
import com.mliem.playtivity.core.TotpSecrets

class PlaytivityApp : Application() {
    private val preferences by lazy { getSharedPreferences("playtivity", MODE_PRIVATE) }
    var hapticsEnabled: Boolean
        get() = preferences.getBoolean("haptics", true)
        set(value) { preferences.edit().putBoolean("haptics", value).apply() }
    var nightlyUpdates: Boolean
        get() = preferences.getBoolean("enable_nightly", updates.currentVersion.versionName.contains("-nightly-"))
        set(value) { preferences.edit().putBoolean("enable_nightly", value).apply() }
    val sessions by lazy { SessionStore(this) }
    val activityCache by lazy { ActivityCache() }
    val updates by lazy {
        UpdateClient(
            context = this,
            config = UpdateConfig(
                repo = "mliem2k/playtivity",
                installReceiver = InstallResultReceiver::class.java,
                channels = listOf(Channel.STABLE),
                updatesEnabled = packageName == PRODUCTION_PACKAGE,
                minCheckIntervalMillis = DAY_MS,
                messages = UpdateMessages(
                    permission = "Allow Playtivity to install apps in the settings screen that just opened, then tap Install again.",
                    signature = "This build is signed with a different key than the installed app. Uninstall Playtivity once, then install the new APK.",
                    installFailed = "The installer could not install the update.",
                ),
            ),
        )
    }
    private val totp by lazy { TotpSecrets() }
    val spotify by lazy { SpotifyHttpClient(totp = totp) }
    val secrets by lazy {
        TotpSecretRepository(totp, object : SecretCache {
            override suspend fun read(): String? = preferences.getString("totp_secrets", null)
            override suspend fun write(value: String) { preferences.edit().putString("totp_secrets", value).apply() }
        })
    }

    /** Nightly first when opted in, then the latest stable release. */
    fun updateChannels(): List<Channel> =
        if (nightlyUpdates) listOf(Channel.NIGHTLY, Channel.STABLE) else listOf(Channel.STABLE)

    inner class ActivityCache {
        fun load(): List<Activity> = preferences.getString("activities_cache", null)?.let(ActivityCacheCodec::decode).orEmpty()
        fun save(activities: List<Activity>) {
            preferences.edit().putString("activities_cache", ActivityCacheCodec.encode(activities)).apply()
        }
        fun clear() {
            preferences.edit().remove("activities_cache").apply()
        }
    }

    private companion object {
        const val PRODUCTION_PACKAGE = "com.mliem.playtivity"
        const val DAY_MS = 24 * 60 * 60 * 1000L
    }
}
