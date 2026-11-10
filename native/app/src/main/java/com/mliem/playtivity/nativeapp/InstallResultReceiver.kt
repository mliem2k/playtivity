package com.mliem.playtivity.nativeapp

import android.content.Context
import com.mliem.android.update.InstallResultReceiver as CoreInstallResultReceiver
import com.mliem.android.update.UpdateClient

/** Receives the system installer's result and hands it to the shared update client. */
class InstallResultReceiver : CoreInstallResultReceiver() {
    override fun updateClient(context: Context): UpdateClient =
        (context.applicationContext as PlaytivityApp).updates
}
