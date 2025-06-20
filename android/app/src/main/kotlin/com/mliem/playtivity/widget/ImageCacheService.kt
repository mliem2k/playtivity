package com.mliem.playtivity.widget

import android.app.IntentService
import android.content.Context
import android.content.Intent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import kotlinx.coroutines.runBlocking

class ImageCacheService : IntentService("ImageCacheService") {
    
    companion object {
        private const val ACTION_CACHE_IMAGES = "com.mliem.playtivity.CACHE_IMAGES"
        
        fun startImageCaching(context: Context) {
            val intent = Intent(context, ImageCacheService::class.java).apply {
                action = ACTION_CACHE_IMAGES
            }
            context.startService(intent)
        }
    }
    
    override fun onHandleIntent(intent: Intent?) {
        when (intent?.action) {
            ACTION_CACHE_IMAGES -> cacheAllFriendImages()
        }
    }
    
    private fun cacheAllFriendImages() {        try {
            android.util.Log.d("ImageCacheService", "Starting to cache friend images")
            
            val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val activitiesCount = prefs.getString("activities_count", "0")?.toIntOrNull() ?: 0
            
            runBlocking {
                var cachedCount = 0
                // Cache images for all friends (no longer limited to 5)
                for (i in 0 until activitiesCount) {
                    val friendImage = prefs.getString("friend_${i}_image", "") ?: ""
                    val friendName = prefs.getString("friend_${i}_name", "") ?: ""
                    
                    if (friendImage.isNotEmpty() && friendName.isNotEmpty()) {
                        // Only log first few to reduce noise
                        if (i < 2) {
                            android.util.Log.d("ImageCacheService", "Caching image for friend $i: $friendName")
                        }
                        val cachedPath = ImageDownloader.downloadAndCacheImage(this@ImageCacheService, friendImage, i)
                        
                        if (cachedPath != null) {
                            // Save the cached path to both preference sources for the widget to use
                            prefs.edit()
                                .putString("friend_${i}_cached_image", cachedPath)
                                .apply()
                            
                            // Also save to Flutter preferences as backup
                            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            flutterPrefs.edit()
                                .putString("flutter.friend_${i}_cached_image", cachedPath)
                                .apply()
                            
                            android.util.Log.d("ImageCacheService", "Saved cached image path for $friendName: $cachedPath")
                            cachedCount++
                        } else {
                            android.util.Log.w("ImageCacheService", "Failed to cache image for $friendName")
                        }
                    }                }
                
                if (cachedCount > 0) {
                    android.util.Log.d("ImageCacheService", "Cached $cachedCount images total")
                }
            }
            
            // Update all widgets after caching images
            val appWidgetManager = AppWidgetManager.getInstance(this)
            val componentName = ComponentName(this, PlaytivityWidgetReceiver::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            for (appWidgetId in appWidgetIds) {
                PlaytivityWidgetProvider.updateAppWidget(this, appWidgetManager, appWidgetId)
            }
            
            android.util.Log.d("ImageCacheService", "Image caching completed, widget updated")
            
        } catch (e: Exception) {
            android.util.Log.e("ImageCacheService", "Error caching images", e)
        }
    }
} 