package com.mliem.playtivity.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import android.net.Uri

/**
 * Action callback to refresh the widget
 */
class RefreshWidgetCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        // Trigger a background intent to refresh the widget data
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context, 
            Uri.parse("playtivity://refresh")
        )
        backgroundIntent.send()
    }
}