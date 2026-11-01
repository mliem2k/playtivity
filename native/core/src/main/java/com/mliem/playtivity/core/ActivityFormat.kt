package com.mliem.playtivity.core

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max

fun timeAgo(timestamp: Long, now: Long = System.currentTimeMillis()): String {
    val seconds = max(0, (now - timestamp) / 1000)
    val minutes = seconds / 60
    val hours = minutes / 60
    val days = hours / 24
    return when {
        seconds < 45 -> "a moment ago"
        seconds < 90 -> "a minute ago"
        minutes < 45 -> "$minutes minutes ago"
        minutes < 90 -> "about an hour ago"
        hours < 24 -> "$hours hours ago"
        hours < 48 -> "a day ago"
        days < 30 -> "$days days ago"
        days < 60 -> "about a month ago"
        days < 365 -> "${days / 30} months ago"
        days < 730 -> "about a year ago"
        else -> "${days / 365} years ago"
    }
}

fun formatCount(count: Int): String = when {
    count >= 1_000_000 -> String.format(Locale.US, "%.1fM", count / 1_000_000.0)
    count >= 1_000 -> String.format(Locale.US, "%.1fK", count / 1_000.0)
    else -> count.toString()
}

fun formatDuration(durationMs: Long = 0): String {
    val totalSeconds = durationMs / 1000
    return "${totalSeconds / 60}:${(totalSeconds % 60).toString().padStart(2, '0')}"
}

fun widgetTimeText(activity: Activity, now: Long = System.currentTimeMillis()): String {
    if (activity.playing) return "Listening now"
    val minutes = Math.floorDiv(now - activity.timestamp, 60_000L)
    return when {
        minutes < 1 -> "Just now"
        minutes < 60 -> "${minutes}m ago"
        minutes < 1_440 -> "${minutes / 60}h ago"
        minutes < 10_080 -> "${minutes / 1_440}d ago"
        else -> SimpleDateFormat("MMM dd", Locale.US).format(Date(activity.timestamp))
    }
}

fun sortForWidget(activities: List<Activity>): List<Activity> =
    activities.sortedWith(compareByDescending<Activity> { it.playing }.thenByDescending { it.timestamp })

fun widgetSignature(activities: List<Activity>, now: Long = System.currentTimeMillis()): String =
    sortForWidget(activities).joinToString("\n") { activity ->
        val minutes = Math.floorDiv(now - activity.timestamp, 60_000L)
        val time = if (!activity.playing && minutes in 1..59) "${minutes / 5}x5m" else widgetTimeText(activity, now)
        listOf(
            activity.user.id,
            activity.user.displayName,
            activity.user.imageUrl.orEmpty(),
            activity.track?.name ?: activity.playlist?.name.orEmpty(),
            activity.track?.artists?.joinToString(",") ?: activity.playlist?.ownerName.orEmpty(),
            activity.track?.imageUrl ?: activity.playlist?.imageUrl.orEmpty(),
            activity.playing.toString(),
            time,
        ).joinToString("|")
    }
