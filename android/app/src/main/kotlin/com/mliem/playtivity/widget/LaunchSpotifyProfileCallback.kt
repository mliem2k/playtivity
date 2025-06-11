package com.mliem.playtivity.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback

/**
 * Action callback to launch Spotify to a friend's profile
 */
class LaunchSpotifyProfileCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val userId = parameters[userIdKey] ?: ""
        
        if (userId.isNotEmpty()) {
            try {
                // Try to launch Spotify app with user profile URI
                val spotifyUri = "spotify:user:$userId"
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(spotifyUri)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    setPackage("com.spotify.music") // Prefer Spotify app
                }
                
                // Check if Spotify app is available
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    android.util.Log.d("LaunchSpotifyProfile", "Launched Spotify app for user: $userId")
                } else {
                    // Fallback to web browser
                    val webUrl = "https://open.spotify.com/user/$userId"
                    val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse(webUrl)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(webIntent)
                    android.util.Log.d("LaunchSpotifyProfile", "Launched Spotify web for user: $userId")
                }
            } catch (e: Exception) {
                android.util.Log.e("LaunchSpotifyProfile", "Error launching Spotify profile", e)
            }
        } else {
            android.util.Log.w("LaunchSpotifyProfile", "No user ID provided")
        }
    }
    
    companion object {
        val userIdKey = ActionParameters.Key<String>("userId")
    }
} 