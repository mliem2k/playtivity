package com.mliem.playtivity.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.mliem.playtivity.MainActivity
import com.mliem.playtivity.R
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

data class ActivityItem(
    val friendName: String,
    val trackName: String,
    val artistName: String,
    val cachedImagePath: String,
    val timestamp: Long,
    val isCurrentlyPlaying: Boolean,
    val activityType: String
) {
    fun getTimeAgoText(): String {
        if (isCurrentlyPlaying) {
            return "Listening now"
        }
        
        val currentTime = System.currentTimeMillis()
        val diffMinutes = (currentTime - timestamp) / (1000 * 60)
        
        return when {
            diffMinutes < 1 -> "Just now"
            diffMinutes < 60 -> "${diffMinutes}m ago"
            diffMinutes < 1440 -> "${diffMinutes / 60}h ago"
            diffMinutes < 10080 -> "${diffMinutes / 1440}d ago"
            else -> {
                val date = Date(timestamp)
                SimpleDateFormat("MMM dd", Locale.getDefault()).format(date)
            }
        }
    }
}

class PlaytivityWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            android.util.Log.d("PlaytivityWidget", "Updating widget $appWidgetId")
            
            // Create RemoteViews
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            
            // Read widget data from SharedPreferences
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            val activitiesCount = try {
                prefs.getString("activities_count", null)?.toIntOrNull() 
                    ?: flutterPrefs.getString("flutter.activities_count", "0")?.toIntOrNull() ?: 0
            } catch (e: Exception) {
                android.util.Log.w("PlaytivityWidget", "Error parsing activities_count", e)
                0
            }
            
            android.util.Log.d("PlaytivityWidget", "Widget data: activitiesCount=$activitiesCount")
            
            if (activitiesCount > 0) {
                // Parse all activities
                val activities = mutableListOf<ActivityItem>()
                
                for (i in 0 until activitiesCount) {
                    val friendName = prefs.getString("friend_${i}_name", "") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_name", "") ?: ""
                    val trackName = prefs.getString("friend_${i}_track", "") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_track", "") ?: ""
                    val artistName = prefs.getString("friend_${i}_artist", "") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_artist", "") ?: ""
                    val cachedImagePath = prefs.getString("friend_${i}_cached_image", "") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_cached_image", "") ?: ""
                    val timestampString = prefs.getString("friend_${i}_timestamp", "0") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_timestamp", "0") ?: "0"
                    val isCurrentlyPlayingString = prefs.getString("friend_${i}_is_currently_playing", "false") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_is_currently_playing", "false") ?: "false"
                    val activityType = prefs.getString("friend_${i}_activity_type", "track") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_activity_type", "track") ?: "track"
                    
                    val timestamp = try {
                        timestampString.toLongOrNull() ?: System.currentTimeMillis()
                    } catch (e: Exception) {
                        System.currentTimeMillis()
                    }
                    
                    val isCurrentlyPlaying = try {
                        isCurrentlyPlayingString.toBoolean()
                    } catch (e: Exception) {
                        false
                    }
                    
                    if (friendName.isNotEmpty() && trackName.isNotEmpty()) {
                        activities.add(
                            ActivityItem(
                                friendName = friendName,
                                trackName = trackName,
                                artistName = artistName,
                                cachedImagePath = cachedImagePath,
                                timestamp = timestamp,
                                isCurrentlyPlaying = isCurrentlyPlaying,
                                activityType = activityType
                            )
                        )
                    }
                }
                
                if (activities.isNotEmpty()) {
                    // Sort activities by timestamp (most recent first)
                    val sortedActivities = activities.sortedWith { a, b ->
                        when {
                            a.isCurrentlyPlaying && !b.isCurrentlyPlaying -> -1
                            !a.isCurrentlyPlaying && b.isCurrentlyPlaying -> 1
                            else -> b.timestamp.compareTo(a.timestamp)
                        }
                    }
                    
                    // Set up ListView with adapter
                    val intent = Intent(context, PlaytivityWidgetService::class.java)
                    intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    views.setRemoteAdapter(R.id.activities_list, intent)
                    
                    // Set empty view
                    views.setEmptyView(R.id.activities_list, R.id.empty_state)
                    
                    // Show activities list
                    views.setViewVisibility(R.id.activities_list, View.VISIBLE)
                    views.setViewVisibility(R.id.empty_state, View.GONE)
                    
                    // Update activity count in header
                    val currentlyPlayingCount = sortedActivities.count { it.isCurrentlyPlaying }
                    val countText = if (currentlyPlayingCount > 0) {
                        "$currentlyPlayingCount live"
                    } else {
                        "${sortedActivities.size} total"
                    }
                    views.setTextViewText(R.id.activity_count, countText)
                    views.setViewVisibility(R.id.activity_count, View.VISIBLE)
                    
                    android.util.Log.d("PlaytivityWidget", "Showing ${sortedActivities.size} activities, $currentlyPlayingCount currently playing")
                } else {
                    showEmptyState(views)
                }
            } else {
                showEmptyState(views)
            }
            
            // Set click intent to open main app
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            
            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.activities_list)
            android.util.Log.d("PlaytivityWidget", "Widget update completed")
        }
        
        private fun showEmptyState(views: RemoteViews) {
            views.setViewVisibility(R.id.activities_list, View.GONE)
            views.setViewVisibility(R.id.empty_state, View.VISIBLE)
            views.setViewVisibility(R.id.activity_count, View.GONE)
        }
    }
}

class PlaytivityWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return PlaytivityWidgetRemoteViewsFactory(this.applicationContext, intent)
    }
}

class PlaytivityWidgetRemoteViewsFactory(
    private val context: Context,
    intent: Intent
) : RemoteViewsService.RemoteViewsFactory {
    
    private var activities = mutableListOf<ActivityItem>()
    private val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
    
    override fun onCreate() {
        // Nothing to do
    }
    
    override fun onDataSetChanged() {
        loadActivities()
    }
    
    override fun onDestroy() {
        activities.clear()
    }
    
    override fun getCount(): Int = activities.size
    
    override fun getViewAt(position: Int): RemoteViews {
        if (position >= activities.size) {
            return RemoteViews(context.packageName, R.layout.widget_activity_item)
        }
        
        val activity = activities[position]
        val views = RemoteViews(context.packageName, R.layout.widget_activity_item)
        
        // Set track name
        views.setTextViewText(R.id.track_name, activity.trackName)
        
        // Set friend and artist
        views.setTextViewText(R.id.friend_artist, "${activity.friendName} • ${activity.artistName}")
        
        // Set timestamp
        views.setTextViewText(R.id.timestamp, activity.getTimeAgoText())
        
        // Set status indicator
        if (activity.isCurrentlyPlaying) {
            views.setViewVisibility(R.id.status_indicator, View.VISIBLE)
            views.setTextViewText(R.id.status_indicator, "🎵")
        } else {
            views.setViewVisibility(R.id.status_indicator, View.GONE)
        }
        
        // Load friend image
        loadFriendImage(views, activity.cachedImagePath, activity.friendName)
        
        // Set click intent
        val clickIntent = Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context, 
            position, 
            clickIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickFillInIntent(R.id.friend_image, clickIntent)
        
        return views
    }
    
    override fun getLoadingView(): RemoteViews? = null
    
    override fun getViewTypeCount(): Int = 1
    
    override fun getItemId(position: Int): Long = position.toLong()
    
    override fun hasStableIds(): Boolean = true
    
    private fun loadActivities() {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        val activitiesCount = try {
            prefs.getString("activities_count", null)?.toIntOrNull() 
                ?: flutterPrefs.getString("flutter.activities_count", "0")?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            0
        }
        
        android.util.Log.d("PlaytivityWidget", "Loading $activitiesCount activities for widget")
        activities.clear()
        
        for (i in 0 until activitiesCount) {
            val friendName = prefs.getString("friend_${i}_name", "") 
                ?: flutterPrefs.getString("flutter.friend_${i}_name", "") ?: ""
            val trackName = prefs.getString("friend_${i}_track", "") 
                ?: flutterPrefs.getString("flutter.friend_${i}_track", "") ?: ""
            val artistName = prefs.getString("friend_${i}_artist", "") 
                ?: flutterPrefs.getString("flutter.friend_${i}_artist", "") ?: ""
            val cachedImagePath = prefs.getString("friend_${i}_cached_image", "") 
                ?: flutterPrefs.getString("flutter.friend_${i}_cached_image", "") ?: ""
            val timestampString = prefs.getString("friend_${i}_timestamp", "0") 
                ?: flutterPrefs.getString("flutter.friend_${i}_timestamp", "0") ?: "0"
            val isCurrentlyPlayingString = prefs.getString("friend_${i}_is_currently_playing", "false") 
                ?: flutterPrefs.getString("flutter.friend_${i}_is_currently_playing", "false") ?: "false"
            val activityType = prefs.getString("friend_${i}_activity_type", "track") 
                ?: flutterPrefs.getString("flutter.friend_${i}_activity_type", "track") ?: "track"
            
            val timestamp = try {
                timestampString.toLongOrNull() ?: System.currentTimeMillis()
            } catch (e: Exception) {
                System.currentTimeMillis()
            }
            
            val isCurrentlyPlaying = try {
                isCurrentlyPlayingString.toBoolean()
            } catch (e: Exception) {
                false
            }
            
            if (friendName.isNotEmpty() && trackName.isNotEmpty()) {
                android.util.Log.d("PlaytivityWidget", "Activity $i: $friendName, cached image: $cachedImagePath")
                activities.add(
                    ActivityItem(
                        friendName = friendName,
                        trackName = trackName,
                        artistName = artistName,
                        cachedImagePath = cachedImagePath,
                        timestamp = timestamp,
                        isCurrentlyPlaying = isCurrentlyPlaying,
                        activityType = activityType
                    )
                )
            }
        }
        
        // Sort activities by timestamp (most recent first)
        activities.sortWith { a, b ->
            when {
                a.isCurrentlyPlaying && !b.isCurrentlyPlaying -> -1
                !a.isCurrentlyPlaying && b.isCurrentlyPlaying -> 1
                else -> b.timestamp.compareTo(a.timestamp)
            }
        }
        
        android.util.Log.d("PlaytivityWidget", "Loaded ${activities.size} activities for ListView")
    }
    
    private fun loadFriendImage(views: RemoteViews, cachedImagePath: String, friendName: String) {
        android.util.Log.d("PlaytivityWidget", "Loading image for $friendName, path: $cachedImagePath")
        
        if (cachedImagePath.isNotEmpty()) {
            val file = File(cachedImagePath)
            android.util.Log.d("PlaytivityWidget", "File exists: ${file.exists()}, readable: ${file.canRead()}, size: ${file.length()}")
            
            if (file.exists() && file.canRead() && file.length() > 0) {
                try {
                    val bitmap = BitmapFactory.decodeFile(cachedImagePath)
                    if (bitmap != null && !bitmap.isRecycled) {
                        android.util.Log.d("PlaytivityWidget", "Successfully loaded bitmap for $friendName (${bitmap.width}x${bitmap.height})")
                        views.setImageViewBitmap(R.id.friend_image, bitmap)
                        return
                    } else {
                        android.util.Log.w("PlaytivityWidget", "Failed to decode bitmap for $friendName")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("PlaytivityWidget", "Exception loading image for $friendName", e)
                }
            } else {
                android.util.Log.w("PlaytivityWidget", "Image file not accessible for $friendName: exists=${file.exists()}, readable=${file.canRead()}, size=${file.length()}")
            }
        } else {
            android.util.Log.d("PlaytivityWidget", "No cached image path for $friendName")
        }
        
        // Fallback to default icon
        android.util.Log.d("PlaytivityWidget", "Using default icon for $friendName")
        views.setImageViewResource(R.id.friend_image, R.drawable.ic_person)
    }
}