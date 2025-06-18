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

class MainActivity : FlutterActivity() {    private val WIDGET_CHANNEL = "playtivity_widget"
    private val UPDATE_CHANNEL = "com.mliem.playtivity/update_launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Widget channel for home screen widget updates
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
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
        
        // Update channel for APK installation
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        installApk(filePath, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "File path is required", null)
                    }
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
    
    // Handle APK installation using FileProvider
    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found at $filePath", null)
                return
            }
            
            android.util.Log.d("Playtivity", "Installing APK from $filePath")
              // Create content URI using FileProvider
            val contentUri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            
            // Create intent to install the APK
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            
            // Start the installation activity
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("Playtivity", "Error installing APK", e)
            result.error("INSTALLATION_ERROR", "Error installing APK: ${e.message}", null)
        }
    }
}
