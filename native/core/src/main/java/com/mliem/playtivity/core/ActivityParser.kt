package com.mliem.playtivity.core

import org.json.JSONObject
import java.util.Base64

private const val PLAYING_MS = 5 * 60 * 1000L

fun parseFriends(body: String, now: Long = System.currentTimeMillis()): List<Activity> {
    val friends = runCatching { JSONObject(body).optJSONArray("friends") }.getOrNull() ?: return emptyList()
    return buildList {
        for (index in 0 until friends.length()) {
            val entry = friends.optJSONObject(index) ?: continue
            val friend = entry.optJSONObject("friend")
            val data = if (friend?.optJSONObject("user") != null) friend else entry
            val userData = data.optJSONObject("user") ?: continue
            val user = User(
                id = userData.optString("uri").removePrefix("spotify:user:"),
                displayName = userData.optStringOr("name", "Unknown User"),
                imageUrl = userData.optStringOrNull("imageUrl"),
            )
            val timestamp = data.optLongOrNull("timestamp") ?: now
            val live = now - timestamp in 0 until PLAYING_MS
            val playlist = data.optJSONObject("playlist")
            val track = data.optJSONObject("track")
            val episode = data.optJSONObject("episode")
            val context = data.optJSONObject("context")
            when {
                playlist != null -> add(
                    Activity(
                        user = user,
                        playlist = Playlist(
                            name = playlist.optStringOr("name", "Unknown Playlist"),
                            imageUrl = playlist.optStringOrNull("imageUrl"),
                            trackCount = playlist.optInt("trackCount"),
                            uri = playlist.optString("uri"),
                            ownerName = playlist.optJSONObject("owner")?.optStringOr("name", "Unknown") ?: "Unknown",
                        ),
                        timestamp = timestamp,
                        playing = false,
                    ),
                )
                track != null -> add(
                    Activity(
                        user = user,
                        track = Track(
                            name = track.optStringOr("name", "Unknown Track"),
                            artists = listOf(track.optJSONObject("artist")?.optStringOr("name", "Unknown Artist") ?: "Unknown Artist"),
                            album = track.optJSONObject("album")?.optStringOr("name", "Unknown Album") ?: "Unknown Album",
                            imageUrl = track.optStringOrNull("imageUrl") ?: track.optJSONObject("album")?.optStringOrNull("imageUrl"),
                            uri = track.optString("uri"),
                        ),
                        timestamp = timestamp,
                        playing = live,
                    ),
                )
                episode != null -> {
                    val show = episode.optJSONObject("show")?.optStringOr("name", "Unknown Podcast") ?: "Unknown Podcast"
                    add(
                        Activity(
                            user = user,
                            track = Track(
                                name = episode.optStringOr("name", "Unknown Episode"),
                                artists = listOf(show),
                                album = show,
                                imageUrl = episode.optStringOrNull("imageUrl") ?: episode.optJSONObject("show")?.optStringOrNull("imageUrl"),
                                uri = episode.optString("uri"),
                            ),
                            timestamp = timestamp,
                            playing = live,
                        ),
                    )
                }
                !context?.optStringOrNull("uri").isNullOrEmpty() -> add(
                    Activity(
                        user = user,
                        playlist = Playlist(
                            name = context.optStringOr("name", "Spotify"),
                            imageUrl = context.optStringOrNull("imageUrl"),
                            uri = context.optString("uri"),
                            ownerName = "",
                        ),
                        timestamp = timestamp,
                        playing = false,
                    ),
                )
            }
        }
    }.sortedByDescending(Activity::timestamp)
}

fun mergeActivities(existing: List<Activity>, fresh: List<Activity>, now: Long = System.currentTimeMillis()): List<Activity> =
    (existing + fresh).associateBy { it.user.id }.values
        .map { it.copy(playing = it.track != null && now - it.timestamp in 0 until PLAYING_MS) }
        .sortedByDescending(Activity::timestamp)

fun userIdFromJwt(token: String): String? {
    val payload = token.split('.').getOrNull(1) ?: return null
    return runCatching {
        val json = JSONObject(String(Base64.getUrlDecoder().decode(payload)))
        json.optStringOrNull("sub")?.takeIf(String::isNotEmpty)?.removePrefix("spotify:user:")
    }.getOrNull()
}

fun buildUser(id: String, body: JSONObject?): User = User(
    id = id,
    displayName = body?.optStringOrNull("name")?.takeIf(String::isNotEmpty) ?: id,
    imageUrl = body?.optStringOrNull("image_url"),
    followers = body?.optInt("followers_count") ?: 0,
)

internal fun JSONObject.optStringOrNull(key: String): String? =
    optString(key).takeIf { has(key) && !isNull(key) }

internal fun JSONObject.optStringOr(key: String, fallback: String): String = optStringOrNull(key) ?: fallback

private fun JSONObject.optLongOrNull(key: String): Long? =
    opt(key).takeIf { it is Number && it.toDouble().isFinite() && it.toDouble() % 1.0 == 0.0 }?.let { (it as Number).toLong() }
