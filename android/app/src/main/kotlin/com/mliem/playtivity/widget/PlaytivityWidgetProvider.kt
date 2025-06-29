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
import android.os.Bundle
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
    val activityType: String,
    val userId: String = ""
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
                    val userId = prefs.getString("friend_${i}_user_id", "") 
                        ?: flutterPrefs.getString("flutter.friend_${i}_user_id", "") ?: ""
                    
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
                                activityType = activityType,
                                userId = userId
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
                    
                    // Set up click template for individual items
                    val clickTemplate = Intent(context, MainActivity::class.java)
                    clickTemplate.action = "OPEN_FRIEND_PROFILE"
                    clickTemplate.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    val clickPendingTemplate = PendingIntent.getActivity(
                        context, 0, clickTemplate,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    )
                    views.setPendingIntentTemplate(R.id.activities_list, clickPendingTemplate)
                    
                    // Set empty view
                    views.setEmptyView(R.id.activities_list, R.id.empty_state)
                    
                    // Show activities list
                    views.setViewVisibility(R.id.activities_list, View.VISIBLE)
                    views.setViewVisibility(R.id.empty_state, View.GONE)
                    
                    // Update currently playing count
                    val currentlyPlayingCount = sortedActivities.count { it.isCurrentlyPlaying }
                } else {
                    showEmptyState(views)
                }
            } else {
                showEmptyState(views)
            }
            
            // Set click intent to open main app only for header area
            val mainIntent = Intent(context, MainActivity::class.java)
            val mainPendingIntent = PendingIntent.getActivity(
                context, 0, mainIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_title, mainPendingIntent)
            
            // Set refresh button click intent
            val refreshIntent = Intent(context, MainActivity::class.java)
            refreshIntent.action = "REFRESH_WIDGET"
            refreshIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            val refreshPendingIntent = PendingIntent.getActivity(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setOnClickPendingIntent(R.id.refresh_button, refreshPendingIntent)
            
            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
        
        private fun showEmptyState(views: RemoteViews) {
            views.setViewVisibility(R.id.activities_list, View.GONE)
            views.setViewVisibility(R.id.empty_state, View.VISIBLE)
        }
    }
}

class PlaytivityWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return PlaytivityWidgetItemFactory(applicationContext, intent)
    }
}

class PlaytivityWidgetItemFactory(
    private val context: Context,
    private val intent: Intent
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
        loadFriendImage(views, activity.cachedImagePath)
        
        // Set click intent to open friend profile only if we have a valid user ID
        if (activity.userId.isNotEmpty()) {
            val extras = Bundle()
            extras.putString("userId", activity.userId)
            extras.putString("friendName", activity.friendName)
            val fillInIntent = Intent()
            fillInIntent.putExtras(extras)
            views.setOnClickFillInIntent(R.id.widget_activity_item, fillInIntent)
        }
        
        return views
    }
    
    override fun getLoadingView(): RemoteViews? = null
    
    override fun getViewTypeCount(): Int = 1
    
    override fun getItemId(position: Int): Long = position.toLong()
    
    override fun hasStableIds(): Boolean = true
    
    private fun loadActivities() {
        activities.clear()
        
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        val activitiesCount = try {
            prefs.getString("activities_count", null)?.toIntOrNull() 
                ?: flutterPrefs.getString("flutter.activities_count", "0")?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            android.util.Log.w("PlaytivityWidget", "Error parsing activities_count", e)
            0
        }
        
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
            val userId = prefs.getString("friend_${i}_user_id", "") 
                ?: flutterPrefs.getString("flutter.friend_${i}_user_id", "") ?: ""
            
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
                        activityType = activityType,
                        userId = userId
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
    }
    
    private fun loadFriendImage(views: RemoteViews, cachedImagePath: String) {
        if (cachedImagePath.isNotEmpty()) {
            val file = File(cachedImagePath)
            if (file.exists() && file.canRead() && file.length() > 0) {
                try {
                    val bitmap = BitmapFactory.decodeFile(cachedImagePath)
                    if (bitmap != null && !bitmap.isRecycled) {
                        views.setImageViewBitmap(R.id.friend_image, bitmap)
                        return
                    }
                } catch (e: Exception) {
                    android.util.Log.e("PlaytivityWidget", "Error loading friend image", e)
                }
            }
        }
        
        // Fallback to default icon
        views.setImageViewResource(R.id.friend_image, R.drawable.ic_person)
    }
}