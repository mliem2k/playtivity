package com.mliem.playtivity.nativeapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import com.mliem.playtivity.core.mergeActivities
import com.mliem.playtivity.core.parseFriends
import com.mliem.playtivity.core.sortForWidget
import com.mliem.playtivity.widget.PlaytivityWidgetReceiver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch

open class FriendActivityWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context)
        refresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) refresh(context)
    }

    private fun refresh(context: Context) {
        val pending = goAsync()
        val app = context.applicationContext as PlaytivityApp
        synchronized(app.sessions) {
            refreshScope.launch {
                try {
                    val cookie = app.sessions.readCookie() ?: return@launch
                    var token = app.spotify.fetchBearerToken(cookie)
                    if (token == null) {
                        app.secrets.refresh()
                        token = app.spotify.fetchBearerToken(cookie)
                    }
                    val body = token?.let { app.spotify.fetchBuddyList(it) } ?: return@launch
                    val merged = mergeActivities(app.activityCache.load(), parseFriends(body))
                    synchronized(app.sessions) {
                        if (app.sessions.readCookie() != cookie) return@synchronized
                        if (merged.isNotEmpty()) app.activityCache.save(merged)
                        render(context)
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    render(context)
                }
            }.invokeOnCompletion { pending.finish() }
        }
    }

    companion object {
        private const val ACTION_REFRESH = "com.mliem.playtivity.nativeapp.REFRESH_WIDGET"
        private val refreshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        fun cancelRefreshes() {
            refreshScope.coroutineContext.cancelChildren()
        }

        fun render(context: Context) = synchronized((context.applicationContext as PlaytivityApp).sessions) {
            val app = context.applicationContext as PlaytivityApp
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, PlaytivityWidgetReceiver::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return@synchronized
            val rows = sortForWidget(mergeActivities(app.activityCache.load(), emptyList()))
            val useCollection = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && rows.size <= 20 && rows.all { activity ->
                listOfNotNull(activity.user.imageUrl, activity.track?.imageUrl ?: activity.playlist?.imageUrl)
                    .all { url -> WidgetArtwork.cached(context, url) != null }
            }
            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.widget_friend_activity)
                val refresh = Intent(context, PlaytivityWidgetReceiver::class.java).setAction(ACTION_REFRESH)
                val pending = PendingIntent.getBroadcast(context, id, refresh, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.widget_refresh, pending)
                val openApp = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(R.id.widget_title, openApp)
                if (useCollection) {
                    val items = RemoteViews.RemoteCollectionItems.Builder()
                    rows.forEach { activity -> items.addItem(activity.user.id.hashCode().toLong(), widgetRow(context, activity)) }
                    views.setRemoteAdapter(R.id.widget_list, items.build())
                } else {
                    setLegacyAdapter(context, id, views)
                }
                views.setEmptyView(R.id.widget_list, R.id.widget_empty)
                val clickFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val clickTemplate = PendingIntent.getActivity(context, id + 100_000, Intent(context, MainActivity::class.java), clickFlags)
                views.setPendingIntentTemplate(R.id.widget_list, clickTemplate)
                manager.updateAppWidget(id, views)
            }
            if (!useCollection) notifyLegacyList(manager, ids)
        }

        @Suppress("DEPRECATION")
        private fun setLegacyAdapter(context: Context, id: Int, views: RemoteViews) {
            val intent = Intent(context, WidgetListService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .apply { data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME)) }
            views.setRemoteAdapter(R.id.widget_list, intent)
        }

        @Suppress("DEPRECATION")
        private fun notifyLegacyList(manager: AppWidgetManager, ids: IntArray) {
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }
    }
}
