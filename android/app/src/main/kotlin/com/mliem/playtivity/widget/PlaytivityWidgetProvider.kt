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
    val friendUserId: String = ""
)

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
        
        for (i in 0..4) {
            val friendName = prefs.getString("friend_${i}_name", "") ?: ""
            val friendTrack = prefs.getString("friend_${i}_track", "") ?: ""
            val friendArtist = prefs.getString("friend_${i}_artist", "") ?: ""
            val friendImage = prefs.getString("friend_${i}_image", "") ?: ""
            android.util.Log.d("PlaytivityWidget", "  friend_${i}: $friendName - $friendTrack by $friendArtist (image: $friendImage)")
        }
        
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
        // Create a list of valid activities, limited to 5 to stay within the 10 element Column limit
        // Each activity item + spacer = 2 elements, so 5 activities = 10 elements maximum
        val activities = (0 until minOf(activitiesCount, 5)).mapNotNull { index ->
            val friendName = prefs.getString("friend_${index}_name", "") ?: ""
            val friendTrack = prefs.getString("friend_${index}_track", "") ?: ""
            val friendArtist = prefs.getString("friend_${index}_artist", "") ?: ""
            val friendImage = prefs.getString("friend_${index}_image", "") ?: ""
            val cachedImagePath = prefs.getString("friend_${index}_cached_image", "") ?: ""
            val friendUserId = prefs.getString("friend_${index}_user_id", "") ?: ""
            
            if (friendName.isNotEmpty() && friendTrack.isNotEmpty()) {
                FriendActivity(friendName, friendTrack, friendArtist, friendImage, cachedImagePath, friendUserId)
            } else null
        }
        
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(vertical = 8.dp)
        ) {
            if (activities.isEmpty()) {
                // Show a message when no activities are available
                Text(
                    text = "No recent friend activities",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 11.sp
                    ),
                    modifier = GlanceModifier.padding(horizontal = 8.dp)
                )
            } else {
                activities.forEachIndexed { index, activity ->
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
                    // Only add spacer if not the last item to avoid unnecessary elements
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
                .cornerRadius(12.dp)
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
                }
            }
        }
    }
}