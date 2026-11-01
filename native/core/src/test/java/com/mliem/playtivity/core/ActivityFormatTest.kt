package com.mliem.playtivity.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ActivityFormatTest {
    private val now = 1_800_000_000_000L
    private fun activity(id: String, timestamp: Long, playing: Boolean = false) =
        Activity(User(id, id), Track("t", emptyList(), "", uri = ""), timestamp = timestamp, playing = playing)

    @Test fun formatsFeedAndWidgetTime() {
        assertEquals("a moment ago", timeAgo(now - 10_000, now))
        assertEquals("a minute ago", timeAgo(now - 60_000, now))
        assertEquals("5 minutes ago", timeAgo(now - 5 * 60_000, now))
        assertEquals("about an hour ago", timeAgo(now - 60 * 60_000, now))
        assertEquals("3 hours ago", timeAgo(now - 3 * 3_600_000, now))
        assertEquals("a day ago", timeAgo(now - 30 * 3_600_000, now))
        assertEquals("5 days ago", timeAgo(now - 5 * 86_400_000, now))
        assertEquals("Just now", widgetTimeText(activity("a", now - 10_000), now))
        assertEquals("5m ago", widgetTimeText(activity("a", now - 5 * 60_000), now))
        assertEquals("Listening now", widgetTimeText(activity("a", now, true), now))
    }

    @Test fun formatsNumbersAndSortsWidget() {
        assertEquals("999", formatCount(999))
        assertEquals("1.5K", formatCount(1500))
        assertEquals("2.5M", formatCount(2_500_000))
        assertEquals("3:05", formatDuration(185_000))
        assertEquals("0:00", formatDuration())
        assertEquals(listOf("live", "new", "old"), sortForWidget(listOf(activity("old", 1), activity("new", 5), activity("live", 2, true))).map { it.user.id })
    }

    @Test fun widgetSignatureBucketsMinutes() {
        val activities = listOf(activity("a", now - 7 * 60_000), activity("b", now - 3 * 3_600_000))
        assertEquals(widgetSignature(activities, now), widgetSignature(activities, now + 60_000))
        assertNotEquals(widgetSignature(activities, now), widgetSignature(activities, now + 8 * 60_000))
        assertNotEquals(widgetSignature(activities, now), widgetSignature(activities + activity("c", now - 1_000, true), now))
    }
}
