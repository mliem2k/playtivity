package com.mliem.playtivity.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityCacheCodecTest {
    @Test fun roundTripsActivityAndCapsStorage() {
        val activities = (0..50).map { index ->
            Activity(User(index.toString(), "Friend $index", "https://image/$index"), Track("Song", listOf("Singer"), "Album", uri = "spotify:track:$index"), timestamp = index.toLong(), playing = index == 0)
        }
        val decoded = ActivityCacheCodec.decode(ActivityCacheCodec.encode(activities))
        assertEquals(50, decoded.size)
        assertEquals(activities.take(50), decoded)
        assertTrue(ActivityCacheCodec.decode("bad").isEmpty())
    }
}
