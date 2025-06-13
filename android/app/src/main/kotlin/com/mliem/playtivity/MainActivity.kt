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
    }    private fun updateWidget() {
        try {
            // Use direct Glance updateAll approach
            CoroutineScope(Dispatchers.Main).launch {
                // Reduced delay for faster widget updates
                delay(50)
                
                // Reduced logging for better performance
                val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                val flutterActivitiesCount = flutterPrefs.getString("flutter.activities_count", "0")
                
                android.util.Log.d("PlaytivityWidget", "Widget update triggered with $flutterActivitiesCount activities")
                
                // Start image caching service first
                ImageCacheService.startImageCaching(this@MainActivity)
                
                // Update the widget using direct Glance updateAll
                PlaytivityAppWidget().updateAll(this@MainActivity)
                android.util.Log.d("PlaytivityWidget", "Widget update completed")
            }
        } catch (e: Exception) {
            android.util.Log.e("PlaytivityWidget", "Error updating widget", e)
        }
    }
}
