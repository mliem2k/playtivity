package com.mliem.playtivity

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.mliem.playtivity.widget.PlaytivityWidgetReceiver
import com.mliem.playtivity.widget.PlaytivityAppWidget
import com.mliem.playtivity.widget.ImageCacheService
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "playtivity_widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    updateWidget()
                    result.success("Widget update triggered")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun updateWidget() {
        try {
            // Use direct Glance updateAll approach
            CoroutineScope(Dispatchers.Main).launch {
                // Add a small delay to ensure SharedPreferences data is committed
                delay(100)
                
                // Log both SharedPreferences to see where data is being saved
                val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                val homeWidgetPrefs = getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
                
                val flutterActivitiesCount = flutterPrefs.getString("flutter.activities_count", "0")
                val homeWidgetActivitiesCount = homeWidgetPrefs.getString("activities_count", "0")
                
                android.util.Log.d("PlaytivityWidget", "Before update - FlutterSharedPreferences activities_count: $flutterActivitiesCount")
                android.util.Log.d("PlaytivityWidget", "Before update - HomeWidgetPreferences activities_count: $homeWidgetActivitiesCount")
                
                // Start image caching service first
                ImageCacheService.startImageCaching(this@MainActivity)
                android.util.Log.d("PlaytivityWidget", "Image caching service started")
                
                // Update the widget using direct Glance updateAll
                PlaytivityAppWidget().updateAll(this@MainActivity)
                android.util.Log.d("PlaytivityWidget", "Direct Glance widget update triggered")
            }
        } catch (e: Exception) {
            android.util.Log.e("PlaytivityWidget", "Error updating widget", e)
        }
    }
}
