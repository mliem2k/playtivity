package com.mliem.playtivity.nativeapp

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.mliem.playtivity.core.Activity
import com.mliem.playtivity.core.mergeActivities
import com.mliem.playtivity.core.sortForWidget
import com.mliem.playtivity.core.spotifyUrl
import com.mliem.playtivity.core.widgetTimeText

class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    private class Factory(private val context: Context) : RemoteViewsFactory {
        private var activities: List<Activity> = emptyList()

        override fun onCreate() = onDataSetChanged()

        override fun onDataSetChanged() {
            val app = context.applicationContext as PlaytivityApp
            activities = sortForWidget(mergeActivities(app.activityCache.load(), emptyList()))
        }

        override fun onDestroy() {
            activities = emptyList()
        }

        override fun getCount(): Int = activities.size

        override fun getViewAt(position: Int): RemoteViews? {
            val activity = activities.getOrNull(position) ?: return null
            return widgetRow(context, activity)
        }

        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount(): Int = 1
        override fun getItemId(position: Int): Long = activities.getOrNull(position)?.user?.id?.hashCode()?.toLong() ?: position.toLong()
        override fun hasStableIds(): Boolean = true
    }
}

internal fun widgetRow(context: Context, activity: Activity): RemoteViews =
    RemoteViews(context.packageName, R.layout.widget_friend_activity_row).apply {
        setTextViewText(R.id.widget_friend, activity.user.displayName)
        setTextViewText(R.id.widget_time, widgetTimeText(activity))
        setTextViewText(R.id.widget_track, activity.track?.name ?: activity.playlist?.name.orEmpty())
        setTextViewText(R.id.widget_artist, activity.track?.artists?.joinToString(", ") ?: activity.playlist?.ownerName.orEmpty())
        val uri = activity.track?.uri ?: activity.playlist?.uri.orEmpty()
        if (uri.isNotEmpty()) {
            setOnClickFillInIntent(R.id.widget_item, Intent().putExtra("spotify_url", spotifyUrl(uri)))
        }
    }
