package com.mliem.playtivity.core

import org.json.JSONArray
import org.json.JSONObject

fun parseTopContent(body: String): TopContent {
    val profile = runCatching { JSONObject(body).optJSONObject("data")?.optJSONObject("me")?.optJSONObject("profile") }.getOrNull()
    val tracks = profile?.optJSONObject("topTracks")?.optJSONArray("items").mapObjects { item ->
        val track = item.optJSONObject("data") ?: item
        Track(
            name = track.optStringOr("name", "Unknown Track"),
            artists = track.optJSONObject("artists")?.optJSONArray("items").mapObjects { artist ->
                artist.optJSONObject("profile")?.optStringOr("name", "Unknown Artist") ?: "Unknown Artist"
            },
            album = track.optJSONObject("albumOfTrack")?.optStringOr("name", "Unknown Album") ?: "Unknown Album",
            imageUrl = bestImage(track.optJSONObject("albumOfTrack")?.optJSONObject("coverArt")?.optJSONArray("sources"), 300),
            uri = track.optString("uri"),
            durationMs = track.optJSONObject("duration")?.optLong("totalMilliseconds") ?: 0,
        )
    }
    val artists = profile?.optJSONObject("topArtists")?.optJSONArray("items").mapObjects { item ->
        val artist = item.optJSONObject("data") ?: item
        Artist(
            name = artist.optJSONObject("profile")?.optStringOr("name", "Unknown Artist") ?: "Unknown Artist",
            imageUrl = bestImage(artist.optJSONObject("visuals")?.optJSONObject("avatarImage")?.optJSONArray("sources"), 320),
            uri = artist.optString("uri"),
        )
    }
    return TopContent(tracks, artists)
}

fun parseCurrentlyPlaying(body: String): Track? {
    val item = runCatching { JSONObject(body).optJSONObject("item") }.getOrNull() ?: return null
    val album = item.optJSONObject("album")
    return Track(
        name = item.optString("name"),
        artists = item.optJSONArray("artists").mapObjects { it.optStringOrNull("name") }.filterNotNull(),
        album = album?.optString("name").orEmpty(),
        imageUrl = album?.optJSONArray("images")?.optJSONObject(0)?.optStringOrNull("url"),
        uri = item.optString("uri"),
        durationMs = item.optLong("duration_ms"),
    )
}

fun parseArtistListeners(body: String): Int = runCatching {
    JSONObject(body).optJSONObject("data")?.optJSONObject("artist")?.optJSONObject("stats")?.optInt("monthlyListeners") ?: 0
}.getOrDefault(0)

fun parseAccountProfile(body: String): AccountProfile? {
    val profile = runCatching { JSONObject(body).optJSONObject("profile") }.getOrNull() ?: return null
    return AccountProfile(profile.optString("username"), profile.optString("email"), profile.optString("country"))
}

fun spotifyUrl(uri: String): String {
    val parts = uri.split(':')
    return if (parts.size >= 3 && parts[1].isNotEmpty() && parts[2].isNotEmpty())
        "https://open.spotify.com/${parts[1]}/${parts[2]}"
    else "https://open.spotify.com/"
}

private fun bestImage(sources: JSONArray?, preferredHeight: Int): String? {
    val images = sources.mapObjects { it }
    return (images.firstOrNull { it.optInt("height") == preferredHeight }
        ?: images.maxByOrNull { it.optInt("height") })?.optStringOrNull("url")
}

private inline fun <T> JSONArray?.mapObjects(transform: (JSONObject) -> T): List<T> = buildList {
    val array = this@mapObjects ?: return@buildList
    for (index in 0 until array.length()) {
        array.optJSONObject(index)?.let { add(transform(it)) }
    }
}
