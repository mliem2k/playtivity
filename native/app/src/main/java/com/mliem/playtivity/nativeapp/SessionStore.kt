package com.mliem.playtivity.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.webkit.CookieManager
import com.mliem.playtivity.core.spotifySessionCookie
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SessionStore(context: Context) {
    private val preferences = context.getSharedPreferences("playtivity_session", Context.MODE_PRIVATE)

    fun readCookie(): String? = try {
        val stored = preferences.getString("sp_dc", null) ?: return null
        val bytes = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    } catch (_: Exception) {
        preferences.edit().remove("sp_dc").apply()
        null
    }

    fun readOrImportCookie(): String? {
        readCookie()?.let { return it }
        if (preferences.getBoolean("web_cookie_checked", false)) return null
        val cookieHeader = try {
            CookieManager.getInstance().getCookie("https://open.spotify.com")
        } catch (_: Exception) {
            return null
        }
        val cookie = spotifySessionCookie(cookieHeader)
        if (cookie != null) {
            saveCookie(cookie)
            preferences.edit().putBoolean("web_cookie_checked", true).apply()
        }
        return cookie
    }

    fun saveCookie(cookie: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val bytes = cipher.iv + cipher.doFinal(cookie.toByteArray(Charsets.UTF_8))
        preferences.edit().putString("sp_dc", Base64.encodeToString(bytes, Base64.NO_WRAP)).apply()
    }

    fun clear() {
        preferences.edit().remove("sp_dc").putBoolean("web_cookie_checked", true).apply()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "playtivity_session"
    }
}
