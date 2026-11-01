package com.mliem.playtivity.nativeapp

import android.app.Application
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
    val sessions by lazy { SessionStore(this) }
    val activityCache by lazy { ActivityCache() }
    val updates by lazy { UpdateManager(this) }
    private val totp by lazy { TotpSecrets() }
    val spotify by lazy { SpotifyHttpClient(totp = totp) }
    val secrets by lazy {
        TotpSecretRepository(totp, object : SecretCache {
            override suspend fun read(): String? = preferences.getString("totp_secrets", null)
            override suspend fun write(value: String) { preferences.edit().putString("totp_secrets", value).apply() }
        })
    }

    inner class ActivityCache {
        fun load(): List<Activity> = preferences.getString("activities_cache", null)?.let(ActivityCacheCodec::decode).orEmpty()
        fun save(activities: List<Activity>) {
            preferences.edit().putString("activities_cache", ActivityCacheCodec.encode(activities)).apply()
        }
        fun clear() {
            preferences.edit().remove("activities_cache").apply()
        }
    }
}
