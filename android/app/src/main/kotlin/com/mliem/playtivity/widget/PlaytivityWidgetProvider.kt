package com.mliem.playtivity.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.components.Scaffold
import androidx.glance.appwidget.components.TitleBar
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.mliem.playtivity.MainActivity
import com.mliem.playtivity.R

data class FriendActivity(
    val friendName: String,
    val trackName: String,
    val artistName: String,
    val friendImageUrl: String,
    val cachedImagePath: String = "",
    val friendUserId: String = "",
    val timestamp: Long = 0L,
    val isCurrentlyPlaying: Boolean = false,
    val activityType: String = "track"
) {
    fun getStatusText(): String {
        val currentTime = System.currentTimeMillis()
        val timestampDate = if (timestamp > 0) timestamp else currentTime
        val timeDiffMinutes = (currentTime - timestampDate) / (1000 * 60)
        
        // Consider recent if within 1 minute (like Flutter app)
        val isRecent = timeDiffMinutes < 1
        
        return when {
            isCurrentlyPlaying || isRecent -> {
                if (activityType == "playlist") {
                    "Listening to playlist now"
                } else {
                    "Listening now"
                }
            }
            else -> {
                if (activityType == "playlist") {
                    "Played playlist ${formatTimeAgo(timeDiffMinutes)}"
                } else {
                    "Played ${formatTimeAgo(timeDiffMinutes)}"
                }
            }
        }
    }
    
    fun isRecentOrPlaying(): Boolean {
        val currentTime = System.currentTimeMillis()
        val timestampDate = if (timestamp > 0) timestamp else currentTime
        val timeDiffMinutes = (currentTime - timestampDate) / (1000 * 60)
        return isCurrentlyPlaying || timeDiffMinutes < 1
    }
    
    private fun formatTimeAgo(minutes: Long): String {
        return when {
            minutes < 1 -> "just now"
            minutes < 60 -> "${minutes}m ago"
            minutes < 1440 -> "${minutes / 60}h ago"
            else -> "${minutes / 1440}d ago"
        }
    }
}

class PlaytivityAppWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                PlaytivityContent(context)
            }
        }
    }

    @Composable
    private fun PlaytivityContent(context: Context) {
        // Read widget data from home_widget SharedPreferences (without flutter. prefix)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        
        // Force a fresh read by logging timestamp
        val currentTime = System.currentTimeMillis()
        val lastUpdate = prefs.getString("last_update", "never") ?: "never"
        
        val activitiesCount = prefs.getString("activities_count", "0")?.toIntOrNull() ?: 0
        
        // Debug: Log what data we're reading with timestamp
        android.util.Log.d("PlaytivityWidget", "Reading widget data at $currentTime:")
        android.util.Log.d("PlaytivityWidget", "  last_update: $lastUpdate")
        android.util.Log.d("PlaytivityWidget", "  activities_count: $activitiesCount")
        
        // Log all preferences keys for debugging
        val allPrefs = prefs.all
        android.util.Log.d("PlaytivityWidget", "All HomeWidget preferences keys: ${allPrefs.keys}")
        
        // Enhanced debugging: Check if we have data for more friends than activitiesCount suggests
        for (i in 0 until activitiesCount) {
            val friendName = prefs.getString("friend_${i}_name", "") ?: ""
            val friendTrack = prefs.getString("friend_${i}_track", "") ?: ""
            val friendArtist = prefs.getString("friend_${i}_artist", "") ?: ""
            val friendImage = prefs.getString("friend_${i}_image", "") ?: ""
            android.util.Log.d("PlaytivityWidget", "  friend_${i}: $friendName - $friendTrack by $friendArtist (image: $friendImage)")
        }
        
        // Additional debugging: Check if there are more friends beyond the activitiesCount
        android.util.Log.d("PlaytivityWidget", "Checking for additional friends beyond activitiesCount...")
        var foundAdditionalFriends = 0
        for (i in activitiesCount until (activitiesCount + 10)) {
            val friendName = prefs.getString("friend_${i}_name", "") ?: ""
            val friendTrack = prefs.getString("friend_${i}_track", "") ?: ""
            if (friendName.isNotEmpty() && friendTrack.isNotEmpty()) {
                foundAdditionalFriends++
                android.util.Log.d("PlaytivityWidget", "  EXTRA friend_${i}: $friendName - $friendTrack")
            }
        }
        android.util.Log.d("PlaytivityWidget", "Found $foundAdditionalFriends additional friends beyond activitiesCount")
        
        Scaffold(
            titleBar = {
                TitleBar(
                    startIcon = ImageProvider(R.drawable.ic_music_note),
                    title = "Friends' Activities",
                    actions = {
                        Image(
                            provider = ImageProvider(R.drawable.ic_refresh),
                            contentDescription = "Refresh",
                            modifier = GlanceModifier
                                .size(24.dp)
                                .clickable(actionRunCallback<RefreshWidgetCallback>())
                        )
                    }
                )
            },
            backgroundColor = GlanceTheme.colors.widgetBackground,
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(12.dp)
        ) {
            if (activitiesCount > 0) {
                ActivitiesView(prefs, activitiesCount)
            } else {
                NoActivitiesView()
            }
        }
    }

    @Composable
    private fun NoActivitiesView() {
        Box(
            modifier = GlanceModifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Image(
                    provider = ImageProvider(R.drawable.ic_person),
                    contentDescription = "No activities",
                    modifier = GlanceModifier.size(32.dp)
                )
                Spacer(modifier = GlanceModifier.height(8.dp))
                Text(
                    text = "No recent activities",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurface,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                Text(
                    text = "Friends haven't been listening recently",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 10.sp
                    )
                )
            }
        }
    }

    @Composable
    private fun ActivitiesView(prefs: android.content.SharedPreferences, activitiesCount: Int) {
        android.util.Log.d("PlaytivityWidget", "ActivitiesView called with activitiesCount: $activitiesCount")
        
        // Create a list of all valid activities
        val activities = (0 until activitiesCount).mapNotNull { index ->
            val friendName = prefs.getString("friend_${index}_name", "") ?: ""
            val friendTrack = prefs.getString("friend_${index}_track", "") ?: ""
            val friendArtist = prefs.getString("friend_${index}_artist", "") ?: ""
            val friendImage = prefs.getString("friend_${index}_image", "") ?: ""
            val cachedImagePath = prefs.getString("friend_${index}_cached_image", "") ?: ""
            val friendUserId = prefs.getString("friend_${index}_user_id", "") ?: ""
            val timestampString = prefs.getString("friend_${index}_timestamp", "0") ?: "0"
            val isCurrentlyPlayingString = prefs.getString("friend_${index}_is_currently_playing", "false") ?: "false"
            val activityType = prefs.getString("friend_${index}_activity_type", "track") ?: "track"
            
            val timestamp = timestampString.toLongOrNull() ?: 0L
            val isCurrentlyPlaying = isCurrentlyPlayingString.toBoolean()
            
            val isValid = friendName.isNotEmpty() && friendTrack.isNotEmpty()
            android.util.Log.d("PlaytivityWidget", "Activity $index: name='$friendName', track='$friendTrack', valid=$isValid, timestamp=$timestamp, playing=$isCurrentlyPlaying, type=$activityType")
            
            if (isValid) {
                FriendActivity(
                    friendName = friendName, 
                    trackName = friendTrack, 
                    artistName = friendArtist, 
                    friendImageUrl = friendImage, 
                    cachedImagePath = cachedImagePath, 
                    friendUserId = friendUserId,
                    timestamp = timestamp,
                    isCurrentlyPlaying = isCurrentlyPlaying,
                    activityType = activityType
                )
            } else null
        }
        
        android.util.Log.d("PlaytivityWidget", "Created activities list with ${activities.size} valid activities from $activitiesCount total")
        
        if (activities.isEmpty()) {
            // Show a message when no activities are available
            Box(
                modifier = GlanceModifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No recent friend activities",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 11.sp
                    )
                )
            }
        } else {
            // Use LazyColumn to efficiently handle the list
            LazyColumn(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .padding(vertical = 8.dp)
            ) {
                items(activities.size) { index ->
                    val activity = activities[index]
                    FriendActivityItem(
                        activity = activity,
                        onClick = if (activity.friendUserId.isNotEmpty()) {
                            actionRunCallback<LaunchSpotifyProfileCallback>(
                                parameters = actionParametersOf(LaunchSpotifyProfileCallback.userIdKey to activity.friendUserId)
                            )
                        } else {
                            actionStartActivity<MainActivity>()
                        }
                    )
                    // Only add spacer if not the last item
                    if (index < activities.size - 1) {
                        Spacer(modifier = GlanceModifier.height(6.dp))
                    }
                }
            }
        }
    }

    @Composable
    private fun FriendActivityItem(
        activity: FriendActivity,
        onClick: androidx.glance.action.Action
    ) {
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(GlanceTheme.colors.surfaceVariant)
                .padding(12.dp)
                .clickable(onClick)
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Friend profile image or fallback avatar
                if (activity.cachedImagePath.isNotEmpty() && java.io.File(activity.cachedImagePath).exists()) {
                    // Use the cached friend profile image
                    Image(
                        provider = ImageProvider(android.graphics.BitmapFactory.decodeFile(activity.cachedImagePath)),
                        contentDescription = "Friend profile",
                        modifier = GlanceModifier.size(32.dp)
                    )
                } else {
                    // Fallback to avatar with background circle
                    Box(
                        modifier = GlanceModifier
                            .size(32.dp)
                            .background(GlanceTheme.colors.primary)
                            .cornerRadius(16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            provider = ImageProvider(R.drawable.ic_person),
                            contentDescription = "Friend",
                            modifier = GlanceModifier.size(18.dp)
                        )
                    }
                }
                
                Spacer(modifier = GlanceModifier.width(12.dp))
                Column(
                    modifier = GlanceModifier.fillMaxWidth()
                ) {
                    Text(
                        text = activity.trackName,
                        style = TextStyle(
                            color = GlanceTheme.colors.onSurface,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        ),
                        maxLines = 2
                    )
                    Spacer(modifier = GlanceModifier.height(2.dp))
                    Text(
                        text = "${activity.friendName} • ${activity.artistName}",
                        style = TextStyle(
                            color = GlanceTheme.colors.onSurfaceVariant,
                            fontSize = 11.sp
                        ),
                        maxLines = 1
                    )
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    // Add status row with icon and text
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Image(
                            provider = ImageProvider(
                                if (activity.isRecentOrPlaying()) {
                                    R.drawable.ic_play_circle
                                } else {
                                    R.drawable.ic_history
                                }
                            ),
                            contentDescription = "Status",
                            modifier = GlanceModifier.size(12.dp)
                        )
                        Spacer(modifier = GlanceModifier.width(4.dp))
                        Text(
                            text = activity.getStatusText(),
                            style = TextStyle(
                                color = if (activity.isRecentOrPlaying()) {
                                    GlanceTheme.colors.primary
                                } else {
                                    GlanceTheme.colors.onSurfaceVariant
                                },
                                fontSize = 10.sp
                            ),
                            maxLines = 1
                        )
                    }
                }
            }
        }
    }
}