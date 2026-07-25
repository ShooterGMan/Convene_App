package com.convene.convene

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Android requires an active foreground service of type "mediaProjection"
 * running BEFORE screen capture starts (since Android 10, more strictly
 * enforced from Android 14) - otherwise MediaProjection.createVirtualDisplay
 * throws and screen share silently fails. flutter_webrtc (used by
 * livekit_client) does not start one itself, so the app has to.
 */
class ScreenShareForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "screen_share_channel"
        private const val NOTIFICATION_ID = 4201
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen sharing",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Convene")
            .setContentText("Your screen is being shared in the meeting")
            .setSmallIcon(R.mipmap.launcher_icon)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
