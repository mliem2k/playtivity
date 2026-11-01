package com.mliem.playtivity.core

import org.json.JSONArray
import org.json.JSONObject

object ActivityCacheCodec {
    fun encode(activities: List<Activity>): String = JSONArray().apply {
        activities.take(50).forEach { activity ->
            put(JSONObject().apply {
                put("user", JSONObject().apply {
                    put("id", activity.user.id)
                    put("displayName", activity.user.displayName)
                    put("imageUrl", activity.user.imageUrl)
                    put("followers", activity.user.followers)
                })
                activity.track?.let { track ->
                    put("track", JSONObject().apply {
                        put("name", track.name)
                        put("artists", JSONArray(track.artists))
                        put("album", track.album)
                        put("imageUrl", track.imageUrl)
                        put("uri", track.uri)
                        put("durationMs", track.durationMs)
                    })
                }
                activity.playlist?.let { playlist ->
                    put("playlist", JSONObject().apply {
                        put("name", playlist.name)
                        put("imageUrl", playlist.imageUrl)
                        put("trackCount", playlist.trackCount)
                        put("uri", playlist.uri)
                        put("ownerName", playlist.ownerName)
                    })
                }
                put("timestamp", activity.timestamp)
                put("playing", activity.playing)
            })
        }
    }.toString()

    fun decode(body: String): List<Activity> = runCatching {
        val array = JSONArray(body)
        buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val userData = item.optJSONObject("user") ?: continue
                val user = User(
                    id = userData.optString("id"),
                    displayName = userData.optString("displayName"),
                    imageUrl = userData.optStringOrNull("imageUrl"),
                    followers = userData.optInt("followers"),
                )
                val trackData = item.optJSONObject("track")
                val artists = trackData?.optJSONArray("artists")
                val track = trackData?.let {
                    Track(
                        name = it.optString("name"),
                        artists = buildList { for (artistIndex in 0 until (artists?.length() ?: 0)) add(artists?.optString(artistIndex).orEmpty()) },
                        album = it.optString("album"),
                        imageUrl = it.optStringOrNull("imageUrl"),
                        uri = it.optString("uri"),
                        durationMs = it.optLong("durationMs"),
                    )
                }
                val playlist = item.optJSONObject("playlist")?.let {
                    Playlist(it.optString("name"), it.optStringOrNull("imageUrl"), it.optInt("trackCount"), it.optString("uri"), it.optString("ownerName"))
                }
                add(Activity(user, track, playlist, item.optLong("timestamp"), item.optBoolean("playing")))
            }
        }
    }.getOrDefault(emptyList())
}
