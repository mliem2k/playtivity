package com.mliem.playtivity.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

data class SpotifyEndpoints(
    val open: String = "https://open.spotify.com",
    val spClient: String = "https://guc-spclient.spotify.com",
    val partner: String = "https://api-partner.spotify.com",
    val api: String = "https://api.spotify.com",
    val account: String = "https://www.spotify.com",
)

class SpotifyAuthException(message: String) : Exception(message)

class SpotifyHttpClient(
    private val client: OkHttpClient = OkHttpClient(),
    private val totp: TotpSecrets = TotpSecrets(),
    private val endpoints: SpotifyEndpoints = SpotifyEndpoints(),
) {
    suspend fun fetchBearerToken(spDc: String): String? = withContext(Dispatchers.IO) {
        val serverTime = try {
            val request = Request.Builder().url(endpoints.open).get().build()
            client.newCall(request).execute().use { response ->
                ZonedDateTime.parse(response.header("Date"), DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli()
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            System.currentTimeMillis()
        }
        val code = totp.generateCode(serverTime)
        val url = "${endpoints.open}/api/token".toHttpUrl().newBuilder()
            .addQueryParameter("reason", "transport")
            .addQueryParameter("productType", "web-player")
            .addQueryParameter("totp", code)
            .addQueryParameter("totpServer", code)
            .addQueryParameter("totpVer", totp.activeVersion.toString())
            .build()
        val request = Request.Builder().url(url).get()
            .header("Cookie", "sp_dc=$spDc")
            .header("User-Agent", WEB_USER_AGENT)
            .header("Accept", "application/json")
            .header("App-Platform", "WebPlayer")
            .header("Referer", "${endpoints.open}/")
            .header("Origin", endpoints.open)
            .build()
        val response = execute(request)
        if (response.code != 200) return@withContext null
        val json = runCatching { JSONObject(response.body) }.getOrNull()
        json?.optStringOrNull("accessToken")?.takeUnless { json.optBoolean("isAnonymous") }
    }

    suspend fun fetchAccountProfile(spDc: String): AccountProfile? = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url("${endpoints.account}/api/account-settings/v1/profile")
                .header("Cookie", "sp_dc=$spDc")
                .header("User-Agent", WEB_USER_AGENT)
                .header("Accept", "application/json")
                .header("Referer", "${endpoints.account}/account/overview/")
                .build()
            execute(request).takeIf { it.code == 200 }?.let { parseAccountProfile(it.body) }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    suspend fun fetchProfile(token: String, id: String): User? = withContext(Dispatchers.IO) {
        val response = execute(webRequest("${endpoints.spClient}/user-profile-view/v3/profile/$id", token))
        if (response.code != 200) return@withContext null
        buildUser(id, runCatching { JSONObject(response.body) }.getOrNull())
    }

    suspend fun fetchBuddyList(token: String): String = retry {
        val response = withContext(Dispatchers.IO) {
            execute(webRequest("${endpoints.spClient}/presence-view/v1/buddylist", token))
        }
        check(response, "friend activity")
        response.body
    }

    suspend fun fetchTop(token: String, limit: Int = 20): TopContent = retry {
        val range = JSONObject().put("offset", 0).put("limit", limit).put("sortBy", "AFFINITY").put("timeRange", "SHORT_TERM")
        val variables = JSONObject()
            .put("includeTopTracks", true).put("topTracksInput", range)
            .put("includeTopArtists", true).put("topArtistsInput", range)
        val payload = JSONObject()
            .put("operationName", "userTopContent")
            .put("variables", variables)
            .put("extensions", JSONObject().put("persistedQuery", JSONObject().put("version", 1).put("sha256Hash", TOP_HASH)))
        val request = webRequest("${endpoints.partner}/pathfinder/v2/query", token).newBuilder()
            .post(payload.toString().toRequestBody("application/json;charset=UTF-8".toMediaType())).build()
        val response = withContext(Dispatchers.IO) { execute(request) }
        check(response, "top content")
        parseTopContent(response.body)
    }

    suspend fun fetchCurrentlyPlaying(token: String): Track? = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("${endpoints.api}/v1/me/player/currently-playing")
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json, text/plain, */*")
            .header("User-Agent", "okhttp/4.9.2")
            .build()
        execute(request).takeIf { it.code == 200 }?.let { parseCurrentlyPlaying(it.body) }
    }

    suspend fun fetchArtistListeners(token: String, artistId: String): Int = try {
        retry {
            val variables = JSONObject().put("uri", "spotify:artist:$artistId").put("locale", "").put("includePrerelease", true)
            val extensions = JSONObject().put("persistedQuery", JSONObject().put("version", 1).put("sha256Hash", ARTIST_HASH))
            val url = "${endpoints.partner}/pathfinder/v1/query".toHttpUrl().newBuilder()
                .addQueryParameter("operationName", "queryArtistOverview")
                .addQueryParameter("variables", variables.toString())
                .addQueryParameter("extensions", extensions.toString())
                .build()
            val response = withContext(Dispatchers.IO) { execute(webRequest(url.toString(), token)) }
            check(response, "artist details")
            parseArtistListeners(response.body)
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        -1
    }

    private fun webRequest(url: String, token: String): Request = Request.Builder().url(url)
        .header("Authorization", "Bearer $token")
        .header("App-Platform", "WebPlayer")
        .header("Accept", "application/json")
        .header("Accept-Language", "en")
        .header("Origin", endpoints.open)
        .header("Referer", "${endpoints.open}/")
        .header("User-Agent", WEB_USER_AGENT)
        .build()

    private fun execute(request: Request): HttpResult = client.newCall(request).execute().use { response ->
        HttpResult(response.code, response.body.string())
    }

    private fun check(response: HttpResult, what: String) {
        if (response.code == 401 || response.code == 403) throw SpotifyAuthException("Authentication error: ${response.code}")
        if (response.code != 200) error("Failed to fetch $what: ${response.code}")
    }

    private suspend fun <T> retry(tries: Int = 3, action: suspend () -> T): T {
        repeat(tries - 1) { attempt ->
            try {
                return action()
            } catch (error: SpotifyAuthException) {
                throw error
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                delay((if (error.message?.contains("429") == true) 5_000L else 50L) * (1L shl attempt))
            }
        }
        return action()
    }

    private data class HttpResult(val code: Int, val body: String)

    companion object {
        const val WEB_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"
        private const val TOP_HASH = "feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2"
        private const val ARTIST_HASH = "d66221ea13998b2f81883c5187d174c8646e4041d67f5b1e103bc262d447e3a0"
    }
}
