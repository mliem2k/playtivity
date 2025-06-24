package com.mliem.playtivity

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.mliem.playtivity.widget.PlaytivityWidgetReceiver
import com.mliem.playtivity.widget.PlaytivityWidgetProvider
import com.mliem.playtivity.widget.ImageCacheService
import android.app.PendingIntent

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
                "cacheImages" -> {
                    ImageCacheService.startImageCaching(this)
                    result.success("Image caching started")
                }
                "openFriendProfile" -> {
                    val userId = call.argument<String>("userId")
                    val friendName = call.argument<String>("friendName")
                    if (userId != null) {
                        openSpotifyProfile(userId, friendName)
                        result.success("Profile opened")
                    } else {
                        result.error("INVALID_ARGUMENTS", "User ID is required", null)
                    }
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
                "installApkDirect" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        installApkDirect(filePath, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "File path is required", null)
                    }
                }
                "canInstallPackages" -> {
                    result.success(canInstallPackages())
                }
                "requestInstallPermission" -> {
                    requestInstallPermission(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }
    
    override fun onResume() {
        super.onResume()
        handleWidgetIntent(intent)
    }
    
    private fun handleWidgetIntent(intent: Intent?) {
        android.util.Log.d("PlaytivityWidget", "handleWidgetIntent called with intent: $intent")
        intent?.let {
            android.util.Log.d("PlaytivityWidget", "Intent action: ${it.action}")
            android.util.Log.d("PlaytivityWidget", "Intent extras: ${it.extras}")
            
            when (it.action) {
                "OPEN_FRIEND_PROFILE" -> {
                    val friendUserId = it.getStringExtra("friendUserId")
                    val friendName = it.getStringExtra("friendName")
                    
                    android.util.Log.d("PlaytivityWidget", "Opening friend profile: $friendName (ID: $friendUserId)")
                    
                    if (!friendUserId.isNullOrEmpty()) {
                        // Try to open Spotify profile
                        openSpotifyProfile(friendUserId, friendName)
                    } else {
                        android.util.Log.w("PlaytivityWidget", "Friend user ID is null or empty!")
                    }
                }
                "REFRESH_WIDGET" -> {
                    android.util.Log.d("PlaytivityWidget", "Refresh widget requested")
                    updateWidget()
                }
                else -> {
                    android.util.Log.d("PlaytivityWidget", "Unknown action: ${it.action}")
                }
            }
        }
    }
    
    private fun openSpotifyProfile(userId: String, friendName: String?) {
        try {
            // Create Spotify user URI
            val spotifyUri = "spotify:user:$userId"
            val spotifyIntent = Intent(Intent.ACTION_VIEW, Uri.parse(spotifyUri))
            
            android.util.Log.d("PlaytivityWidget", "Attempting to open Spotify profile: $spotifyUri")
            
            // Try to open in Spotify app first
            spotifyIntent.setPackage("com.spotify.music")
            if (spotifyIntent.resolveActivity(packageManager) != null) {
                startActivity(spotifyIntent)
                android.util.Log.d("PlaytivityWidget", "Opened in Spotify app")
                return
            }
            
            // Fallback to web browser
            val webUrl = "https://open.spotify.com/user/$userId"
            val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse(webUrl))
            
            if (webIntent.resolveActivity(packageManager) != null) {
                startActivity(webIntent)
                android.util.Log.d("PlaytivityWidget", "Opened in web browser: $webUrl")
            } else {
                android.util.Log.w("PlaytivityWidget", "No app found to open Spotify profile")
            }
            
        } catch (e: Exception) {
            android.util.Log.e("PlaytivityWidget", "Error opening Spotify profile for $userId", e)
        }
    }

    private fun updateWidget() {
        try {
            // Check both SharedPreferences sources
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val homeWidgetPrefs = getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
            val flutterActivitiesCount = flutterPrefs.getString("flutter.activities_count", "0")
            val homeWidgetActivitiesCount = homeWidgetPrefs.getString("activities_count", "0")
            
            android.util.Log.d("PlaytivityWidget", "Widget update triggered - Flutter: $flutterActivitiesCount, HomeWidget: $homeWidgetActivitiesCount activities")
            
            // Start image caching service first
            ImageCacheService.startImageCaching(this)
            
            // Update all widgets using traditional AppWidgetManager
            val appWidgetManager = AppWidgetManager.getInstance(this)
            val componentName = ComponentName(this, PlaytivityWidgetReceiver::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            for (appWidgetId in appWidgetIds) {
                PlaytivityWidgetProvider.updateAppWidget(this, appWidgetManager, appWidgetId)
            }
            
            android.util.Log.d("PlaytivityWidget", "Widget update completed")
        } catch (e: Exception) {
            android.util.Log.e("PlaytivityWidget", "Error updating widget", e)
        }
    }
    
    // Check if the app can install packages
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true // On older versions, this permission is granted by default
        }
    }
    
    // Request install permission for Android 8.0+
    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                android.util.Log.d("Playtivity", "Requesting install packages permission")
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                try {
                    startActivity(intent)
                    result.success("PERMISSION_REQUESTED")
                } catch (e: Exception) {
                    android.util.Log.e("Playtivity", "Error requesting install permission: ${e.message}", e)
                    result.error("PERMISSION_REQUEST_FAILED", "Failed to open permission settings", e.toString())
                }
            } else {
                result.success("PERMISSION_ALREADY_GRANTED")
            }
        } else {
            result.success("PERMISSION_NOT_REQUIRED")
        }
    }

    // Handle APK installation using FileProvider
    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            // Check if we have permission to install packages on Android 8.0+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                android.util.Log.e("Playtivity", "No permission to install packages. User needs to enable 'Unknown sources' for this app.")
                result.error("PERMISSION_DENIED", "Permission to install packages is required. Please enable 'Unknown sources' for Playtivity in your device settings.", null)
                return
            }
            
            val file = java.io.File(filePath)
            if (!file.exists()) {
                android.util.Log.e("Playtivity", "APK file not found at $filePath")
                result.error("FILE_NOT_FOUND", "APK file not found at $filePath", null)
                return
            }
            
            android.util.Log.d("Playtivity", "Installing APK from $filePath (size: ${file.length()} bytes)")
            
            // Create content URI using FileProvider
            val contentUri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            
            android.util.Log.d("Playtivity", "FileProvider URI: $contentUri")
            
            // Create intent to install the APK
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            
            // Check if there's an app that can handle this intent
            val packageManager = packageManager
            val activities = packageManager.queryIntentActivities(intent, 0)
            
            if (activities.isEmpty()) {
                android.util.Log.e("Playtivity", "No app found to handle APK installation")
                result.error("NO_HANDLER", "No app found to handle APK installation", null)
                return
            }
            
            android.util.Log.d("Playtivity", "Found ${activities.size} apps that can handle APK installation")
            
            // Start the installation activity
            startActivity(intent)
            android.util.Log.d("Playtivity", "APK installation intent started successfully")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("Playtivity", "Error installing APK: ${e.message}", e)
            result.error("INSTALLATION_ERROR", "Error installing APK: ${e.message}", e.toString())
        }
    }
    
    // Alternative installation method using standard Intent
    private fun installApkDirect(filePath: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(filePath)
            if (!file.exists()) {
                android.util.Log.e("Playtivity", "APK file not found at $filePath")
                result.error("FILE_NOT_FOUND", "APK file not found at $filePath", null)
                return
            }
            
            android.util.Log.d("Playtivity", "Installing APK directly from $filePath")
            
            // Create file URI directly
            val fileUri = android.net.Uri.fromFile(file)
            
            // Create intent to install the APK
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            
            // Start the installation activity
            startActivity(intent)
            android.util.Log.d("Playtivity", "Direct APK installation intent started successfully")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("Playtivity", "Error installing APK directly: ${e.message}", e)
            result.error("INSTALLATION_ERROR", "Error installing APK directly: ${e.message}", e.toString())
        }
    }
}
