package com.mliem.playtivity.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

interface SecretCache {
    suspend fun read(): String?
    suspend fun write(value: String)
}

class TotpSecretRepository(
    private val secrets: TotpSecrets,
    private val cache: SecretCache,
    private val client: OkHttpClient = OkHttpClient(),
    private val url: String = "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true",
) {
    suspend fun initialize(scope: CoroutineScope, now: Long = System.currentTimeMillis()) {
        val cached = try {
            cache.read()?.let(::JSONObject)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
        val table = cached?.optJSONObject("data")?.toSecretTable()
        if (table != null) secrets.apply(table)
        if (table == null || now - cached.optLong("at") > SIX_HOURS_MS) {
            scope.launch { refresh() }
        }
    }

    suspend fun refresh(now: Long = System.currentTimeMillis()): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url(url).header("Accept", "application/json").build()
            val json = client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext false
                JSONObject(response.body.string())
            }
            val table = json.toSecretTable() ?: return@withContext false
            secrets.apply(table)
            cache.write(JSONObject().put("at", now).put("data", json).toString())
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            false
        }
    }

    private fun JSONObject.toSecretTable(): Map<Int, List<Int>>? {
        val keys = keys().asSequence().toList()
        if (keys.isEmpty()) return null
        return buildMap {
            for (key in keys) {
                val version = key.takeIf { it.isNotEmpty() && it.all(Char::isDigit) }?.toIntOrNull() ?: return null
                val values = optJSONArray(key) ?: return null
                if (values.length() == 0) return null
                val bytes = (0 until values.length()).map { index ->
                    val value = values.opt(index)
                    if (value !is Number || value.toDouble() % 1.0 != 0.0 || value.toInt() !in 0..255) return null
                    value.toInt()
                }
                put(version, bytes)
            }
        }
    }

    companion object {
        private const val SIX_HOURS_MS = 6 * 60 * 60 * 1000L
    }
}
