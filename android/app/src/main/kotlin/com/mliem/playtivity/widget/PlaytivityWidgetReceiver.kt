package com.mliem.playtivity.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class PlaytivityWidgetReceiver : AppWidgetProvider() {
    
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        for (appWidgetId in appWidgetIds) {
            PlaytivityWidgetProvider.updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
    
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        android.util.Log.d("PlaytivityWidget", "Widget enabled")
    }
    
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        android.util.Log.d("PlaytivityWidget", "Widget disabled")
    }
}
