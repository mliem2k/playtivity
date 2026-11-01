package com.mliem.playtivity.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class ActivityParserTest {
    private val now = 1_800_000_000_000L

    @Test fun parsesTracksEpisodesPlaylistsAndContexts() {
        val body = """{
            "friends": [
              null,
              {"timestamp": ${now - 1_000}, "user": {"uri": "spotify:user:a", "name": "A"}, "track": {"name": "T", "artist": {"name": "Ar"}, "album": {"name": "Al"}, "uri": "spotify:track:1"}},
              {"friend": {"timestamp": ${now - 9_000_000}, "user": {"uri": "spotify:user:b", "name": "B"}, "context": {"uri": "spotify:album:9", "name": "Alb"}}},
              {"timestamp": ${now - 2_000}, "user": {"uri": "spotify:user:c"}, "episode": {"name": "E", "show": {"name": "Show"}}},
              {"user": {"uri": "spotify:user:d"}},
              {"user": {"uri": "spotify:user:e"}, "playlist": {"name": "P", "owner": {"name": "Owner"}}}
            ]
        }"""
        val activities = parseFriends(body, now)
        assertEquals(listOf("e", "a", "c", "b"), activities.map { it.user.id })
        assertEquals("Owner", activities[0].playlist?.ownerName)
        assertTrue(activities[1].playing)
        assertEquals("Show", activities[2].track?.artists?.single())
        assertEquals("Alb", activities[3].playlist?.name)
    }

    @Test fun rejectsInvalidBodiesAndMergesByUser() {
        assertTrue(parseFriends("bad", now).isEmpty())
        assertTrue(parseFriends("{}", now).isEmpty())
        assertTrue(parseFriends("""{"friends":[{"user":{"uri":"spotify:user:x"},"context":{"uri":""}}]}""", now).isEmpty())
        val old = Activity(User("a", "A"), Track("Old", emptyList(), "", uri = ""), timestamp = now - 1_000, playing = true)
        val fresh = old.copy(track = old.track?.copy(name = "New"))
        val merged = mergeActivities(listOf(old), listOf(fresh), now + 10 * 60_000)
        assertEquals(1, merged.size)
        assertEquals("New", merged.single().track?.name)
        assertFalse(merged.single().playing)
    }

    @Test fun decodesJwtAndMapsPartialProfile() {
        val payload = Base64.getUrlEncoder().withoutPadding().encodeToString("{\"sub\":\"spotify:user:xyz\"}".toByteArray())
        assertEquals("xyz", userIdFromJwt("h.$payload.s"))
        assertNull(userIdFromJwt("invalid"))
        assertEquals("abc", buildUser("abc", null).displayName)
        assertEquals("abc", buildUser("abc", JSONObject("""{"name":""}""")).displayName)
        assertEquals(User("abc", "Michael", "https://i/x.jpg", 42), buildUser("abc", JSONObject("""{"name":"Michael","image_url":"https://i/x.jpg","followers_count":42}""")))
    }
}
